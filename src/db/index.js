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
} from '../services/crypto';

/** Tables that participate in P2P sync and in backups. */
export const SYNCED_TABLES = Object.freeze([
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
]);

/**
 * Tables a backup file is allowed to write into.
 *
 * `vaultMeta` is deliberately ABSENT. It holds the salt and canary that key the
 * entire vault; letting a restore overwrite them re-keys the vault and orphans
 * every record created since the backup was taken. It is still exported (so the
 * file is a complete forensic record and so a future "restore onto a blank
 * device" flow can read the salt deliberately), but import always skips it.
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

    const updatedAt = Math.max(Date.now(), (existing.updatedAt || 0) + 1);
    let row;
    if (key) {
      row = await encryptRecord({ id, updatedAt, deleted: true }, key);
    } else {
      row = { id, updatedAt, deleted: true, v: existing.v || 1 };
    }
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
   * Imports validated decrypted tables into local IndexedDB.
   *
   * Hardened against a corrupted, oversized or hand-edited backup:
   *  - `vaultMeta` is skipped outright, so a restore can never re-key the vault
   *    and orphan everything created since the backup.
   *  - Only known fields survive; arbitrary extra keys are dropped instead of
   *    being persisted into live tables.
   *  - Caller-supplied objects are never mutated.
   *  - Per-table record caps and a per-blob byte cap.
   *  - The transaction is scoped to the tables actually being written.
   *
   * @param {Record<string, Object[]>} tables
   * @returns {Promise<{ imported: Record<string, number>, skipped: number, skippedTables: string[] }>}
   */
  async importRawDataFromBackup(tables) {
    if (!tables || typeof tables !== 'object' || Array.isArray(tables)) {
      throw new Error('Invalid backup table payload');
    }

    const imported = {};
    const skippedTables = [];
    let skipped = 0;

    const staged = new Map();

    for (const [tableName, records] of Object.entries(tables)) {
      if (!IMPORTABLE_TABLES.has(tableName)) {
        skippedTables.push(tableName);
        continue;
      }
      if (!Array.isArray(records)) {
        skippedTables.push(tableName);
        continue;
      }
      if (records.length > MAX_RECORDS_PER_TABLE) {
        throw new Error(
          `Backup rejected: "${tableName}" contains ${records.length} records (limit ${MAX_RECORDS_PER_TABLE}).`
        );
      }

      const clean = [];
      for (const record of records) {
        const sanitized = sanitizeImportedRecord(tableName, record);
        if (!sanitized) {
          skipped++;
          continue;
        }
        clean.push(sanitized);
      }
      staged.set(tableName, clean);
    }

    if (staged.size === 0) {
      return { imported, skipped, skippedTables };
    }

    const targetTables = Array.from(staged.keys()).map((name) => this.table(name));

    await this.transaction('rw', targetTables, async () => {
      for (const [tableName, records] of staged.entries()) {
        const table = this.table(tableName);
        for (let offset = 0; offset < records.length; offset += BULK_WRITE_CHUNK) {
          await table.bulkPut(records.slice(offset, offset + BULK_WRITE_CHUNK));
        }
        imported[tableName] = records.length;
      }
    });

    return { imported, skipped, skippedTables };
  }
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
export default db;
