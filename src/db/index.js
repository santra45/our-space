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
import { MAX_IMAGE_BLOB_BYTES } from '../services/limits.js';
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
  PROVENANCE_LEGACY,
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

/**
 * Re-exported so existing importers keep working. Defined in services/limits.js
 * and DERIVED from the wire ceiling - see that file for why it is not a number
 * written down here.
 */
export { MAX_IMAGE_BLOB_BYTES };

const BULK_WRITE_CHUNK = 100;

/**
 * A record stamped further ahead than this is a clock artefact, not history.
 *
 * This MUST stay equal to peerSync's MAX_CLOCK_SKEW_MS (peerSync.js), and it was
 * not: this was 48h while the wire gate was 24h, and the comment claimed they
 * matched. The gap was a real trap rather than a cosmetic one - a row stamped
 * +30h was accepted by planBackupMerge and then refused by _validateWireRecord
 * as `future_timestamp`, so a row a user had just restored from their own rescue
 * backup could not reach their partner until the clock caught up, with nothing
 * anywhere saying why. The two numbers are duplicated rather than imported
 * because peerSync.js already imports this module at the top level
 * (`import db from '../db/index.js'`), which is why this module reaches
 * peerSync only through a deferred dynamic import (loadPrecedenceRule, below).
 * A top-level import back the other way would make that cycle eager. So: if you
 * change one of these two constants, change the other.
 */
const MAX_BACKUP_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

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
  /**
   * Stamps the `_del` index mirror onto a row about to be written.
   *
   * The Dexie hooks below keep `_del` in step for ordinary single-row writes,
   * but they DO NOT FIRE for bulkPut / bulkAdd - and encryptRecord deliberately
   * strips `_del`, because it is local bookkeeping that must never be sealed
   * into an envelope or put on the wire. Both facts together mean every row
   * written in bulk arrived with `_del` undefined.
   *
   * That silently broke deletion sync. getManifest() reads tombstones off
   * `where('_del').equals(1)`, so a re-sealed or restored tombstone was
   * advertised to the partner as `deleted: false` - and a deleted memory came
   * back from the dead on the next sync.
   *
   * Applied explicitly at every write site rather than trusted to the hooks, so
   * a future bulk path cannot reintroduce it.
   *
   * @param {Object} row
   * @returns {Object} the same row, with `_del` in step with `deleted`
   */
  _withDelIndex(row) {
    if (row && typeof row === 'object') {
      row._del = row.deleted === true ? 1 : 0;
    }
    return row;
  }

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
  /**
   * Decides whether a write at `id` must inherit PROVENANCE_LEGACY.
   *
   * Provenance is STICKY PER ID, and it has to be, because a device cannot tell
   * its own record from one an attacker got created at that id. d9239ab marked
   * the re-seal sweep, but every other re-encrypt path re-authored freely - and
   * an adversarial reviewer executed four chains through them, one needing no
   * user gesture at all (SecretCapsule's automatic time-lock seal pass), one
   * needing a single tap on an unread letter, and one turning the user's own
   * "Delete this precious memory?" confirmation into an authenticated tombstone
   * that erased the partner's copy.
   *
   * The rule: a brand-new id gets full standing. An id that already holds a row
   * this vault cannot authenticate keeps that row's reduced standing, whoever
   * writes over it and for whatever reason. Editing content you were shown does
   * not vouch for where it came from.
   *
   * @returns {Promise<Object>} Options to spread into encryptRecord().
   */
  async _inheritedProvenance(tableName, id, key) {
    try {
      const existing = await this.table(tableName).get(id);
      if (!existing) return {};
      if (isLegacyRecord(existing)) return { provenance: PROVENANCE_LEGACY };
      const verdict = await verifyRowIntegrity(existing, key, tableName);
      return verdict === 'ok' ? {} : { provenance: PROVENANCE_LEGACY };
    } catch {
      // Cannot establish standing, so do not grant any. Fail closed.
      return { provenance: PROVENANCE_LEGACY };
    }
  }

  async putEncrypted(tableName, plainFields, key) {
    if (!SYNCED_TABLES.includes(tableName)) {
      throw new Error(`putEncrypted: unknown table "${tableName}"`);
    }
    if (!key) throw new Error('putEncrypted: vault is locked');

    // The table is sealed INTO the envelope, so this row cannot later be
    // replayed into a different table under its own valid ciphertext (see
    // TABLE_BINDING_FIELD in crypto.js).
    const row = await encryptRecord(plainFields, key, {
      table: tableName,
      ...(await this._inheritedProvenance(tableName, plainFields.id, key)),
    });
    await this.table(tableName).put(this._withDelIndex(row));
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
    // Bound to this table, like every other write. A tombstone is the row an
    // attacker most wants to move between tables - it needs no plausible
    // payload, only an id - so it is the one that must carry the binding.
    // Provenance is inherited here too, and this is the case that mattered most:
    // a hostile peer creates a junk row, the user sees an unrecognisable card,
    // taps Delete and confirms - and without this the app would mint a fully
    // authenticated tombstone at that id and replicate it, erasing the partner's
    // real photo. Deleting something you did not recognise is not an assertion
    // that you authored it.
    const row = await encryptRecord({ id, updatedAt, deleted: true }, key, {
      table: tableName,
      ...(await this._inheritedProvenance(tableName, id, key)),
    });
    await this.table(tableName).put(this._withDelIndex(row));
    return row;
  }

  /**
   * One-shot sweep that finishes the v1 -> v2 migration now that a key exists,
   * and re-seals v2 rows whose envelopes predate a binding this build enforces.
   *
   * Call once after the vault unlocks. Each row that needs it is decrypted,
   * re-sealed with encryptRecord() and written back under the SAME id and
   * updatedAt, so the sync manifest is unchanged and no peer sees a spurious
   * update. A row is only replaced after its replacement has been built
   * successfully; anything that fails to decrypt is left exactly as it was, and
   * anything that reports tampering is left alone deliberately (see below).
   *
   * This is what drains the two compatibility carve-outs - a v2 row with no
   * binary digest map, and a v2 row with no table binding - so neither is
   * permanent. It drains PER DEVICE and only for rows this device holds: until
   * a given device has completed one sweep, its own older rows still verify on
   * fewer dimensions. A partner still on a build that predates this sweep never
   * runs it at all, so it keeps sending unbound rows indefinitely, and every
   * update and delete it sends is refused (see _commitStagedRecords). That is
   * the intended trade and it is reported to the user rather than hidden - see
   * the `unverifiable` counter on the sync status.
   *
   * The v1 carve-out is NOT drained in the same sense. A v1 row is re-sealed so
   * it reads like every other v2 row, but the seal records that its content came
   * from a header this vault never authenticated (PROVENANCE_LEGACY), so it
   * keeps the same create-only standing it had as a v1 row. That is deliberate:
   * see the laundry note inside the loop.
   *
   * @param {CryptoKey} key
   * @param {{ chunkSize?: number }} [options]
   * @returns {Promise<{ scanned: number, migrated: number, failed: number,
   *                     tampered: number }>} `tampered` counts rows left
   *   untouched because some unauthenticated part of them disagrees with their
   *   envelope - including a fully-bound row whose photo bytes were swapped.
   *   `failed` counts rows that would not decrypt at all.
   */
  async migrateLegacyRecords(key, options = {}) {
    if (!key) throw new Error('migrateLegacyRecords: vault is locked');
    const chunkSize = Number.isFinite(options.chunkSize) ? options.chunkSize : 25;

    const stats = { scanned: 0, migrated: 0, failed: 0, tampered: 0 };

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

          // Three kinds of row need re-sealing.
          //
          // 1. v1 rows, which is what this sweep was originally for.
          // 2. v2 rows written BEFORE photo bytes were bound into the envelope.
          //    Those carry no digest map, so verifyBinaryDigests reports them
          //    `unverified` rather than tampered - which means the blob on a
          //    pre-digest photo can still be swapped and every gate will pass it.
          //    Skipping them here left that carve-out permanent: no other code
          //    path re-seals a v2 row, so every photo already in a live vault
          //    would have stayed swappable forever. Draining it is the whole
          //    point, so they are opened too.
          // 3. v2 rows written before the TABLE was bound into the envelope
          //    (TABLE_BINDING_FIELD). Same carve-out, same drain, and this is
          //    the one that costs: a table binding is inside the ciphertext, so
          //    unlike an attached blob its absence cannot be detected without
          //    decrypting. There is therefore no cheap pre-filter available and
          //    the sweep opens every v2 row once per unlock:
          //    one AES-GCM open of a small JSON envelope per row, on a sweep
          //    that already SHA-256s every attached photo it opens. That cost is
          //    the price of this carve-out draining at all rather than being
          //    permanent, and it is paid on a background task VaultContext fires
          //    un-awaited after unlock.
          //
          // Rows written by an OLDER build of this app are covered the same way,
          // including the six starter bucket-list items on their fixed,
          // cross-vault-colliding ids: seedDefaultItems() binds the table now,
          // but rows it wrote before that are unbound and are bound here at the
          // next unlock.
          //
          // Note what this sweep does NOT do: it re-seals rows this device
          // HOLDS, while the integrity gates decrypt the row ARRIVING. Sweeping
          // therefore does nothing about an envelope an attacker harvested
          // before binding existed. That is handled where it has to be - by
          // refusing an unverified row an overwrite in planBackupMerge and
          // _commitStagedRecords.
          //
          // WHAT THE SWEEP IS NOT, since it used to be exactly this: it is not
          // a laundry. Re-sealing takes the row's CURRENT top-level header and
          // bytes and authenticates them, so re-sealing an attacker-authored v1
          // row would have turned it into a fully-bound v2 envelope over the
          // attacker's chosen id, updatedAt and delete flag - a create-only
          // capability promoted into an overwrite-anything one. Two things stop
          // that now, and both are load-bearing: a row reporting tampering is
          // never re-sealed at all (below), and a row that arrived as v1 is
          // re-sealed carrying PROVENANCE_LEGACY, which decryptRecord surfaces
          // as `_headerUnverified` and both gates treat exactly like a missing
          // binding - may create, never overwrite or delete.
          const isLegacy = isLegacyRecord(row);

          try {
            const plain = await decryptRecord(row, key, { table: tableName });
            // NEVER re-seal a row that reports tampering - see the laundry note
            // above. Leave it exactly as it is, still refused by those gates,
            // and report it separately from `failed` (which VaultContext renders
            // as "written with a different passphrase", and this is not that).
            //
            // This check runs BEFORE the "already bound, skip" test below on
            // purpose. It used to run after, which meant a FULLY bound row whose
            // photo bytes had been swapped underneath it took the skip and was
            // never counted: stats.tampered stayed 0 for the one row shape that
            // proves someone went at the database directly.
            if (plain._headerTampered === true) {
              stats.tampered++;
              continue;
            }
            // A v2 row already bound on both dimensions is done - re-encrypting
            // it would burn CPU on every row at every unlock for nothing.
            if (!isLegacy && plain._binaryUnverified !== true && plain._tableUnverified !== true) {
              continue;
            }
            delete plain._schemaVersion;
            delete plain._needsReencrypt;
            delete plain._headerTampered;
            delete plain._binaryTampered;
            delete plain._binaryUnverified;
            delete plain._tableTampered;
            delete plain._tableUnverified;
            // Preserve identity and ordering exactly: a migration is not an edit.
            plain.id = row.id;
            plain.updatedAt = Number.isFinite(row.updatedAt) ? row.updatedAt : 0;
            plain.deleted = row.deleted === true;
            // CRITICAL: a v1 row's header was never authenticated by this
            // vault, and re-encrypting it cannot retroactively make it so.
            // Without this marker the sweep is an escalation: an attacker who
            // gets a v1 row CREATED here (the create path is deliberately
            // permissive) would have it come back out as a fully-bound v2
            // envelope over their chosen id, timestamp, delete flag and bytes,
            // and it would then be accepted as an authenticated overwrite
            // against the partner's irreplaceable data. The marker preserves the
            // weakness instead of laundering it away, and clears itself when the
            // owning device genuinely edits the record.
            //
            // `_headerUnverified` is carried forward as well as `isLegacy`. An
            // already-re-sealed legacy row takes the skip above today, so this
            // second condition is unreachable on the current build - but if a
            // future binding is added, that row starts needing a re-seal again,
            // and dropping the marker at that point would launder it after all.
            const inheritsLegacyProvenance = isLegacy || plain._headerUnverified === true;
            delete plain._headerUnverified;
            rewritten.push(
              await encryptRecord(plain, key, {
                table: tableName,
                ...(inheritsLegacyProvenance ? { provenance: PROVENANCE_LEGACY } : {}),
              })
            );
          } catch {
            stats.failed++;
          }
        }

        if (rewritten.length > 0) {
          // _del explicitly, because bulkPut does not fire the tombstone hooks
          // and encryptRecord strips the field. Without this a re-sealed
          // tombstone drops off the `_del` index and the manifest tells the
          // partner the record is alive.
          await table.bulkPut(rewritten.map((row) => this._withDelIndex(row)));
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
   *                  report `_headerTampered` / `_binaryTampered` /
   *                  `_tableTampered`, mirroring peerSync._verifyRecordIntegrity.
   *                  A backup from a different vault fails here, record by
   *                  record, and writes nothing. The two failures are counted
   *                  apart - `undecryptable` (wrong key or rotted bytes) and
   *                  `tampered` (opened under this key, then edited) - because
   *                  one of those is a filing mistake and the other is a person.
   *                  On a v1 row this proves only that the key opened a cipher
   *                  field - see verifyRowIntegrity for why that is weaker than
   *                  it looks, and step 2b below for what covers the gap.
   *  2b. AUTHORITY   overwriting or tombstoning a row that ALREADY EXISTS
   *                  additionally requires that verifyRowIntegrity() returned
   *                  'ok' rather than 'unverified', AND
   *                  recordHasAuthenticatedHeader(), i.e. a v2 envelope. A v1
   *                  row, or a v2 row whose binding is merely absent, may create
   *                  and nothing else.
   *   3. PRECEDENCE  the winner is chosen by peerSync's OWN _incomingWins rule
   *                  (loaded below, deliberately not reimplemented), so a merge
   *                  and a sync can never disagree about which copy is newer.
   *                  Restoring an older backup of the same vault therefore adds
   *                  what is missing and leaves newer local edits alone.
   *
   * WHAT THE COUNTERS MEAN, because step 2b refuses two very different files
   * with the same verdict and the preview has to be able to tell them apart:
   *
   *   `unauthenticated`  every row refused by step 2b. The umbrella total. It is
   *                      the number the preview has always shown.
   *   `unverifiable`     the SUBSET of those refused because the row's binding is
   *                      ABSENT rather than wrong - a v1 row, or an envelope
   *                      sealed before the photo digest / table binding existed,
   *                      or a v1 row the sweep re-sealed under PROVENANCE_LEGACY.
   *                      This is the ordinary, innocent case: a rescue backup
   *                      taken before the binding shipped. Such a file can still
   *                      ADD everything this device is missing; it simply cannot
   *                      repair a row the device already holds.
   *   `unverifiableNewer` the SUBSET of `unverifiable` whose file copy would
   *                      actually have WON on precedence - i.e. the user's own
   *                      backup is genuinely newer than what is on the device and
   *                      is still being refused. This is the count worth putting
   *                      in front of a user, because it is the one that means
   *                      "your restore did not do what you expected".
   *
   * `unverifiable` and `unverifiableNewer` are subsets of `unauthenticated`, not
   * additions to it; summing all three double-counts.
   *
   * @param {Record<string, Object[]>} tables - `tables` from a decrypted container.
   * @param {CryptoKey} key - The key the RESULTING vault will be read with.
   * @returns {Promise<{ writes: Array<{table: string, row: Object}>,
   *   perTable: Record<string, Object>, totals: Object, skippedTables: string[],
   *   incomingWins: Function, key: CryptoKey }>} A plan; hand it to
   *   applyBackupMerge() to write. `key` is carried so applyBackupMerge can
   *   re-run the integrity check itself instead of trusting the plan.
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
      tampered: 0,
      unauthenticated: 0,
      unverifiable: 0,
      unverifiableNewer: 0,
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
        tampered: 0,
        unauthenticated: 0,
        unverifiable: 0,
        unverifiableNewer: 0,
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
        // The table name is passed so a row sealed for a DIFFERENT table cannot
        // be replayed into this one under its own valid envelope - the key that
        // `tables` is being iterated by is exactly the claim being checked.
        const verdict = await verifyRowIntegrity(row, key, tableName);
        if (verdict !== 'ok' && verdict !== 'unverified') {
          stats[verdict]++;
          continue;
        }
        // An unverified row is kept as a CANDIDATE but remembered as such: it may
        // still create something at an id we do not have, because that destroys
        // nothing. The decision loop below is what refuses it an overwrite.
        candidates.push({ row, verified: verdict === 'ok' });
      }

      // Compare against what is already here, in chunks so a photo table does
      // not have to be resident all at once.
      for (let offset = 0; offset < candidates.length; offset += BULK_WRITE_CHUNK) {
        const chunk = candidates.slice(offset, offset + BULK_WRITE_CHUNK);
        const existingRows = await table.bulkGet(chunk.map((entry) => entry.row.id));
        for (let i = 0; i < chunk.length; i++) {
          const existing = existingRows[i];
          const { row, verified } = chunk[i];
          if (!existing) {
            // A tombstone for an id we have never seen deletes nothing, and it is
            // not harmless: it is invisible in every list (they all filter on
            // `deleted`), so the user can neither see nor remove it, and it sits
            // on a primary key that is identical in every vault by construction.
            // The seed guard is no longer the `count() > 0` this comment used to
            // describe - seedDefaultItems() now counts only LIVE rows
            // (`where('_del').equals(0)`), so one forged tombstone no longer
            // suppresses all six starter items. It still costs one: the seed
            // skips any of the six fixed ids that is already present rather than
            // overwriting it, because a local seed is not allowed to clobber a
            // row it cannot prove it authored either. sanitizeImportedRecord also
            // allows a stamp up to MAX_BACKUP_CLOCK_SKEW_MS (24h) ahead, letting
            // such a row outrank genuine later writes at that id. Nothing
            // legitimate needs to insert a delete, so refuse it.
            if (row.deleted === true) {
              stats.invalid++;
              continue;
            }
            // Otherwise there is nothing here to destroy, so a v1 row may create.
            // It could still be a junk row - but it is a VISIBLE junk row the
            // user can delete, which is the property the earlier note claimed
            // without checking the tombstone case.
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
          // Same rule for a binding that is merely ABSENT rather than wrong: an
          // envelope predating the photo digest or the table binding cannot
          // prove which bytes or which table it belongs to, so it may not
          // overwrite or delete. Otherwise a single harvested pre-binding
          // envelope erases a photo (swap the bytes, or just omit them) or
          // deletes a letter from another table, on a fully-swept device.
          //
          // Refusing is correct. Refusing INVISIBLY is not: the only counter
          // this used to land in reads "not sealed to the record it targets",
          // which tells a user restoring their own pre-binding rescue backup
          // nothing about what happened or what to do. So the innocent case is
          // counted apart - see the counter contract on this method - and the
          // sub-case that actually cost the user something (their file copy was
          // NEWER and was still refused) is counted apart again.
          if (!verified) {
            stats.unauthenticated++;
            stats.unverifiable++;
            if (incomingWins(existing, row)) stats.unverifiableNewer++;
            continue;
          }

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

    // `key` travels with the plan so applyBackupMerge can re-derive the
    // integrity verdict itself rather than trusting a caller-supplied object.
    // A CryptoKey is not extractable and never leaves this process.
    return { writes, perTable, totals, skippedTables, incomingWins, key };
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
   * THE INTEGRITY RE-CHECK IS REAL, and it used to only look real. The comment
   * here claimed "a plan is a caller-supplied object, so this must not rely on
   * planBackupMerge having filtered" while checking recordHasAuthenticatedHeader
   * and nothing else - which passes any well-formed v2 envelope, including one
   * sealed for a different table or around different photo bytes. A hand-built
   * plan could therefore write a cross-table envelope over a live letter. The
   * two missing dimensions live INSIDE the ciphertext, so proving them needs
   * Web Crypto, and awaiting Web Crypto inside a Dexie transaction lets the
   * transaction commit out from under you. So the verdicts are recomputed here,
   * BEFORE the transaction opens, using the key the plan carries; the
   * transaction body then does nothing but pure comparisons and writes.
   *
   * A plan with no `key` (only a hand-built one has none) is not trusted at all:
   * every row in it is treated as unverifiable, so it may create and may never
   * overwrite or delete. Fail closed, and the honest restore path is unaffected
   * because planBackupMerge always supplies the key.
   *
   * The cost, stated rather than hidden: this opens every ACCEPTED row a second
   * time (planning opened them once), plus one SHA-256 pass per attached photo.
   * It is paid once, on an explicit confirmation the user has just read, on a
   * path that is already about to rewrite their library.
   *
   * @param {Object} plan
   * @returns {Promise<{ written: Record<string, number>,
   *   supersededSincePreview: number, refusedSincePreview: number }>}
   *   `supersededSincePreview` is every planned write that did not happen;
   *   `refusedSincePreview` is the subset refused because the row could not be
   *   proved to belong here (a subset, not an addition).
   */
  async applyBackupMerge(plan) {
    if (!plan || !Array.isArray(plan.writes) || typeof plan.incomingWins !== 'function') {
      throw new Error('applyBackupMerge: not a plan produced by planBackupMerge()');
    }
    const written = {};
    let supersededSincePreview = 0;
    let refusedSincePreview = 0;
    if (plan.writes.length === 0) {
      return { written, supersededSincePreview, refusedSincePreview };
    }

    // Recompute the verdict per write entry, outside the transaction. Keyed by
    // the entry object itself so two writes at the same id in different tables
    // cannot be confused for one another.
    const verifiedEntries = new Set();
    if (plan.key) {
      for (const entry of plan.writes) {
        if (!entry || typeof entry !== 'object' || !entry.row) continue;
        const verdict = await verifyRowIntegrity(entry.row, plan.key, entry.table);
        if (verdict === 'ok') verifiedEntries.add(entry);
      }
    }

    const tableNames = [...new Set(plan.writes.map((entry) => entry.table))];
    const tables = tableNames.map((name) => this.table(name));

    await this.transaction('rw', tables, async () => {
      for (const name of tableNames) {
        const table = this.table(name);
        const entries = plan.writes.filter((entry) => entry.table === name);

        for (let offset = 0; offset < entries.length; offset += BULK_WRITE_CHUNK) {
          const chunk = entries.slice(offset, offset + BULK_WRITE_CHUNK);
          const existingRows = await table.bulkGet(chunk.map((entry) => entry.row.id));
          const stillWins = chunk
            .filter((entry, i) => {
              const existing = existingRows[i];
              const row = entry.row;
              if (!existing) return true;
              // Re-assert the plan-time invariant. A row that would overwrite or
              // delete an existing one must be provably ours on every dimension,
              // and a sync landing between preview and confirm can turn an
              // "added" into an overwrite.
              if (!verifiedEntries.has(entry) || !recordHasAuthenticatedHeader(row)) {
                supersededSincePreview++;
                refusedSincePreview++;
                return false;
              }
              if (plan.incomingWins(existing, row)) return true;
              supersededSincePreview++;
              return false;
            })
            .map((entry) => entry.row);
          // Same bulkPut caveat as the re-seal sweep: stamp the index mirror
          // or a restored tombstone stops replicating as a deletion.
          if (stillWins.length > 0) {
            await table.bulkPut(stillWins.map((row) => this._withDelIndex(row)));
          }
          written[name] = (written[name] || 0) + stillWins.length;
        }
      }
    });

    return { written, supersededSincePreview, refusedSincePreview };
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
 * are NOT interchangeable. Each bullet below is scoped to the rows it is
 * actually true of, because these three dimensions did not ship together:
 *
 *  - EVERY v2 row: the key opened the envelope, and the envelope's own copy of
 *    the plaintext id / updatedAt / deleted header matches the row's. A
 *    rewritten header fails here with no exception - encryptRecord has sealed
 *    that header inside the payload since the commit that introduced v2 at all
 *    (crypto.js, `payload.id = id; payload.updatedAt = updatedAt;
 *    payload.deleted = deleted;`), so no v2 row exists that lacks it.
 *  - A v2 row sealed WITH a digest map: the SHA-256 of every attached binary
 *    field matches too, so a swapped photo fails. A v2 row sealed before that
 *    map existed carries none, and its bytes are reported `unverified` rather
 *    than tampered - and accepted.
 *  - A v2 row sealed WITH a table binding: the table it is being presented as
 *    matches the one it was sealed for, so a cross-table replay fails. A row
 *    sealed before that binding existed is again `unverified`, and accepted.
 *  - A v1 row: none of the three holds. It proves ONLY that some
 *    `<base>Cipher` field opened under this key. decryptLegacyRecord() stamps
 *    `_headerTampered: false` and `_binaryTampered: false` unconditionally,
 *    because v1 has no authenticated header, no digest and no binding to
 *    compare against. A clean verdict on a v1 row therefore means "unknowable",
 *    not "clean", which is exactly why one lifted ciphertext used as a decoy
 *    pair passed this check (test 11bis) and why planBackupMerge separately
 *    demands recordHasAuthenticatedHeader() before letting anything overwrite
 *    or tombstone an existing row.
 *
 * A fourth case joins them: a row this device's own sweep re-sealed out of a v1
 * row carries PROVENANCE_LEGACY, which surfaces as `_headerUnverified`. The
 * envelope is genuine; its CONTENT came from a header nothing ever
 * authenticated. Same verdict, same standing: may create, never overwrite.
 *
 * The residual window, stated rather than papered over: the digest and table
 * carve-outs are not permanent on a device that runs the sweep, but they are not
 * instant either. db.migrateLegacyRecords() re-seals such rows at unlock - both
 * carve-outs, one sweep - so a device drains its own. Until that sweep has
 * completed on a given device, that device's older photos are still swappable
 * and its older rows still movable between tables.
 *
 * A PARTNER ON A BUILD OLDER THAN THAT SWEEP NEVER DRAINS AT ALL, because the
 * sweep is what ships in this build. Their rows keep arriving unverified
 * forever, which means every update and every delete they send is refused. That
 * is the deliberate trade; what is not acceptable is doing it silently, so both
 * gates count those refusals apart from ordinary staleness and the caller says
 * so - see `unverifiable` on planBackupMerge's totals and on the sync status.
 *
 * @param {Object} row
 * @param {CryptoKey} key
 * @param {string} [tableName] - The table the row is being presented as. Omit it
 *   and the table dimension is simply not checked.
 * @returns {Promise<'ok'|'unverified'|'undecryptable'|'tampered'>} A REASON, not
 *   a boolean, and FOUR of them - planBackupMerge branches on 'unverified'
 *   specifically, so leaving it out of this list was not a documentation nit.
 *   'ok': proved on every dimension this build checks; may overwrite or delete.
 *   'unverified': opened cleanly, but at least one binding is ABSENT (v1 row,
 *   pre-digest photo, pre-table-binding envelope, or a sweep-re-sealed v1 row);
 *   may create, never overwrite or delete.
 *   'undecryptable': "this file belongs to another vault, or the bytes rotted".
 *   'tampered': "this row opened under YOUR key and was then edited".
 *   The last two are separated because the import preview reports them
 *   separately - reporting 'tampered' as 'undecryptable' told the user "wrong
 *   key" about the one row that proves someone went at their file deliberately.
 */
async function verifyRowIntegrity(row, key, tableName) {
  // A successful decrypt is not on its own proof the key was used: a row with no
  // ciphertext at all resolves through the legacy path without touching the key.
  // Require an authenticated payload FIRST, or a foreign row on a colliding
  // stable id (bkt-default-1, roulette-current) would overwrite a live one.
  // 'undecryptable' is the honest label for it: the row carries nothing this
  // vault's key could ever have sealed.
  if (!recordCarriesAuthenticatedPayload(row)) return 'undecryptable';
  try {
    const plain = await decryptRecord(row, key, { table: tableName });
    if (!plain) return 'undecryptable';
    // `_headerTampered` already covers the other two; all three are named here
    // so that decoupling them later cannot silently reopen the photo-swap or
    // the cross-table hole.
    if (
      plain._headerTampered === true ||
      plain._binaryTampered === true ||
      plain._tableTampered === true
    ) {
      return 'tampered';
    }
    // Binding present and correct is 'ok'. Binding ABSENT is neither ok nor
    // tampered - it is unknowable, and it must not be silently treated as ok.
    //
    // This is the hole the re-seal sweep does NOT close, and the reason it does
    // not is worth stating plainly: migrateLegacyRecords re-seals rows this
    // device HOLDS, while this function only ever decrypts the row ARRIVING.
    // Sweeping therefore does nothing about an envelope an attacker harvested
    // before binding existed. Without this verdict such an envelope stays a
    // permanent capability against that id - on every device, however many
    // times either side sweeps.
    if (
      plain._binaryUnverified === true ||
      plain._tableUnverified === true ||
      plain._headerUnverified === true
    ) {
      return 'unverified';
    }
    return 'ok';
  } catch {
    return 'undecryptable';
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
    // `out.imageBlob` came straight out of parsed backup JSON, so it can be any
    // value at all. Two ways that used to hurt, both before the size check
    // below could run:
    //   imageBlob: 9e15         -> new Uint8Array(9e15) throws RangeError, which
    //                              is NOT caught here, so ONE hostile row aborts
    //                              an otherwise legitimate 20,000-row restore.
    //   imageBlob: 419430400    -> allocates 400MB of zeros first, then fails the
    //                              size check. A few such rows is a reliable OOM.
    // A number is never a valid blob, so reject anything that is not already
    // bytes or a real byte container, and bound the length BEFORE allocating.
    let bytes;
    if (out.imageBlob instanceof Uint8Array) {
      bytes = out.imageBlob;
    } else if (out.imageBlob instanceof ArrayBuffer) {
      if (out.imageBlob.byteLength > MAX_IMAGE_BLOB_BYTES) return null;
      bytes = new Uint8Array(out.imageBlob);
    } else if (Array.isArray(out.imageBlob)) {
      if (out.imageBlob.length > MAX_IMAGE_BLOB_BYTES) return null;
      bytes = new Uint8Array(out.imageBlob);
    } else {
      return null;
    }
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
