/**
 * src/db/index.js
 * IndexedDB persistence layer using Dexie.js
 * Zero plaintext is stored in the database.
 */
import Dexie from 'dexie';

const ALLOWED_DB_TABLES = new Set([
  'vaultMeta',
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
]);

export class SweetheartDatabase extends Dexie {
  constructor() {
    super('SweetheartVaultDB');

    // Define database tables and indexable fields
    this.version(1).stores({
      vaultMeta: 'id',
      memories: 'id, date, updatedAt, deleted',
      milestones: 'id, date, updatedAt, deleted',
      dateIdeas: 'id, category, isScratched, updatedAt, deleted',
      letters: 'id, unlockDate, isOpened, updatedAt, deleted',
      bucketList: 'id, completed, updatedAt, deleted',
    });
  }

  /**
   * Generates a manifest of all local record IDs and their last update timestamps
   * Used by the WebRTC sync engine to detect differences
   */
  async getManifest() {
    const tables = ['memories', 'milestones', 'dateIdeas', 'letters', 'bucketList'];
    const manifest = {};

    for (const tableName of tables) {
      const records = await this.table(tableName).toArray();
      manifest[tableName] = records.map((r) => ({
        id: r.id,
        updatedAt: r.updatedAt || 0,
        deleted: !!r.deleted,
      }));
    }

    return manifest;
  }

  /**
   * Serializes all encrypted records for single-container backup packaging
   */
  async exportRawDataForBackup() {
    const tables = ['vaultMeta', 'memories', 'milestones', 'dateIdeas', 'letters', 'bucketList'];
    const data = {
      version: 1,
      tables: {},
    };

    for (const tableName of tables) {
      const records = await this.table(tableName).toArray();
      if (tableName === 'memories') {
        data.tables[tableName] = records.map((r) => {
          const clone = { ...r };
          if (clone.imageBlob) {
            let binary = '';
            const bytes = new Uint8Array(clone.imageBlob);
            for (let i = 0; i < bytes.byteLength; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            clone.imageBlobBase64 = (typeof window !== 'undefined' ? window.btoa : globalThis.btoa)(binary);
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
   * Imports validated decrypted tables into local IndexedDB
   */
  async importRawDataFromBackup(tables) {
    if (!tables || typeof tables !== 'object') {
      throw new Error('Invalid backup table payload');
    }

    await this.transaction('rw', this.tables, async () => {
      for (const [tableName, records] of Object.entries(tables)) {
        if (!ALLOWED_DB_TABLES.has(tableName) || !Array.isArray(records)) {
          continue;
        }

        const table = this.table(tableName);
        for (const record of records) {
          if (!record || typeof record !== 'object' || !record.id) {
            continue;
          }

          if (tableName === 'memories' && typeof record.imageBlobBase64 === 'string') {
            try {
              const binary = (typeof window !== 'undefined' ? window.atob : globalThis.atob)(record.imageBlobBase64);
              const bytes = new Uint8Array(binary.length);
              for (let i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
              }
              record.imageBlob = bytes;
              delete record.imageBlobBase64;
            } catch {
              continue;
            }
          }
          await table.put(record);
        }
      }
    });
  }
}

export const db = new SweetheartDatabase();
export default db;
