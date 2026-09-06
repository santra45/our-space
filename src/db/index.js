/**
 * src/db/index.js
 * IndexedDB persistence layer using Dexie.js
 * Zero plaintext is stored in the database.
 */
import Dexie from 'dexie';

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
   * Exports all encrypted records as a single JSON object for backup
   */
  async exportEncryptedVault() {
    const tables = ['vaultMeta', 'memories', 'milestones', 'dateIdeas', 'letters', 'bucketList'];
    const backup = {
      version: 1,
      exportedAt: new Date().toISOString(),
      tables: {},
    };

    for (const tableName of tables) {
      const records = await this.table(tableName).toArray();
      // For memories, convert Uint8Array binary imageBlobs to base64 strings
      if (tableName === 'memories') {
        backup.tables[tableName] = records.map((r) => {
          const clone = { ...r };
          if (clone.imageBlob) {
            let binary = '';
            const bytes = new Uint8Array(clone.imageBlob);
            for (let i = 0; i < bytes.byteLength; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            clone.imageBlobBase64 = window.btoa(binary);
            delete clone.imageBlob;
          }
          return clone;
        });
      } else {
        backup.tables[tableName] = records;
      }
    }

    return backup;
  }

  /**
   * Imports an exported backup into the local database
   */
  async importEncryptedVault(backup) {
    if (!backup || !backup.tables) {
      throw new Error('Invalid vault backup file format');
    }

    await this.transaction('rw', this.tables, async () => {
      for (const [tableName, records] of Object.entries(backup.tables)) {
        const table = this.table(tableName);
        for (const record of records) {
          if (tableName === 'memories' && record.imageBlobBase64) {
            const binary = window.atob(record.imageBlobBase64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) {
              bytes[i] = binary.charCodeAt(i);
            }
            record.imageBlob = bytes;
            delete record.imageBlobBase64;
          }
          await table.put(record);
        }
      }
    });
  }
}

export const db = new SweetheartDatabase();
export default db;
