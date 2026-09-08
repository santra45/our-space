/**
 * src/db/index.js
 * IndexedDB persistence layer using Dexie.js
 *
 * SCHEMA v2 - ENCRYPTED METADATA, AND NOTHING ELSE
 * Every record is one AES-GCM envelope. Only three things stay readable without
 * the key:
 *
 *   id         string   primary key, needed to address a record over sync
 *   updatedAt  number   last-write-wins comparison, needed without decrypting
 *   deleted    boolean  tombstone, needed so deletions replicate
 *
 * Everything else lives inside `ciphertext`/`iv`. Filtering and sorting is an
 * in-memory pass after decryptRecord(), not an index query.
 *
 * THERE IS EXACTLY ONE RECORD SHAPE, and that is a security property rather
 * than tidiness. The app briefly carried a second, older shape whose plaintext
 * `id` / `updatedAt` / `deleted` header was bound to nothing, so a single
 * ciphertext produced under the vault key could be aimed at any id as a forged
 * tombstone and no amount of checking could tell. Every gate below that asks
 * "may this row destroy something?" now has a single answer to give, because
 * an unsealed row cannot get past decryptRecord() at all.
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
  PBKDF2_ITERATIONS_CURRENT,
  bufferToBase64,
  base64ToBuffer,
  decryptRecord,
  encryptRecord,
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

    /**
     * The only schema this app has ever shipped to anyone.
     *
     * Indexes are the primary key plus the two things sync compares without a
     * key. Nothing else is indexed, because nothing else is readable.
     *
     * DO NOT RENUMBER THIS TO 1. The number is what IndexedDB compares against
     * the version already on a device, and a lower number is a downgrade: Dexie
     * refuses to open, and the vault looks like it has vanished. It stays 2
     * forever, whatever else is deleted around it.
     */
    this.version(2).stores({
      vaultMeta: 'id',
      memories: 'id, updatedAt, _del',
      milestones: 'id, updatedAt, _del',
      dateIdeas: 'id, updatedAt, _del',
      letters: 'id, updatedAt, _del',
      bucketList: 'id, updatedAt, _del',
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
   * `where('_del').equals(1)`, so a restored tombstone was advertised to the
   * partner as `deleted: false` - and a deleted memory came back from the dead
   * on the next sync.
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
  async putEncrypted(tableName, plainFields, key) {
    if (!SYNCED_TABLES.includes(tableName)) {
      throw new Error(`putEncrypted: unknown table "${tableName}"`);
    }
    if (!key) throw new Error('putEncrypted: vault is locked');

    // The table is sealed INTO the envelope, so this row cannot later be
    // replayed into a different table under its own valid ciphertext (see
    // TABLE_BINDING_FIELD in crypto.js).
    const row = await encryptRecord(plainFields, key, { table: tableName });
    await this.table(tableName).put(this._withDelIndex(row));
    return row;
  }

  /**
   * Reads one row and decrypts it.
   * @returns {Promise<Object|null>}
   */
  async getDecrypted(tableName, id, key) {
    if (!key) throw new Error('getDecrypted: vault is locked');
    const row = await this.table(tableName).get(id);
    if (!row) return null;
    // The table is passed so a row sealed for a DIFFERENT table is flagged
    // `_tableTampered` here too. Without it, decryptRecord has no expected table
    // to compare the sealed `_tbl` against, so it reports nothing and every
    // screen renders a cross-table row as ordinary content. The write gates
    // refuse such a row an overwrite, but a row sealed before table binding
    // existed may still create - so one CAN be sitting in a table, and a read
    // that does not ask is a read that will not notice.
    return await decryptRecord(row, key, { table: tableName });
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
        // Same reason as getDecrypted: without the expected table, a row sealed
        // for another one is indistinguishable from a legitimate record.
        out.push(await decryptRecord(row, key, { table: tableName }));
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
    const row = await encryptRecord({ id, updatedAt, deleted: true }, key, {
      table: tableName,
    });
    await this.table(tableName).put(this._withDelIndex(row));
    return row;
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
   *                  A row that is not a sealed envelope at all cannot pass this
   *                  step, so it can no longer create either.
   *  2b. AUTHORITY   overwriting or tombstoning a row that ALREADY EXISTS
   *                  additionally requires that verifyRowIntegrity() returned
   *                  'ok' rather than 'unverified'. A row whose photo-digest or
   *                  table binding is merely ABSENT may create and nothing else.
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
   *                      ABSENT rather than wrong - an envelope sealed before the
   *                      photo digest or the table binding existed.
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

          // SEALED OR NOTHING, whether or not anything is already here.
          //
          // Creating used to be free, because unsealed rows had to be let in so
          // an old backup could still restore. There are no unsealed rows any
          // more, so the carve-out is gone and creating is a real assertion
          // again: every row that lands in a table arrived inside an envelope
          // somebody holding the vault key sealed.
          //
          // verifyRowIntegrity() has already refused anything unsealed, so this
          // is belt and braces rather than the only line of defence - which is
          // exactly what it should be on a path that writes to the user's
          // library from a file a stranger could have handed them.
          if (!recordHasAuthenticatedHeader(row)) {
            stats.unauthenticated++;
            continue;
          }

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
            // Otherwise there is nothing here to destroy, so a sealed row whose
            // photo digest or table binding merely predates this build may
            // create. It could still be a junk row - but it is a VISIBLE junk
            // row the user can delete, which is the property the earlier note
            // claimed without checking the tombstone case.
            stats.added++;
            writes.push({ table: tableName, row });
            continue;
          }

          // Something already exists at this id, so this write can destroy data,
          // and a binding that is merely ABSENT rather than wrong is not good
          // enough for that: an envelope predating the photo digest or the table
          // binding cannot prove which bytes or which table it belongs to.
          // Otherwise a single harvested pre-binding envelope erases a photo
          // (swap the bytes, or just omit them) or deletes a letter from another
          // table.
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
              // Re-assert the plan-time invariant, starting with the one that
              // holds whether or not anything is already here: a plan is a
              // caller-supplied object, and nothing unsealed may be written into
              // a table under any circumstances.
              if (!recordHasAuthenticatedHeader(row)) {
                supersededSincePreview++;
                refusedSincePreview++;
                return false;
              }
              if (!existing) return true;
              // A row that would overwrite or delete an existing one must be
              // provably ours on every dimension, and a sync landing between
              // preview and confirm can turn an "added" into an overwrite.
              if (!verifiedEntries.has(entry)) {
                supersededSincePreview++;
                refusedSincePreview++;
                return false;
              }
              if (plan.incomingWins(existing, row)) return true;
              supersededSincePreview++;
              return false;
            })
            .map((entry) => entry.row);
          // bulkPut does not fire the Dexie tombstone hooks and encryptRecord
          // strips the field, so the index mirror is stamped explicitly here or
          // a restored tombstone stops replicating as a deletion.
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
        : PBKDF2_ITERATIONS_CURRENT,
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
      : PBKDF2_ITERATIONS_CURRENT,
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
 * WHAT THIS PROVES, AND WHAT IT DOES NOT. Every row reaching this function is a
 * sealed envelope or it is nothing, so the first bullet holds unconditionally.
 * The other two are scoped, because the three bindings did not ship together:
 *
 *  - EVERY row: the key opened the envelope, and the envelope's own copy of
 *    the plaintext id / updatedAt / deleted header matches the row's. A
 *    rewritten header fails here with no exception - encryptRecord has sealed
 *    that header inside the payload since the envelope existed at all
 *    (crypto.js, `payload.id = id; payload.updatedAt = updatedAt;
 *    payload.deleted = deleted;`), so no row exists that lacks it.
 *  - A row sealed WITH a digest map: the SHA-256 of every attached binary
 *    field matches too, so a swapped photo fails. A row sealed before that
 *    map existed carries none, and its bytes are reported `unverified` rather
 *    than tampered - and accepted.
 *  - A row sealed WITH a table binding: the table it is being presented as
 *    matches the one it was sealed for, so a cross-table replay fails. A row
 *    sealed before that binding existed is again `unverified`, and accepted.
 *
 * The residual window, stated rather than papered over: an envelope harvested
 * before the digest or table binding existed can still be replayed at the id it
 * was sealed for. That is exactly what the 'unverified' verdict is for - such a
 * row may create, never overwrite or delete - and it is why the verdict cannot
 * be collapsed into 'ok' however old and innocent the row looks. Both gates
 * count those refusals apart from ordinary staleness and the caller says so;
 * see `unverifiable` on planBackupMerge's totals and on the sync status.
 *
 * @param {Object} row
 * @param {CryptoKey} key
 * @param {string} [tableName] - The table the row is being presented as. Omit it
 *   and the table dimension is simply not checked.
 * @returns {Promise<'ok'|'unverified'|'undecryptable'|'tampered'>} A REASON, not
 *   a boolean, and FOUR of them - planBackupMerge branches on 'unverified'
 *   specifically, so leaving it out of this list was not a documentation nit.
 *   'ok': proved on every dimension this build checks; may overwrite or delete.
 *   'unverified': opened cleanly, but at least one binding is ABSENT (a
 *   pre-digest photo or a pre-table-binding envelope); may create, never
 *   overwrite or delete.
 *   'undecryptable': "this is not a sealed record, or it belongs to another
 *   vault, or the bytes rotted".
 *   'tampered': "this row opened under YOUR key and was then edited".
 *   The last two are separated because the import preview reports them
 *   separately - reporting 'tampered' as 'undecryptable' told the user "wrong
 *   key" about the one row that proves someone went at their file deliberately.
 */
async function verifyRowIntegrity(row, key, tableName) {
  // Asked FIRST so the answer is never inferred from a decrypt that resolved.
  // decryptRecord() now throws on anything that is not a complete envelope, so
  // this is agreement rather than a second opinion - but it is the check the
  // whole two-tier rule is stated in terms of, and stating it here means the
  // gate does not depend on how decryptRecord happens to fail today.
  // 'undecryptable' is the honest label: the row carries nothing this vault's
  // key could ever have sealed.
  if (!recordHasAuthenticatedHeader(row)) return 'undecryptable';
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
    // An envelope an attacker harvested before binding existed would otherwise
    // stay a permanent capability against that id, on every device, forever.
    if (plain._binaryUnverified === true || plain._tableUnverified === true) {
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
 *
 * A stored row is its envelope plus, on a photo, the binary that hangs off the
 * top level of it - and nothing else. Every metadata field a record has lives
 * INSIDE the ciphertext, so there is nothing per-table to allow beyond the
 * photo. Names that used to appear here (`date`, `category`, `unlockDate`,
 * `completed`, `isOpened`, the `<base>Cipher`/`<base>Iv` pairs) named plaintext
 * columns that no longer exist; allowing them meant a hostile file could
 * persist arbitrary readable junk alongside a genuine envelope.
 */
const COMMON_FIELDS = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', '_del'];
const BINARY_FIELDS_BY_TABLE = {
  memories: ['imageBlob', 'mimeType'],
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
  // Version 2 or nothing, and an ABSENT version is not a pass. There is one
  // record shape; anything claiming another is not something this build can
  // reason about, so it does not get written.
  if (record.v !== RECORD_SCHEMA_VERSION) return null;

  const allowed = new Set([...COMMON_FIELDS, ...(BINARY_FIELDS_BY_TABLE[tableName] || [])]);
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
 * IndexedDB will not change a database's version while another tab still holds
 * it open at the old one, so db.open() hangs and every read rejects. That read
 * failure is indistinguishable from "this device has no vault", which routed a
 * returning user to the CREATE VAULT form - one confirmation away from writing a
 * fresh salt over a fully populated live vault. Dexie tells us exactly why, so
 * the UI can say "close the other tabs" instead of offering to erase everything.
 *
 * This build declares one version, so nothing upgrades today. The detection
 * stays: the next time the schema does move, the tab that is holding the old
 * one open is the tab that is about to look like a wiped device.
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
