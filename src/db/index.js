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

export const SYNCED_TABLES = Object.freeze([
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
  'loveBursts',
  'dailyAnswers',
  'people',
]);

export const IMPORTABLE_TABLES = new Set(SYNCED_TABLES);

export const EXPORTED_TABLES = Object.freeze(['vaultMeta', ...SYNCED_TABLES]);

export const MAX_BACKUP_FILE_BYTES = 150 * 1024 * 1024;

export const MAX_RECORDS_PER_TABLE = 20000;

export { MAX_IMAGE_BLOB_BYTES };

const BULK_WRITE_CHUNK = 100;

const MAX_BACKUP_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

export class SweetheartDatabase extends Dexie {
  constructor() {
    super('SweetheartVaultDB');

    this.version(2).stores({
      vaultMeta: 'id',
      memories: 'id, updatedAt, _del',
      milestones: 'id, updatedAt, _del',
      dateIdeas: 'id, updatedAt, _del',
      letters: 'id, updatedAt, _del',
      bucketList: 'id, updatedAt, _del',
    });

    this.version(3).stores({
      vaultMeta: 'id',
      memories: 'id, updatedAt, _del',
      milestones: 'id, updatedAt, _del',
      dateIdeas: 'id, updatedAt, _del',
      letters: 'id, updatedAt, _del',
      bucketList: 'id, updatedAt, _del',
      loveBursts: 'id, updatedAt, _del',
    });

    this.version(4).stores({
      vaultMeta: 'id',
      memories: 'id, updatedAt, _del',
      milestones: 'id, updatedAt, _del',
      dateIdeas: 'id, updatedAt, _del',
      letters: 'id, updatedAt, _del',
      bucketList: 'id, updatedAt, _del',
      loveBursts: 'id, updatedAt, _del',
      dailyAnswers: 'id, updatedAt, _del',
    });

    this.version(5).stores({
      vaultMeta: 'id',
      memories: 'id, updatedAt, _del',
      milestones: 'id, updatedAt, _del',
      dateIdeas: 'id, updatedAt, _del',
      letters: 'id, updatedAt, _del',
      bucketList: 'id, updatedAt, _del',
      loveBursts: 'id, updatedAt, _del',
      dailyAnswers: 'id, updatedAt, _del',
      people: 'id, updatedAt, _del',
    });

    this._installTombstoneHooks();
  }

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

  async getManifest() {
    const manifest = {};

    for (const tableName of SYNCED_TABLES) {
      const table = this.table(tableName);

      const ids = await table.toCollection().primaryKeys();
      const entries = new Map();
      for (const id of ids) {
        entries.set(id, { id, updatedAt: 0, deleted: false });
      }

      await table.orderBy('updatedAt').eachKey((updatedAt, cursor) => {
        const entry = entries.get(cursor.primaryKey);
        if (entry && Number.isFinite(updatedAt)) entry.updatedAt = updatedAt;
      });

      const tombstoned = await table.where('_del').equals(1).primaryKeys();
      for (const id of tombstoned) {
        const entry = entries.get(id);
        if (entry) entry.deleted = true;
      }

      manifest[tableName] = Array.from(entries.values());
    }

    return manifest;
  }

  async putEncrypted(tableName, plainFields, key) {
    if (!SYNCED_TABLES.includes(tableName)) {
      throw new Error(`putEncrypted: unknown table "${tableName}"`);
    }
    if (!key) throw new Error('putEncrypted: vault is locked');

    const row = await encryptRecord(plainFields, key, { table: tableName });
    await this.table(tableName).put(this._withDelIndex(row));
    return row;
  }

  async getDecrypted(tableName, id, key) {
    if (!key) throw new Error('getDecrypted: vault is locked');
    const row = await this.table(tableName).get(id);
    if (!row) return null;
    return await decryptRecord(row, key, { table: tableName });
  }

  async listDecrypted(tableName, key, options = {}) {
    if (!key) throw new Error('listDecrypted: vault is locked');
    const rows = await this.table(tableName).toArray();
    const out = [];
    for (const row of rows) {
      if (!options.includeDeleted && row.deleted === true) continue;
      try {
        out.push(await decryptRecord(row, key, { table: tableName }));
      } catch {
      }
    }
    return out;
  }

  async softDelete(tableName, id, key) {
    const existing = await this.table(tableName).get(id);
    if (!existing) return null;
    if (!key) {
      throw new Error('softDelete requires the vault key to write a replicable tombstone.');
    }

    const updatedAt = Math.max(await syncSafeNow(), (existing.updatedAt || 0) + 1);
    const row = await encryptRecord({ id, updatedAt, deleted: true }, key, {
      table: tableName,
    });
    await this.table(tableName).put(this._withDelIndex(row));
    return row;
  }

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

  async readVaultIdentity() {
    try {
      const meta = await this.vaultMeta.get('config');
      return { ok: true, meta: meta && meta.salt ? meta : null };
    } catch (err) {
      return { ok: false, meta: null, error: err };
    }
  }

  async planBackupMerge(tables, key) {
    if (!tables || typeof tables !== 'object' || Array.isArray(tables)) {
      throw new Error('Invalid backup table payload');
    }
    if (!key) {
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

      const candidates = [];
      for (const record of records) {
        const row = sanitizeImportedRecord(tableName, record);
        if (!row) {
          stats.invalid++;
          continue;
        }
        const verdict = await verifyRowIntegrity(row, key, tableName);
        if (verdict !== 'ok' && verdict !== 'unverified') {
          stats[verdict]++;
          continue;
        }
        candidates.push({ row, verified: verdict === 'ok' });
      }

      for (let offset = 0; offset < candidates.length; offset += BULK_WRITE_CHUNK) {
        const chunk = candidates.slice(offset, offset + BULK_WRITE_CHUNK);
        const existingRows = await table.bulkGet(chunk.map((entry) => entry.row.id));
        for (let i = 0; i < chunk.length; i++) {
          const existing = existingRows[i];
          const { row, verified } = chunk[i];

          if (!recordHasAuthenticatedHeader(row)) {
            stats.unauthenticated++;
            continue;
          }

          if (!existing) {
            if (row.deleted === true) {
              stats.invalid++;
              continue;
            }
            stats.added++;
            writes.push({ table: tableName, row });
            continue;
          }

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

    return { writes, perTable, totals, skippedTables, incomingWins, key };
  }

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
              if (!recordHasAuthenticatedHeader(row)) {
                supersededSincePreview++;
                refusedSincePreview++;
                return false;
              }
              if (!existing) return true;
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
          if (stillWins.length > 0) {
            await table.bulkPut(stillWins.map((row) => this._withDelIndex(row)));
          }
          written[name] = (written[name] || 0) + stillWins.length;
        }
      }
    });

    return { written, supersededSincePreview, refusedSincePreview };
  }

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

export function compareVaultIdentity(backupIdentity, localRead) {
  if (!localRead || localRead.ok !== true) return 'unknown';
  if (!localRead.meta) return 'no-local-vault';
  if (!backupIdentity || typeof backupIdentity.salt !== 'string') return 'unknown';
  return backupIdentity.salt === localRead.meta.salt ? 'same' : 'foreign';
}

async function verifyRowIntegrity(row, key, tableName) {
  if (!recordHasAuthenticatedHeader(row)) return 'undecryptable';
  try {
    const plain = await decryptRecord(row, key, { table: tableName });
    if (!plain) return 'undecryptable';
    if (
      plain._headerTampered === true ||
      plain._binaryTampered === true ||
      plain._tableTampered === true
    ) {
      return 'tampered';
    }
    if (plain._binaryUnverified === true || plain._tableUnverified === true) {
      return 'unverified';
    }
    return 'ok';
  } catch {
    return 'undecryptable';
  }
}

async function syncSafeNow() {
  try {
    const mod = await import('../services/peerSync.js');
    const engine = mod && mod.default;
    if (engine && typeof engine.getSyncSafeTimestamp === 'function') {
      return engine.getSyncSafeTimestamp();
    }
  } catch {
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

const COMMON_FIELDS = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', '_del'];
const BINARY_FIELDS_BY_TABLE = {
  memories: ['imageBlob'],
};

function sanitizeImportedRecord(tableName, record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return null;
  if (typeof record.id !== 'string' || record.id.length === 0 || record.id.length > 128) return null;
  if (record.updatedAt !== undefined && !Number.isFinite(record.updatedAt)) return null;
  if (Number.isFinite(record.updatedAt)) {
    if (record.updatedAt < 0) return null;
    if (record.updatedAt > Date.now() + MAX_BACKUP_CLOCK_SKEW_MS) return null;
  }
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

let upgradeBlocked = false;
const upgradeBlockedListeners = new Set();

db.on('blocked', () => {
  upgradeBlocked = true;
  for (const listener of upgradeBlockedListeners) {
    try {
      listener(true);
    } catch {
    }
  }
});

export function isUpgradeBlocked() {
  return upgradeBlocked;
}

export function subscribeUpgradeBlocked(listener) {
  upgradeBlockedListeners.add(listener);
  if (upgradeBlocked) listener(true);
  return () => upgradeBlockedListeners.delete(listener);
}

export default db;
