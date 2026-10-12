import { AsyncLocalStorage } from 'node:async_hooks';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const repo = join(here, '..', '..', '..', '..');
export const fixtures = join(here, '..', 'fixtures');

const memoryStorage = new Map();
Object.defineProperty(globalThis, 'localStorage', {
  configurable: true,
  value: {
    getItem: (k) => (memoryStorage.has(k) ? memoryStorage.get(k) : null),
    setItem: (k, v) => memoryStorage.set(k, String(v)),
    removeItem: (k) => memoryStorage.delete(k),
    clear: () => memoryStorage.clear(),
  },
});

const load = (path) => import(pathToFileURL(join(repo, path)).href);

export const crypto = await load('src/services/crypto.js');
const dbModule = await load('src/db/index.js');
export const { PeerSyncManager } = await load('src/services/peerSync.js');
export const { pack, unpack } = await import('peerjs-js-binarypack');
export const peerjs = await import('peerjs/dist/bundler.mjs');

const db = dbModule.default;
const { SweetheartDatabase, EXPORTED_TABLES } = dbModule;
export const Chunker = Object.getPrototypeOf(peerjs.util.constructor);
export const CHUNKED_MTU = peerjs.util.chunkedMTU;

export const toBase64 = (bytes) => Buffer.from(bytes).toString('base64');
export const fromBase64 = (text) => new Uint8Array(Buffer.from(text, 'base64'));

export function seededBytes(seed, length) {
  const out = new Uint8Array(length);
  let block = createHash('sha256').update(seed).digest();
  let offset = 0;
  while (offset < length) {
    for (let i = 0; i < block.length && offset < length; i++) out[offset++] = block[i];
    block = createHash('sha256').update(block).digest();
  }
  return out;
}

export class FakeVaultStore {
  constructor() {
    this._tables = new Map();
    for (const name of EXPORTED_TABLES) this._tables.set(name, new Map());
  }

  table(name) {
    const rows = this._tables.get(name);
    if (!rows) throw new Error(`FakeVaultStore: unknown table "${name}"`);
    const sorted = () => [...rows.keys()].sort();
    return {
      async get(id) {
        return rows.get(id);
      },
      async put(row) {
        rows.set(row.id, row);
      },
      async toArray() {
        return sorted().map((id) => rows.get(id));
      },
      async bulkGet(ids) {
        return ids.map((id) => rows.get(id));
      },
      async bulkPut(list) {
        for (const row of list) rows.set(row.id, row);
      },
      toCollection() {
        return {
          async primaryKeys() {
            return sorted();
          },
        };
      },
      orderBy(field) {
        return {
          async eachKey(callback) {
            const ordered = sorted()
              .map((id) => rows.get(id))
              .sort((a, b) => (a[field] ?? 0) - (b[field] ?? 0));
            for (const row of ordered) callback(row[field], { primaryKey: row.id });
          },
        };
      },
      where(field) {
        return {
          equals(value) {
            return {
              async primaryKeys() {
                return sorted().filter((id) => rows.get(id)[field] === value);
              },
            };
          },
        };
      },
    };
  }

  async transaction(mode, tables, body) {
    return body();
  }

  async seed(table, row) {
    await this.table(table).put({ ...row, _del: row.deleted === true ? 1 : 0 });
  }

  async seedWire(tables) {
    for (const [table, rows] of Object.entries(tables || {})) {
      for (const wire of rows) {
        const row = {};
        for (const [field, value] of Object.entries(wire)) {
          if (field === 'imageBlobBase64') continue;
          row[field] = value;
        }
        if (typeof wire.imageBlobBase64 === 'string') row.imageBlob = fromBase64(wire.imageBlobBase64);
        await this.seed(table, row);
      }
    }
  }

  async dump() {
    const out = {};
    for (const [name, rows] of this._tables) {
      if (name === 'vaultMeta') continue;
      out[name] = [...rows.keys()].sort().map((id) => {
        const row = rows.get(id);
        const clean = {};
        for (const field of ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv']) {
          if (row[field] !== undefined) clean[field] = row[field];
        }
        if (row.imageBlob) clean.imageBlobBase64 = toBase64(row.imageBlob);
        return clean;
      });
    }
    return out;
  }
}

FakeVaultStore.prototype.getManifest = SweetheartDatabase.prototype.getManifest;

const context = new AsyncLocalStorage();
db.table = (name) => context.getStore().store.table(name);
db.transaction = (mode, tables, body) => context.getStore().store.transaction(mode, tables, body);
db.getManifest = () => context.getStore().store.getManifest();

export function clean(value) {
  return JSON.parse(JSON.stringify(value ?? null));
}

export class Side {
  constructor(name, peerId, key, store) {
    this.name = name;
    this.peerId = peerId;
    this.key = key;
    this.store = store;
    this.manager = new PeerSyncManager();
    this.manager.cryptoKey = key;
    this.manager.myPeerId = peerId;
    this.statuses = [];
    this.events = [];
    this.manager.on('status', (status) => this.statuses.push(clean(status)));
    this.manager.on('data-updated', (payload) => this.events.push({ event: 'data-updated', ...clean(payload) }));
    this.manager.on('config-synced', (payload) => this.events.push({ event: 'config-synced', ...clean(payload) }));
  }

  run(fn) {
    return context.run(this, fn);
  }
}

export class FakeConn {
  constructor(side, remotePeerId, transport) {
    this.side = side;
    this.peer = remotePeerId;
    this.open = false;
    this.handlers = {};
    this.transport = transport;
    this.chunker = new Chunker();
    this.chunks = {};
    this.onClosed = null;
  }

  on(event, fn) {
    (this.handlers[event] ||= []).push(fn);
  }

  emit(event, ...args) {
    for (const fn of [...(this.handlers[event] || [])]) fn(...args);
  }

  send(data) {
    if (!this.open) return;
    const blob = pack(data);
    const frames = blob.byteLength > CHUNKED_MTU ? this.chunker.chunk(blob).map((chunk) => pack(chunk)) : [blob];
    for (const frame of frames) this.transport(new Uint8Array(frame));
  }

  receive(frame) {
    if (!this.open) return;
    const data = unpack(frame);
    const peerData = data && data.__peerData;
    if (peerData) {
      if (peerData.type === 'close') {
        this.close();
        return;
      }
      const entry = this.chunks[peerData] || { data: [], count: 0, total: data.total };
      entry.data[data.n] = new Uint8Array(data.data);
      entry.count++;
      this.chunks[peerData] = entry;
      if (entry.total === entry.count) {
        delete this.chunks[peerData];
        const size = entry.data.reduce((sum, part) => sum + part.byteLength, 0);
        const whole = new Uint8Array(size);
        let offset = 0;
        for (const part of entry.data) {
          whole.set(part, offset);
          offset += part.byteLength;
        }
        this.receive(whole.buffer);
      }
      return;
    }
    this.emit('data', data);
  }

  openNow() {
    this.open = true;
    this.side.run(() => this.emit('open'));
  }

  close() {
    if (!this.open) return;
    this.open = false;
    this.emit('close');
    if (this.onClosed) this.onClosed();
  }
}

export const settle = (ms = 400) => new Promise((resolve) => setTimeout(resolve, ms));

export async function waitFor(predicate, label, tries = 400) {
  for (let i = 0; i < tries; i++) {
    if (predicate()) return;
    await settle(25);
  }
  throw new Error(`timed out waiting for ${label}`);
}
