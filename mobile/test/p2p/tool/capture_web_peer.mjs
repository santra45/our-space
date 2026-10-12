import { AsyncLocalStorage } from 'node:async_hooks';
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..', '..', '..');
const fixtures = join(here, '..', 'fixtures');

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

const crypto = await load('src/services/crypto.js');
const dbModule = await load('src/db/index.js');
const { PeerSyncManager } = await load('src/services/peerSync.js');
const { pack, unpack } = await import('peerjs-js-binarypack');
const peerjs = await import('peerjs/dist/bundler.mjs');

const db = dbModule.default;
const { SweetheartDatabase, EXPORTED_TABLES } = dbModule;
const Chunker = Object.getPrototypeOf(peerjs.util.constructor);
const CHUNKED_MTU = peerjs.util.chunkedMTU;

const toBase64 = (bytes) => Buffer.from(bytes).toString('base64');

function seededBytes(seed, length) {
  const out = new Uint8Array(length);
  let block = createHash('sha256').update(seed).digest();
  let offset = 0;
  while (offset < length) {
    for (let i = 0; i < block.length && offset < length; i++) out[offset++] = block[i];
    block = createHash('sha256').update(block).digest();
  }
  return out;
}

class FakeVaultStore {
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

class Side {
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

function clean(value) {
  return JSON.parse(JSON.stringify(value ?? null));
}

class FakeConn {
  constructor(side, remotePeerId, transcript) {
    this.side = side;
    this.peer = remotePeerId;
    this.open = false;
    this.handlers = {};
    this.transcript = transcript;
    this.chunker = new Chunker();
    this.chunks = {};
    this.remote = null;
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
    for (const frame of frames) {
      const bytes = new Uint8Array(frame);
      this.transcript.push({ from: this.side.name, frame: toBase64(bytes) });
      const remote = this.remote;
      setImmediate(() => remote.side.run(() => remote.receive(bytes.slice().buffer)));
    }
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

  close() {
    if (!this.open) return;
    this.open = false;
    this.transcript.push({ from: this.side.name, close: true });
    this.emit('close');
    const remote = this.remote;
    setImmediate(() => remote.side.run(() => remote.close()));
  }
}

function link(a, b, transcript) {
  const ab = new FakeConn(a, b.peerId, transcript);
  const ba = new FakeConn(b, a.peerId, transcript);
  ab.remote = ba;
  ba.remote = ab;
  return { initiator: ab, responder: ba };
}

const settle = (ms = 400) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitFor(predicate, label, tries = 200) {
  for (let i = 0; i < tries; i++) {
    if (predicate()) return;
    await settle(25);
  }
  throw new Error(`capture timed out waiting for ${label}`);
}

const KEY_BITS = seededBytes('our-space p2p fixture key', 32);
const OTHER_KEY_BITS = seededBytes('our-space p2p other key', 32);
const BASE = 1760000000000;

async function sealed(key, table, fields) {
  return crypto.encryptRecord(fields, key, { table });
}

async function seedSession(key) {
  const a = new FakeVaultStore();
  const b = new FakeVaultStore();
  const photo = seededBytes('pier photo', 40000);
  const rows = {
    letA: await sealed(key, 'letters', { id: 'let-a1', title: 'Only on A', content: 'Hello from A', unlockDate: '2025-12-25', updatedAt: BASE + 100 }),
    letSharedA: await sealed(key, 'letters', { id: 'let-shared', title: 'Newer on A', content: 'v2', unlockDate: '2025-12-25', updatedAt: BASE + 300 }),
    letSharedB: await sealed(key, 'letters', { id: 'let-shared', title: 'Older on B', content: 'v1', unlockDate: '2025-12-25', updatedAt: BASE + 200 }),
    bucketA: await sealed(key, 'bucketList', { id: 'bucket-b1', text: 'Old idea', category: 'travel', completed: false, updatedAt: BASE + 400 }),
    bucketB: await sealed(key, 'bucketList', { id: 'bucket-b1', text: 'New idea', category: 'travel', completed: true, updatedAt: BASE + 500 }),
    tieA: await sealed(key, 'milestones', { id: 'ms-tie', updatedAt: BASE + 600, deleted: true }),
    tieB: await sealed(key, 'milestones', { id: 'ms-tie', title: 'First date', date: '2024-02-14', updatedAt: BASE + 600 }),
    memA: await sealed(key, 'memories', { id: 'mem-photo', date: '2025-06-01', caption: 'Pier', mime: 'image/webp', imageBlob: photo, updatedAt: BASE + 700 }),
    roulette: await sealed(key, 'dateIdeas', { id: 'roulette-state', ideaId: 'idea-1', category: 'cozy', revealed: true, updatedAt: BASE + 800 }),
    burstA: await sealed(key, 'loveBursts', { id: 'burst-device-a', count: 1, lastSentAt: BASE + 900, updatedAt: BASE + 900 }),
    personB: await sealed(key, 'people', { id: 'person-b', name: 'Bee', pronoun: 'she', updatedAt: BASE + 1000 }),
    answerB: await sealed(key, 'dailyAnswers', { id: 'answer-b', ownerId: 'person-b', questionId: 'q1', text: 'Sunsets', updatedAt: BASE + 1100 }),
  };
  await a.seed('letters', rows.letA);
  await a.seed('letters', rows.letSharedA);
  await b.seed('letters', rows.letSharedB);
  await a.seed('bucketList', rows.bucketA);
  await b.seed('bucketList', rows.bucketB);
  await a.seed('milestones', rows.tieA);
  await b.seed('milestones', rows.tieB);
  await a.seed('memories', rows.memA);
  await a.seed('dateIdeas', rows.roulette);
  await b.seed('dateIdeas', rows.roulette);
  await a.seed('loveBursts', rows.burstA);
  await b.seed('people', rows.personB);
  await b.seed('dailyAnswers', rows.answerB);
  return { a, b };
}

async function captureSession() {
  const key = await crypto.importVaultKeyFromBits(KEY_BITS);
  const { a: storeA, b: storeB } = await seedSession(key);
  const startA = await storeA.dump();
  const startB = await storeB.dump();
  const A = new Side('A', 'love-aaaaaaaaaaaaaaaa', key, storeA);
  const B = new Side('B', 'love-bbbbbbbbbbbbbbbb', key, storeB);
  const transcript = [];
  const configA = { coupleNames: 'Ash & Bee', startDate: '2024-02-14', updatedAt: BASE + 50 };
  const configB = { coupleNames: 'Bee & Ash', startDate: '2024-02-13', updatedAt: BASE + 40 };
  A.manager.on('status', (status) => {
    if (status.state === 'authorized') A.run(() => A.manager.syncVaultConfig(configA));
  });
  B.manager.on('status', (status) => {
    if (status.state === 'authorized') B.run(() => B.manager.syncVaultConfig(configB));
  });

  const { initiator, responder } = link(A, B, transcript);
  A.run(() => {
    A.manager.dialingPeerId = B.peerId;
    A.manager._setupConnection(initiator, true);
  });
  B.run(() => B.manager._setupConnection(responder, false));
  responder.open = true;
  initiator.open = true;
  B.run(() => responder.emit('open'));
  A.run(() => initiator.emit('open'));

  await waitFor(
    () =>
      A.statuses.some((s) => s.code === 'sync_complete') &&
      B.statuses.some((s) => s.code === 'sync_complete') &&
      !A.manager.isSyncing &&
      !B.manager.isSyncing,
    'the first sync'
  );
  await settle();
  const marks = { afterSync: transcript.length };

  const burst = await sealed(key, 'loveBursts', { id: 'burst-device-a', count: 2, lastSentAt: BASE + 1200, updatedAt: BASE + 1200 });
  await A.run(async () => {
    await storeA.seed('loveBursts', burst);
    await A.manager.broadcastLiveRecord('loveBursts', burst);
  });
  await waitFor(() => B.events.some((e) => e.event === 'data-updated' && e.single), 'the live burst');
  await settle();
  marks.afterBroadcast = transcript.length;

  await A.run(() => A.manager._heartbeatTick());
  await settle();
  marks.afterPing = transcript.length;

  await A.run(() => A.manager.syncNow());
  await waitFor(() => !A.manager.isSyncing && !B.manager.isSyncing, 'the manual sync');
  await settle();
  marks.afterManualSync = transcript.length;

  A.run(() => A.manager.closeConnection());
  await settle();

  const endA = await storeA.dump();
  const endB = await storeB.dump();
  A.run(() => A.manager.destroy());
  B.run(() => B.manager.destroy());

  return {
    keyBase64: toBase64(KEY_BITS),
    chunkedMtu: CHUNKED_MTU,
    peers: { A: A.peerId, B: B.peerId },
    configs: { A: configA, B: configB },
    start: { A: startA, B: startB },
    end: { A: endA, B: endB },
    marks,
    transcript,
    statuses: { A: A.statuses, B: B.statuses },
    events: { A: A.events, B: B.events },
  };
}

async function captureMismatch() {
  const keyA = await crypto.importVaultKeyFromBits(KEY_BITS);
  const keyB = await crypto.importVaultKeyFromBits(OTHER_KEY_BITS);
  const A = new Side('A', 'love-aaaaaaaaaaaaaaaa', keyA, new FakeVaultStore());
  const B = new Side('B', 'love-bbbbbbbbbbbbbbbb', keyB, new FakeVaultStore());
  const transcript = [];
  const { initiator, responder } = link(A, B, transcript);
  A.run(() => {
    A.manager.dialingPeerId = B.peerId;
    A.manager._setupConnection(initiator, true);
  });
  B.run(() => B.manager._setupConnection(responder, false));
  responder.open = true;
  initiator.open = true;
  B.run(() => responder.emit('open'));
  A.run(() => initiator.emit('open'));
  await waitFor(() => B.statuses.some((s) => s.code === 'passphrase_mismatch'), 'the mismatch');
  await settle();
  A.run(() => A.manager.destroy());
  B.run(() => B.manager.destroy());
  return {
    keyBase64: { A: toBase64(KEY_BITS), B: toBase64(OTHER_KEY_BITS) },
    peers: { A: A.peerId, B: B.peerId },
    transcript,
    statuses: { A: A.statuses, B: B.statuses },
  };
}

function tagged(value) {
  if (value === undefined) return { $undefined: true };
  if (value instanceof ArrayBuffer) return { $bytes: toBase64(new Uint8Array(value)) };
  if (value instanceof Uint8Array) return { $bytes: toBase64(value) };
  if (typeof value === 'number' && !Number.isFinite(value)) return { $number: String(value) };
  if (typeof value === 'number' && Object.is(value, -0)) return { $number: '-0' };
  if (Array.isArray(value)) return value.map(tagged);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = tagged(v);
    return { $map: out };
  }
  return value;
}

function generated(spec) {
  if (spec.$gen === 'repeat') return spec.char.repeat(spec.count);
  if (spec.$gen === 'seq') return Array.from({ length: spec.count }, (_, i) => i % spec.mod);
  if (spec.$gen === 'bytes') return seededBytes(spec.seed, spec.count);
  if (spec.$gen === 'keys') return Object.fromEntries(Array.from({ length: spec.count }, (_, i) => [`k${i}`, i % 2 === 0]));
  throw new Error('unknown generator');
}

function packVectors() {
  const bytes = (n, seed) => seededBytes(seed, n);
  const values = [
    0, 1, 127, 128, 255, 256, 65535, 65536, -1, -32, -33, -128, -129, -32768, -32769,
    2147483647, 2147483648, 4294967295, 4294967296, -2147483648, -2147483649, -4294967296,
    BASE, BASE + 1234, 9007199254740991, -9007199254740991,
    1.5, -2.25, 0.1, 3.14159, 1e300, -1e-300, 123456.789, 1e21, 2 ** 64, 2 ** 63,
    true, false, null, '', 'a', 'SWEETHEART_V2', 'x'.repeat(15), 'y'.repeat(16), 'w'.repeat(300),
    'héllo wörld', '💕 love', '\u0000\u007f\u0080߿ࠀ￿', 'lone \ud800 surrogate',
    [], [1, 2, 3], Array.from({ length: 16 }, (_, i) => i),
    {}, { a: 1 }, Object.fromEntries(Array.from({ length: 16 }, (_, i) => [`k${i}`, i])),
    bytes(0, 'b0'), bytes(15, 'b15'), bytes(16, 'b16'), bytes(300, 'b300'),
    { protocol: 'SWEETHEART_V2', payload: { ciphertext: 'q'.repeat(40), iv: 'AAAAAAAAAAAAAAAA' } },
    { __peerData: 3, n: 1, data: bytes(20, 'chunk').buffer, total: 4 },
    { __peerData: { type: 'close' } },
    { nested: [{ deep: [null, true, 'x', 1.25, -7] }] },
  ];
  const packed = values.map((value) => {
    try {
      const out = new Uint8Array(pack(value));
      return {
        value: tagged(value),
        hex: Buffer.from(out).toString('hex'),
        unpacked: tagged(unpack(out.slice().buffer)),
      };
    } catch {
      return { value: tagged(value), error: true };
    }
  });
  const large = [
    { $gen: 'repeat', char: 'z', count: 70000 },
    { $gen: 'seq', count: 3000, mod: 3 },
    { $gen: 'bytes', seed: 'b70000', count: 70000 },
    { $gen: 'keys', count: 3000 },
  ].map((spec) => {
    const out = new Uint8Array(pack(generated(spec)));
    return {
      spec,
      length: out.byteLength,
      prefix: Buffer.from(out.subarray(0, 16)).toString('hex'),
      sha256: createHash('sha256').update(out).digest('hex'),
    };
  });
  const rawInputs = [
    'ca40490fdb', 'cbc00921fb54442d18', 'cf0000019a2b3c4d5e', 'cfffffffffffffffff', 'd3ffffffffffffffff',
    'd3fffffffe00000000', 'd0ff', 'd1ff00', 'd2ffff0000', 'cc80', 'cdffff', 'ceffffffff', 'c0', 'c1', 'c2', 'c3',
    'd4', 'd5', 'd6', 'd7', 'c4', 'c9', '82a1610101c3', '8201b161', '92c0c1', 'b3e282ac', 'b4f09f9295',
    'd80003616263', 'd900000003646566', 'da0003010203', 'db00000002ffee', 'dc0002c2c3', 'dd00000001c0',
    'de0001a17801', 'df00000001a17902', 'e0', 'ff', '7f', '',
  ];
  const unpacked = rawInputs.map((hex) => {
    let result;
    try {
      result = { value: tagged(unpack(new Uint8Array(Buffer.from(hex, 'hex')).buffer)) };
    } catch (err) {
      result = { error: true };
    }
    return { hex, ...result };
  });
  return { packed, large, unpacked };
}

function chunkVectors() {
  const chunker = new Chunker();
  const blob = new Uint8Array(pack({ protocol: 'SWEETHEART_V2', payload: { ciphertext: 'c'.repeat(40000), iv: 'i'.repeat(16) } }));
  const chunks = chunker.chunk(blob.buffer);
  return {
    mtu: CHUNKED_MTU,
    message: toBase64(blob),
    frames: chunks.map((chunk) => toBase64(new Uint8Array(pack(chunk)))),
  };
}

mkdirSync(fixtures, { recursive: true });
const vectors = { ...packVectors(), chunking: chunkVectors() };
writeFileSync(join(fixtures, 'binary_pack_vectors.json'), JSON.stringify(vectors));
writeFileSync(join(fixtures, 'web_peer_session.json'), JSON.stringify(await captureSession(), null, 1));
writeFileSync(join(fixtures, 'web_peer_mismatch.json'), JSON.stringify(await captureMismatch(), null, 1));
console.log('wrote', fixtures);
process.exit(0);
