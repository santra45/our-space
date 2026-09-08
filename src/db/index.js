/**
 * src/db/index.js
 * IndexedDB persistence layer using Dexie.js
 *
 * SCHEMA v2 - ENCRYPTED METADATA
 * v1 stored record metadata (`date`, `category`, `unlockDate`, `completed`,
 * `completedAt`, `isOpened`) in PLAINTEXT and indexed it, which leaked the shape
 * of the couple's life to anyone who opened devtools. v2 folds every field into
 * one AES-GCM envelope. Only three things stay readable without the key:
 *
 *   id         string   primary key, needed to address a record over sync
 *   updatedAt  number   last-write-wins comparison, needed without decrypting
 *   deleted    boolean  tombstone, needed so deletions replicate
 *
 * Everything else lives inside `ciphertext`/`iv`. Filtering and sorting that
 * used to be an index query is now an in-memory filter after decryptRecord().
 *
 * WHY `_del` EXISTS
 * IndexedDB refuses boolean index keys, so a declared `deleted` index silently
 * indexes nothing. `_del` is its 0/1 mirror, maintained automatically by Dexie
 * hooks below so no calling code has to know about it. It is what makes
 * getManifest() able to report tombstones from a key cursor, without loading
 * every encrypted photo into memory.
 *
 * WHY THE IMPORT SPECIFIERS BELOW CARRY `.js`
 * Vite resolves extensionless relative imports; plain Node does not. Spelling
 * the extension keeps this module (and peerSync, which it is cyclic with)
 * loadable by `node test-crypto.mjs`, which is how the backup-merge and
 * identity-restore paths that guard irreplaceable data get tested at all. Do not
 * strip them for tidiness - that silently removes those paths from the suite.
 */
import Dexie from 'dexie';
import {
  RECORD_SCHEMA_VERSION,
  PBKDF2_ITERATIONS_LEGACY,
  bufferToBase64,
  base64ToBuffer,
  decryptRecord,
  encryptRecord,
  isLegacyRecord,
  recordCarriesAuthenticatedPayload,
  recordHasAuthenticatedHeader,
} from '../services/crypto.js';

/** Tables that participate in P2P sync and in backups. */
export const SYNCED_TABLES = Object.freeze([
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
]);

/**
 * Tables an ordinary MERGE import is allowed to write into.
 *
 * `vaultMeta` is deliberately ABSENT here. It holds the salt and canary that key
 * the entire vault; letting a routine restore overwrite them re-keys the vault
 * and orphans every record created since the backup was taken.
 *
 * The one place vaultMeta may legitimately come out of a backup is the explicit
 * IDENTITY RESTORE flow - restoreVaultIdentity() below, driven by
 * VaultContext.restoreVaultFromBackup(). That path adopts the backup's salt on
 * purpose, verified against the backup's own canary, behind the same
 * confirmation phrase that guards every other salt replacement.
 */
export const IMPORTABLE_TABLES = new Set(SYNCED_TABLES);

/** Tables written into a backup container. */
export const EXPORTED_TABLES = Object.freeze(['vaultMeta', ...SYNCED_TABLES]);

/** Hard ceiling on a .vault file, checked before it is read into a string. */
export const MAX_BACKUP_FILE_BYTES = 150 * 1024 * 1024;

/** Ceiling on records accepted from one table in one restore. */
export const MAX_RECORDS_PER_TABLE = 20000;

/** Ceiling on a single decoded image blob accepted from a backup or a peer. */
export const MAX_IMAGE_BLOB_BYTES = 32 * 1024 * 1024;

const BULK_WRITE_CHUNK = 100;

/**
 * A record stamped further ahead than this is a clock artefact, not history.
 * Matches the ceiling peerSync applies to inbound records.
 */
const MAX_BACKUP_CLOCK_SKEW_MS = 48 * 60 * 60 * 1000;

export class SweetheartDatabase extends Dexie {
  constructor() {
    super('SweetheartVaultDB');

    // ---- v1: plaintext metadata, indexed. Kept so existing databases upgrade.
    this.version(1).stores({
      vaultMeta: 'id',
      memories: 'id, date, updatedAt, deleted',
      milestones: 'id, date, updatedAt, deleted',
      dateIdeas: 'id, category, isScratched, updatedAt, deleted',
      letters: 'id, unlockDate, isOpened, updatedAt, deleted',
      bucketList: 'id, completed, updatedAt, deleted',
    });

    // ---- v2: metadata moves inside the encrypted envelope.
    // Indexes shrink to the primary key plus the two things sync compares
    // without a key. Dexie drops the removed indexes; the rows themselves are
    // preserved and reshaped by the upgrade callback below.
    this.version(2)
      .stores({
        vaultMeta: 'id',
        memories: 'id, updatedAt, _del',
        milestones: 'id, updatedAt, _del',
        dateIdeas: 'id, updatedAt, _del',
        letters: 'id, updatedAt, _del',
        bucketList: 'id, updatedAt, _del',
      })
      .upgrade(async (tx) => {
        /**
         * THE MIGRATION CANNOT DECRYPT.
         *
         * Dexie runs upgrades when the database opens, which is before the user
         * has typed a passphrase, so there is no CryptoKey here. Re-encrypting
         * metadata into an envelope is therefore impossible at this point, and
         * throwing away the plaintext fields would be destroying data we cannot
         * re-create.
         *
         * So this pass is deliberately non-destructive and key-free:
         *   - it normalises `updatedAt` and `deleted` so the new indexes are sane,
         *   - it backfills `_del`,
         *   - it stamps `v: 1` and `needsReencrypt: 1` on every untouched row,
         *   - it records that pre-existing vaults derive at 250,000 PBKDF2
         *     iterations, so raising the constant cannot lock anyone out.
         *
         * The actual re-shaping happens later, with a key, in
         * db.migrateLegacyRecords(cryptoKey) - call it once after unlock. Until
         * that runs (or if it fails), decryptRecord() reads v1 rows natively, so
         * the app keeps working and nothing is lost. Rows are only rewritten
         * once their contents have been successfully decrypted and re-sealed.
         */
        for (const tableName of SYNCED_TABLES) {
          await tx
            .table(tableName)
            .toCollection()
            .modify((record) => {
              if (!record || typeof record !== 'object') return;

              if (!Number.isFinite(record.updatedAt)) record.updatedAt = 0;
              record.deleted = record.deleted === true;
              record._del = record.deleted ? 1 : 0;

              if (record.v !== RECORD_SCHEMA_VERSION) {
                record.v = 1;
                record.needsReencrypt = 1;
              }
            });
        }

        await tx
          .table('vaultMeta')
          .toCollection()
          .modify((meta) => {
            if (!meta || typeof meta !== 'object') return;
            if (!Number.isFinite(meta.kdfIterations)) {
              meta.kdfIterations = PBKDF2_ITERATIONS_LEGACY;
            }
          });
      });

    this._installTombstoneHooks();
  }

  /**
   * Keeps `_del` in lockstep with `deleted` on every write, so callers can go on
   * setting a plain boolean and never think about the index mirror.
   * @private
   */
  _installTombstoneHooks() {
    for (const tableName of SYNCED_TABLES) {
      const table = this.table(tableName);

      table.hook('creating', (primKey, obj) => {
        if (obj && typeof obj === 'object') {
          obj._del = obj.deleted === true ? 1 : 0;
        }
      });

      table.hook('updating', (mods, primKey, obj) => {
        const next = { ...obj, ...mods };
        const wanted = next.deleted === true ? 1 : 0;
        return next._del === wanted ? undefined : { _del: wanted };
      });
    }
  }

  /* --------------------------------------------------------------------- *
   * Sync support
   * --------------------------------------------------------------------- */

  /**
   * Generates a manifest of all local record IDs and their last update timestamps.
   * Used by the WebRTC sync engine to detect differences.
   *
   * Built entirely from key cursors: no record is materialised, so a vault with
   * hundreds of encrypted photos no longer spikes hundreds of megabytes on every
   * sync round.
   *
   * @returns {Promise<Record<string, Array<{ id: string, updatedAt: number, deleted: boolean }>>>}
   */
  async getManifest() {
    const manifest = {};

    for (const tableName of SYNCED_TABLES) {
      const table = this.table(tableName);

      // Pass 1: every primary key, including rows with a missing updatedAt.
      const ids = await table.toCollection().primaryKeys();
      const entries = new Map();
      for (const id of ids) {
        entries.set(id, { id, updatedAt: 0, deleted: false });
      }

      // Pass 2: timestamps, straight off the updatedAt index.
      await table.orderBy('updatedAt').eachKey((updatedAt, cursor) => {
        const entry = entries.get(cursor.primaryKey);
        if (entry && Number.isFinite(updatedAt)) entry.updatedAt = updatedAt;
      });

      // Pass 3: tombstones, straight off the _del index.
      const tombstoned = await table.where('_del').equals(1).primaryKeys();
      for (const id of tombstoned) {
        const entry = entries.get(id);
        if (entry) entry.deleted = true;
      }

      manifest[tableName] = Array.from(entries.values());
    }

    return manifest;
  }

  /* --------------------------------------------------------------------- *
   * Encrypted record helpers
   * --------------------------------------------------------------------- */

  /**
   * Encrypts a full logical record and writes it as a v2 envelope.
   * @param {string} tableName
   * @param {Object} plainFields - Everything, including `id`. `updatedAt` defaults to now.
   * @param {CryptoKey} key
   * @returns {Promise<Object>} The stored row, ready to hand to peerSync.broadcastLiveRecord.
   */
  async putEncrypted(tableName, plainFields, key) {
    if (!SYNCED_TABLES.includes(tableName)) {
      throw new Error(`putEncrypted: unknown table "${tableName}"`);
    }
    if (!key) throw new Error('putEncrypted: vault is locked');

    const row = await encryptRecord(plainFields, key);
    await this.table(tableName).put(row);
    return row;
  }

  /**
   * Reads one row and decrypts it, whichever schema version it uses.
   * @returns {Promise<Object|null>}
   */
  async getDecrypted(tableName, id, key) {
    if (!key) throw new Error('getDecrypted: vault is locked');
    const row = await this.table(tableName).get(id);
    if (!row) return null;
    return await decryptRecord(row, key);
  }

  /**
   * Reads and decrypts a whole table.
   *
   * Metadata is no longer indexed, so callers filter and sort the returned
   * array in memory. Rows that fail to decrypt are skipped rather than throwing,
   * so one corrupt record cannot blank an entire screen.
   *
   * @param {string} tableName
   * @param {CryptoKey} key
   * @param {{ includeDeleted?: boolean }} [options]
   * @returns {Promise<Object[]>}
   */
  async listDecrypted(tableName, key, options = {}) {
    if (!key) throw new Error('listDecrypted: vault is locked');
    const rows = await this.table(tableName).toArray();
    const out = [];
    for (const row of rows) {
      if (!options.includeDeleted && row.deleted === true) continue;
      try {
        out.push(await decryptRecord(row, key));
      } catch {
        // Undecryptable row (wrong key, corruption, hostile peer). Skip it.
      }
    }
    return out;
  }

  /**
   * Tombstones a record: keeps the id and bumps updatedAt so the deletion
   * replicates, and drops the encrypted payload so the content is really gone.
   * @returns {Promise<Object|null>} The stored tombstone, or null when absent.
   */
  async softDelete(tableName, id, key) {
    const existing = await this.table(tableName).get(id);
    if (!existing) return null;
    // A keyless tombstone carries no ciphertext, so the integrity gates on the
    // import and wire paths would (correctly) refuse it as unauthenticated and
    // the deletion would never replicate. Refuse to mint one rather than write a
    // tombstone that silently cannot travel.
    if (!key) {
      throw new Error('softDelete requires the vault key to write a replicable tombstone.');
    }

    // Not Date.now(): a device with a slow clock would stamp a tombstone the
    // partner's copy already beats, so the delete would be silently undone on
    // the next merge. syncSafeNow() is ahead of anything the partner has issued;
    // the +1 guarantees the tombstone also beats the row it is replacing.
    const updatedAt = Math.max(await syncSafeNow(), (existing.updatedAt || 0) + 1);
    const row = await encryptRecord({ id, updatedAt, deleted: true }, key);
    await this.table(tableName).put(row);
    return row;
  }

  /**
   * One-shot sweep that finishes the v1 -> v2 migration now that a key exists.
   *
   * Call once after the vault unlocks. Each legacy row is decrypted, re-sealed
   * with encryptRecord() and written back under the SAME id and updatedAt, so
   * the sync manifest is unchanged and no peer sees a spurious update. A row is
   * only replaced after its replacement has been built successfully; anything
   * that fails to decrypt is left exactly as it was.
   *
   * @param {CryptoKey} key
   * @param {{ chunkSize?: number }} [options]
   * @returns {Promise<{ scanned: number, migrated: number, failed: number }>}
   */
  async migrateLegacyRecords(key, options = {}) {
    if (!key) throw new Error('migrateLegacyRecords: vault is locked');
    const chunkSize = Number.isFinite(options.chunkSize) ? options.chunkSize : 25;

    const stats = { scanned: 0, migrated: 0, failed: 0 };

    for (const tableName of SYNCED_TABLES) {
      const table = this.table(tableName);
      const ids = await table.toCollection().primaryKeys();

      for (let offset = 0; offset < ids.length; offset += chunkSize) {
        const batch = ids.slice(offset, offset + chunkSize);
        const rewritten = [];

        for (const id of batch) {
          const row = await table.get(id);
          if (!row) continue;
          stats.scanned++;
          if (!isLegacyRecord(row)) continue;

          try {
            const plain = await decryptRecord(row, key);
            delete plain._schemaVersion;
            delete plain._needsReencrypt;
            delete plain._headerTampered;
            delete plain._binaryTampered;
            delete plain._binaryUnverified;
            // Preserve identity and ordering exactly: a migration is not an edit.
            plain.id = row.id;
            plain.updatedAt = Number.isFinite(row.updatedAt) ? row.updatedAt : 0;
            plain.deleted = row.deleted === true;
            rewritten.push(await encryptRecord(plain, key));
          } catch {
            stats.failed++;
          }
        }

        if (rewritten.length > 0) {
          await table.bulkPut(rewritten);
          stats.migrated += rewritten.length;
        }
      }
    }

    return stats;
  }

  /**
   * @returns {Promise<number>} How many rows still use the v1 shape.
   */
  async countLegacyRecords() {
    let total = 0;
    for (const tableName of SYNCED_TABLES) {
      const rows = await this.table(tableName).toArray();
      for (const row of rows) {
        if (isLegacyRecord(row)) total++;
      }
    }
    return total;
  }

  /* --------------------------------------------------------------------- *
   * Backup
   * --------------------------------------------------------------------- */

  /**
   * Serializes all encrypted records for single-container backup packaging.
   * `vaultMeta` is included so the file is self-describing, but restore never
   * writes it back - see IMPORTABLE_TABLES.
   */
  async exportRawDataForBackup() {
    const data = {
      version: 2,
      exportedAt: new Date().toISOString(),
      tables: {},
    };

    for (const tableName of EXPORTED_TABLES) {
      const records = await this.table(tableName).toArray();
      if (tableName === 'memories') {
        data.tables[tableName] = records.map((record) => {
          const clone = { ...record };
          if (clone.imageBlob) {
            // Chunked base64: the old per-byte string build froze the UI for
            // seconds on a multi-megabyte photo set.
            clone.imageBlobBase64 = bufferToBase64(clone.imageBlob);
            delete clone.imageBlob;
          }
          return clone;
        });
      } else {
        data.tables[tableName] = records;
      }
    }

    return data;
  }

  /**
   * Reads the live vault identity WITHOUT swallowing the failure.
   *
   * Every gate that protects irreversible data destruction depends on knowing
   * whether a vault is present. A `catch { return null }` there is
   * indistinguishable from "there is definitely no vault", which is how a
   * transient IndexedDB error (a blocked version upgrade, a full disk, a private
   * window) used to be promoted into permission to overwrite a live salt. So
   * this reports THREE outcomes and lets the caller fail closed on the third.
   *
   * @returns {Promise<{ ok: boolean, meta: Object|null, error?: Error }>}
   */
  async readVaultIdentity() {
    try {
      const meta = await this.vaultMeta.get('config');
      return { ok: true, meta: meta && meta.salt ? meta : null };
    } catch (err) {
      return { ok: false, meta: null, error: err };
    }
  }

  /**
   * Plans a MERGE of a decrypted backup into the live tables. Writes nothing.
   *
   * This exists because the old importRawDataFromBackup() was a blind bulkPut:
   * no timestamp comparison, no proof the file came from this vault, no preview.
   * With the stable deterministic seed ids this build introduced
   * (bkt-default-1..6, roulette-current), ANY two vaults collide on primary key,
   * so that bulkPut would replace live rows with rows encrypted under a foreign
   * key - rows every read path then silently skips, making the items simply
   * vanish. Three defences, in order:
   *
   *   1. STRUCTURE   sanitizeImportedRecord() drops unknown fields and rejects a
   *                  malformed header, mirroring peerSync._validateWireRecord.
   *   2. INTEGRITY   every row must decrypt under THIS vault's key and must not
   *                  report `_headerTampered` / `_binaryTampered`, mirroring
   *                  peerSync._verifyRecordIntegrity. A backup from a different
   *                  vault fails here, record by record, and writes nothing.
   *                  On a v1 row this proves only that the key opened a cipher
   *                  field - see verifyRowIntegrity for why that is weaker than
   *                  it looks, and step 2b below for what covers the gap.
   *  2b. AUTHORITY   overwriting or tombstoning a row that ALREADY EXISTS
   *                  additionally requires recordHasAuthenticatedHeader(), i.e.
   *                  a v2 envelope. A v1 row may create and nothing else.
   *   3. PRECEDENCE  the winner is chosen by peerSync's OWN _incomingWins rule
   *                  (loaded below, deliberately not reimplemented), so a merge
   *                  and a sync can never disagree about which copy is newer.
   *                  Restoring an older backup of the same vault therefore adds
   *                  what is missing and leaves newer local edits alone.
   *
   * @param {Record<string, Object[]>} tables - `tables` from a decrypted container.
   * @param {CryptoKey} key - The key the RESULTING vault will be read with.
   * @returns {Promise<Object>} A plan; hand it to applyBackupMerge() to write.
   */
  async planBackupMerge(tables, key) {
    if (!tables || typeof tables !== 'object' || Array.isArray(tables)) {
      throw new Error('Invalid backup table payload');
    }
    if (!key) {
      // Fail closed: without a key nothing can be integrity-checked, and an
      // unchecked write is exactly the hole this function exists to close.
      throw new Error('Cannot verify a backup while the vault is locked.');
    }

    const incomingWins = await loadPrecedenceRule();

    const perTable = {};
    const skippedTables = [];
    const writes = [];
    const totals = {
      added: 0,
      updated: 0,
      deleted: 0,
      stale: 0,
      invalid: 0,
      undecryptable: 0,
      unauthenticated: 0,
    };

    for (const [tableName, records] of Object.entries(tables)) {
      if (!IMPORTABLE_TABLES.has(tableName) || !Array.isArray(records)) {
        skippedTables.push(tableName);
        continue;
      }
      if (records.length > MAX_RECORDS_PER_TABLE) {
        throw new Error(
          `Backup rejected: "${tableName}" contains ${records.length} records (limit ${MAX_RECORDS_PER_TABLE}).`
        );
      }

      const stats = {
        total: records.length,
        added: 0,
        updated: 0,
        deleted: 0,
        stale: 0,
        invalid: 0,
        undecryptable: 0,
        unauthenticated: 0,
      };
      const table = this.table(tableName);

      // Sanitize + integrity-check first, OUTSIDE any transaction: awaiting Web
      // Crypto inside a Dexie transaction lets it commit out from under us.
      const candidates = [];
      for (const record of records) {
        const row = sanitizeImportedRecord(tableName, record);
        if (!row) {
          stats.invalid++;
          continue;
        }
        if (!(await verifyRowIntegrity(row, key))) {
          stats.undecryptable++;
          continue;
        }
        candidates.push(row);
      }

      // Compare against what is already here, in chunks so a photo table does
      // not have to be resident all at once.
      for (let offset = 0; offset < candidates.length; offset += BULK_WRITE_CHUNK) {
        const chunk = candidates.slice(offset, offset + BULK_WRITE_CHUNK);
        const existingRows = await table.bulkGet(chunk.map((row) => row.id));
        for (let i = 0; i < chunk.length; i++) {
          const existing = existingRows[i];
          const row = chunk[i];
          if (!existing) {
            // Nothing here to destroy. A v1 row is allowed to CREATE, because the
            // worst case is a junk row the user can delete, not a lost photo.
            stats.added++;
            writes.push({ table: tableName, row });
            continue;
          }

          // Something already exists at this id, so this write can destroy data.
          // Only a v2 envelope may do that: see recordHasAuthenticatedHeader.
          // A v1 row's id / updatedAt / deleted header is not bound to any
          // ciphertext, so a forger holding one blob encrypted under the vault
          // key can aim a tombstone at any id they can guess - and the seeded
          // ids are identical across every vault by construction.
          if (!recordHasAuthenticatedHeader(row)) {
            stats.unauthenticated++;
            continue;
          }

          if (!incomingWins(existing, row)) {
            stats.stale++;
            continue;
          }

          // Count destructive writes separately. Folding these into "updated"
          // let the preview describe losing a photo as an update.
          if (row.deleted === true && existing.deleted !== true) {
            stats.deleted++;
          } else {
            stats.updated++;
          }
          writes.push({ table: tableName, row });
        }
      }

      perTable[tableName] = stats;
      for (const field of Object.keys(totals)) totals[field] += stats[field];
    }

    return { writes, perTable, totals, skippedTables, incomingWins };
  }

  /**
   * Writes a plan produced by planBackupMerge(), after the user confirmed it.
   *
   * The precedence rule is re-applied INSIDE the transaction. A live sync can
   * land a newer copy in the seconds between the preview and the confirmation,
   * and a plan that was accurate when it was built must not be allowed to
   * regress that. Comparison is pure, so it is safe inside the transaction;
   * decryption already happened during planning.
   *
   * @param {Object} plan
   * @returns {Promise<{ written: Record<string, number>, supersededSincePreview: number }>}
   */
  async applyBackupMerge(plan) {
    if (!plan || !Array.isArray(plan.writes) || typeof plan.incomingWins !== 'function') {
      throw new Error('applyBackupMerge: not a plan produced by planBackupMerge()');
    }
    const written = {};
    let supersededSincePreview = 0;
    if (plan.writes.length === 0) return { written, supersededSincePreview };

    const tableNames = [...new Set(plan.writes.map((entry) => entry.table))];
    const tables = tableNames.map((name) => this.table(name));

    await this.transaction('rw', tables, async () => {
      for (const name of tableNames) {
        const table = this.table(name);
        const rows = plan.writes.filter((entry) => entry.table === name).map((entry) => entry.row);

        for (let offset = 0; offset < rows.length; offset += BULK_WRITE_CHUNK) {
          const chunk = rows.slice(offset, offset + BULK_WRITE_CHUNK);
          const existingRows = await table.bulkGet(chunk.map((row) => row.id));
          const stillWins = chunk.filter((row, i) => {
            const existing = existingRows[i];
            if (!existing) return true;
            // Re-assert the plan-time invariant here too. A row that would
            // overwrite or delete an existing one must carry a bound header, and
            // a sync landing between preview and confirm can turn an "added"
            // into an overwrite. Belt and braces: a plan is a caller-supplied
            // object, so this must not rely on planBackupMerge having filtered.
            if (!recordHasAuthenticatedHeader(row)) {
              supersededSincePreview++;
              return false;
            }
            if (plan.incomingWins(existing, row)) return true;
            supersededSincePreview++;
            return false;
          });
          if (stillWins.length > 0) await table.bulkPut(stillWins);
          written[name] = (written[name] || 0) + stillWins.length;
        }
      }
    });

    return { written, supersededSincePreview };
  }

  /**
   * Adopts a vault identity (salt + canary + KDF count) out of a backup.
   *
   * THIS IS THE ONLY PLACE IN THE APP THAT WRITES vaultMeta FROM A FILE, and it
   * is what makes the rescue backup an actual way back rather than a promise the
   * code could not keep. Callers must already have:
   *   - derived a key from `metaRow.salt` and PROVED it against `metaRow.canary`
   *     (an unverifiable identity is refused upstream - writing a salt nobody
   *     can be shown to hold the key for is the trap this replaces), and
   *   - obtained the destroy confirmation when a different live vault exists.
   *
   * @param {{ salt: string, canary: string, canaryIv: string, kdfIterations?: number,
   *           updatedAt?: number }} metaRow
   * @returns {Promise<void>}
   */
  async restoreVaultIdentity(metaRow) {
    await this.vaultMeta.put({
      id: 'config',
      salt: metaRow.salt,
      canary: metaRow.canary,
      canaryIv: metaRow.canaryIv,
      kdfIterations: Number.isFinite(metaRow.kdfIterations)
        ? metaRow.kdfIterations
        : PBKDF2_ITERATIONS_LEGACY,
      updatedAt: Number.isFinite(metaRow.updatedAt) ? metaRow.updatedAt : 0,
    });
  }
}

/**
 * The vault identity a backup container carries, or null when it carries none.
 *
 * Exported containers include `vaultMeta` (see EXPORTED_TABLES) precisely so a
 * restore can read it deliberately. A container missing it - or missing its
 * canary - cannot be used to restore identity, because there would be no way to
 * prove the passphrase before committing a salt.
 *
 * @param {Record<string, Object[]>} tables
 * @returns {{ salt: string, canary: string, canaryIv: string, kdfIterations: number,
 *            updatedAt: number }|null}
 */
export function readBackupVaultIdentity(tables) {
  const rows = tables && tables.vaultMeta;
  if (!Array.isArray(rows)) return null;
  const row = rows.find((entry) => entry && entry.id === 'config' && typeof entry.salt === 'string');
  if (!row) return null;
  if (typeof row.canary !== 'string' || typeof row.canaryIv !== 'string') return null;
  return {
    salt: row.salt,
    canary: row.canary,
    canaryIv: row.canaryIv,
    kdfIterations: Number.isFinite(row.kdfIterations)
      ? row.kdfIterations
      : PBKDF2_ITERATIONS_LEGACY,
    updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0,
  };
}

/**
 * Says whether a backup belongs to the vault currently on this device.
 *
 * 'unknown' is NOT 'foreign' and NOT 'same' - it means the question could not be
 * answered, and every caller must treat it as a reason to stop rather than a
 * reason to proceed.
 *
 * @param {ReturnType<typeof readBackupVaultIdentity>} backupIdentity
 * @param {{ ok: boolean, meta: Object|null }} localRead - from db.readVaultIdentity()
 * @returns {'same'|'foreign'|'no-local-vault'|'unknown'}
 */
export function compareVaultIdentity(backupIdentity, localRead) {
  if (!localRead || localRead.ok !== true) return 'unknown';
  if (!localRead.meta) return 'no-local-vault';
  if (!backupIdentity || typeof backupIdentity.salt !== 'string') return 'unknown';
  return backupIdentity.salt === localRead.meta.salt ? 'same' : 'foreign';
}

/**
 * Proves a row from a backup is genuinely readable by THIS vault before it is
 * ever written.
 *
 * Mirrors peerSync._verifyRecordIntegrity deliberately: same checks, same
 * rejections. It is duplicated rather than imported because that method reads
 * peerSync's own key, which is null when no partner is connected - and a backup
 * restore must work offline.
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT - the rule is two-tier, and the tiers
 * are NOT interchangeable:
 *
 *  - For a v2 row it proves the key opened an envelope AND that the envelope
 *    agrees with the unauthenticated parts of the row: the plaintext
 *    id/updatedAt/deleted header, and the SHA-256 of every attached binary
 *    field. A rewritten header or a swapped photo fails here.
 *  - For a v1 row it proves ONLY that some `<base>Cipher` field opened under
 *    this key. decryptLegacyRecord() stamps `_headerTampered: false` and
 *    `_binaryTampered: false` unconditionally, because v1 has no authenticated
 *    header and no digest to compare against. A clean verdict on a v1 row
 *    therefore means "unknowable", not "clean", which is exactly why one lifted
 *    ciphertext used as a decoy pair passed this check (test 11bis) and why
 *    planBackupMerge separately demands recordHasAuthenticatedHeader() before
 *    letting anything overwrite or tombstone an existing row.
 *
 * The residual gap, stated rather than papered over: a v2 envelope sealed
 * before digest binding existed carries no digest map, so its photo bytes are
 * accepted unverified. That is the deliberate backward-compatibility choice
 * (see BINARY_DIGEST_FIELD in crypto.js) - refusing them would make old photos
 * unrestorable.
 *
 * @returns {Promise<boolean>}
 */
async function verifyRowIntegrity(row, key) {
  // A successful decrypt is not on its own proof the key was used: a row with no
  // ciphertext at all resolves through the legacy path without touching the key.
  // Require an authenticated payload FIRST, or a foreign row on a colliding
  // stable id (bkt-default-1, roulette-current) would overwrite a live one.
  if (!recordCarriesAuthenticatedPayload(row)) return false;
  try {
    const plain = await decryptRecord(row, key);
    if (!plain) return false;
    // `_headerTampered` already covers `_binaryTampered`; both are named here so
    // that decoupling them later cannot silently reopen the photo-swap hole.
    if (plain._headerTampered === true || plain._binaryTampered === true) return false;
    return true;
  } catch {
    return false;
  }
}

/**
 * Borrows the LIVE last-write-wins rule from the sync engine.
 *
 * Deliberately not reimplemented here. A second copy of "which version is newer"
 * would drift from peerSync's, and the two paths write the same rows - a merge
 * that disagreed with a sync would ping-pong records forever. Imported lazily
 * because peerSync imports this module; the cycle only resolves at call time,
 * long after both modules have finished evaluating.
 *
 * Fails closed: if the rule cannot be loaded, the merge is refused rather than
 * falling back to a home-grown comparison.
 *
 * Rollup warns that peerSync is both dynamically and statically imported and so
 * will not be split into its own chunk. That is the desired outcome, not a
 * problem: the module is already in the main bundle, so this resolves instantly
 * and offline. Do NOT "fix" the warning by making this a static import - that
 * reintroduces the evaluation cycle this defers around.
 *
 * @returns {Promise<(existing: Object, incoming: Object) => boolean>}
 */
/**
 * Lazily borrows peerSync's monotonic clock.
 *
 * Same lazy-import reason as loadPrecedenceRule: peerSync imports this module,
 * so a static import here would be circular. Unlike the precedence rule, a
 * missing clock is NOT fatal - a tombstone that stamps a plain wall-clock time
 * is still a valid tombstone, it just loses the remote high-water guarantee. So
 * this degrades to Date.now() instead of refusing the delete.
 *
 * @returns {Promise<number>}
 */
async function syncSafeNow() {
  try {
    const mod = await import('../services/peerSync.js');
    const engine = mod && mod.default;
    if (engine && typeof engine.getSyncSafeTimestamp === 'function') {
      return engine.getSyncSafeTimestamp();
    }
  } catch {
    // peerSync unavailable (not yet loaded, or storage blocked). Fall through.
  }
  return Date.now();
}

async function loadPrecedenceRule() {
  const mod = await import('../services/peerSync.js');
  const engine = mod && mod.default;
  if (!engine || typeof engine._incomingWins !== 'function') {
    throw new Error(
      'Cannot verify which copy of a record is newer, so nothing was written. Reload and try again.'
    );
  }
  return engine._incomingWins.bind(engine);
}

/**
 * Field allowlist per table. Anything not listed is dropped on import.
 * Legacy (v1) field names are included so an old backup still restores.
 */
const COMMON_FIELDS = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', '_del'];
const LEGACY_FIELDS_BY_TABLE = {
  memories: ['date', 'captionCipher', 'captionIv', 'imageBlob', 'mimeType', 'needsReencrypt'],
  milestones: ['date', 'titleCipher', 'titleIv', 'needsReencrypt'],
  dateIdeas: ['category', 'isScratched', 'textCipher', 'textIv', 'needsReencrypt'],
  letters: [
    'unlockDate',
    'isOpened',
    'titleCipher',
    'titleIv',
    'contentCipher',
    'contentIv',
    'needsReencrypt',
  ],
  bucketList: ['category', 'completed', 'completedAt', 'textCipher', 'textIv', 'needsReencrypt'],
};

/**
 * Validates and copies one record from a backup. Returns null to reject it.
 * Never mutates the input.
 */
function sanitizeImportedRecord(tableName, record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return null;
  if (typeof record.id !== 'string' || record.id.length === 0 || record.id.length > 128) return null;
  if (record.updatedAt !== undefined && !Number.isFinite(record.updatedAt)) return null;
  // Same header rules the sync path enforces (peerSync._validateWireRecord).
  // A negative or far-future stamp is not just odd data: restored, it would win
  // every last-write-wins comparison against real edits, forever.
  if (Number.isFinite(record.updatedAt)) {
    if (record.updatedAt < 0) return null;
    if (record.updatedAt > Date.now() + MAX_BACKUP_CLOCK_SKEW_MS) return null;
  }
  if (record.v !== undefined && record.v !== 1 && record.v !== 2) return null;

  const allowed = new Set([...COMMON_FIELDS, ...(LEGACY_FIELDS_BY_TABLE[tableName] || [])]);
  const out = {};

  for (const [field, value] of Object.entries(record)) {
    if (!allowed.has(field)) continue;
    if (value === undefined) continue;
    out[field] = value;
  }

  out.updatedAt = Number.isFinite(record.updatedAt) ? record.updatedAt : 0;
  out.deleted = record.deleted === true;
  out._del = out.deleted ? 1 : 0;

  if (tableName === 'memories' && typeof record.imageBlobBase64 === 'string') {
    try {
      const bytes = base64ToBuffer(record.imageBlobBase64);
      if (bytes.byteLength > MAX_IMAGE_BLOB_BYTES) return null;
      out.imageBlob = bytes;
    } catch {
      return null;
    }
  } else if (out.imageBlob !== undefined) {
    const bytes =
      out.imageBlob instanceof Uint8Array ? out.imageBlob : new Uint8Array(out.imageBlob || []);
    if (bytes.byteLength > MAX_IMAGE_BLOB_BYTES) return null;
    out.imageBlob = bytes;
  }

  return out;
}

export const db = new SweetheartDatabase();

/* ------------------------------------------------------------------------- *
 * Blocked-upgrade detection
 *
 * IndexedDB will not run the v1 -> v2 upgrade while another tab still holds the
 * database open at v1, so db.open() hangs and every read rejects. That read
 * failure used to be indistinguishable from "this device has no vault", which
 * routed a returning user to the CREATE VAULT form - one confirmation away from
 * writing a fresh salt over a fully populated live vault. Dexie tells us exactly
 * why, so the UI can say "close the other tabs" instead of offering to erase
 * everything.
 * ------------------------------------------------------------------------- */

let upgradeBlocked = false;
const upgradeBlockedListeners = new Set();

db.on('blocked', () => {
  upgradeBlocked = true;
  for (const listener of upgradeBlockedListeners) {
    try {
      listener(true);
    } catch {
      // A listener throwing must not stop the others being told.
    }
  }
});

/** @returns {boolean} True when another tab is holding the old schema open. */
export function isUpgradeBlocked() {
  return upgradeBlocked;
}

/**
 * @param {(blocked: boolean) => void} listener
 * @returns {() => void} Unsubscribe.
 */
export function subscribeUpgradeBlocked(listener) {
  upgradeBlockedListeners.add(listener);
  if (upgradeBlocked) listener(true);
  return () => upgradeBlockedListeners.delete(listener);
}

export default db;
