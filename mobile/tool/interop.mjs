import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const mobile = join(here, '..');
const FIXTURE = join(mobile, 'test', 'fixtures', 'web_sealed.json');
const DART_SEALED = join(mobile, 'build', 'interop', 'dart_sealed.json');

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
const mailbox = await load('src/services/mailbox.js');
const people = await load('src/services/people.js');
const dq = await load('src/services/dailyQuestion.js');
const bank = await load('src/data/dailyQuestions.js');
const bursts = await load('src/services/loveBursts.js');
const invite = await load('src/utils/invite.js');
const limits = await load('src/services/limits.js');
const dates = await load('src/utils/dateHelpers.js');
const worker = (await load('worker/src/index.js')).default;

const db = dbModule.default;
const { SweetheartDatabase, EXPORTED_TABLES, SYNCED_TABLES } = dbModule;

class FakeVaultStore {
  constructor() {
    this._tables = new Map();
    for (const name of EXPORTED_TABLES) this._tables.set(name, new Map());
  }

  table(name) {
    const rows = this._tables.get(name);
    if (!rows) throw new Error(`FakeVaultStore: unknown table "${name}"`);
    return {
      async get(id) {
        return rows.get(id);
      },
      async put(row) {
        rows.set(row.id, row);
      },
      async toArray() {
        return Array.from(rows.values());
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
            return Array.from(rows.keys());
          },
        };
      },
      orderBy(field) {
        return {
          async eachKey(callback) {
            for (const row of rows.values()) callback(row[field], { primaryKey: row.id });
          },
        };
      },
      where(field) {
        return {
          equals(value) {
            return {
              async primaryKeys() {
                return Array.from(rows.values())
                  .filter((row) => row[field] === value)
                  .map((row) => row.id);
              },
            };
          },
        };
      },
    };
  }

  get vaultMeta() {
    return this.table('vaultMeta');
  }

  async transaction(mode, tables, body) {
    return body();
  }
}

for (const method of [
  'putEncrypted',
  'putEncryptedMany',
  'softDelete',
  '_withDelIndex',
  'getDecrypted',
  'listDecrypted',
  'getManifest',
  'planBackupMerge',
  'applyBackupMerge',
  'exportRawDataForBackup',
  'readVaultIdentity',
]) {
  if (typeof SweetheartDatabase.prototype[method] !== 'function') {
    throw new Error(`interop harness is stale: SweetheartDatabase has no ${method}()`);
  }
  FakeVaultStore.prototype[method] = SweetheartDatabase.prototype[method];
}

function toJsonValue(value) {
  if (value instanceof Uint8Array) return { $bytes: crypto.bufferToBase64(value) };
  if (value instanceof ArrayBuffer) return { $bytes: crypto.bufferToBase64(new Uint8Array(value)) };
  if (Array.isArray(value)) return value.map(toJsonValue);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (v === undefined) continue;
      out[k] = toJsonValue(v);
    }
    return out;
  }
  return value;
}

function fromJsonValue(value) {
  if (Array.isArray(value)) return value.map(fromJsonValue);
  if (value && typeof value === 'object') {
    const keys = Object.keys(value);
    if (keys.length === 1 && keys[0] === '$bytes') return crypto.base64ToBuffer(value.$bytes);
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = fromJsonValue(v);
    return out;
  }
  return value;
}

function rowToWire(row) {
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    if (k === 'imageBlob' && v) {
      out.imageBlobBase64 = crypto.bufferToBase64(v);
      continue;
    }
    out[k] = toJsonValue(v);
  }
  return out;
}

function rowFromWire(wire) {
  const row = fromJsonValue(wire);
  if (typeof row.imageBlobBase64 === 'string') {
    row.imageBlob = crypto.base64ToBuffer(row.imageBlobBase64);
    delete row.imageBlobBase64;
  }
  return row;
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonical(value[key]);
    return out;
  }
  return value;
}

const same = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));

function makeKv() {
  const kv = new Map();
  return {
    kv,
    binding: {
      async get(k) {
        return kv.has(k) ? kv.get(k) : null;
      },
      async put(k, v) {
        kv.set(k, v);
      },
    },
  };
}

const MAILBOX_ORIGIN = 'https://sameskytonight.vercel.app';
const MAILBOX_CONFIG = { url: 'https://mailbox.interop.test', token: 'interop-token-0123456789' };

function routeFetchToWorker(binding) {
  const env = { MAILBOX: binding, MAILBOX_TOKEN: MAILBOX_CONFIG.token, ALLOWED_ORIGIN: MAILBOX_ORIGIN };
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    const request = new Request(url, {
      method: options.method || 'GET',
      headers: { ...(options.headers || {}), Origin: MAILBOX_ORIGIN },
      body: options.body,
    });
    return worker.fetch(request, env);
  };
  return () => {
    globalThis.fetch = realFetch;
  };
}

function kvDump(kv) {
  const out = {};
  for (const [k, v] of kv.entries()) {
    if (typeof v === 'string') out[k] = v;
    else out[k] = new TextDecoder().decode(v instanceof ArrayBuffer ? new Uint8Array(v) : v);
  }
  return out;
}

async function collectInto(store, cryptoKey, partnerId) {
  const realManifest = db.getManifest;
  db.getManifest = () => FakeVaultStore.prototype.getManifest.call(store);
  try {
    return await mailbox.collect({ cryptoKey, partnerId, overrides: MAILBOX_CONFIG, store });
  } finally {
    db.getManifest = realManifest;
  }
}

const PASSPHRASE = 'our space interop passphrase 2026';
const SALT = crypto.bufferToBase64(Uint8Array.from({ length: 16 }, (_, i) => (i * 37 + 11) & 0xff));
const ITERATIONS = crypto.PBKDF2_ITERATIONS_CURRENT;
const BACKUP_PASSPHRASE = 'a different passphrase for the backup file';
const T0 = 1760000000000;
const WEB_DEVICE = 'webdevice-0001';
const PHOTO = Uint8Array.from({ length: 3000 }, (_, i) => (i * 31 + 7) & 0xff);

async function generate() {
  const bits = new Uint8Array(await crypto.deriveVaultKeyBits(PASSPHRASE, SALT, { iterations: ITERATIONS }));
  const key = await crypto.importVaultKeyFromBits(bits);
  const config = { coupleNames: 'Sam & Alex ✨', startDate: '2021-06-14', createdAt: T0 - 5000, updatedAt: T0 - 4000 };
  const { canary, canaryIv } = await crypto.createCanary(key, config);
  const vaultMeta = { id: 'config', salt: SALT, canary, canaryIv, kdfIterations: ITERATIONS, updatedAt: config.updatedAt };

  const [slotA, slotB] = await people.derivePersonSlots(key);
  const web = new FakeVaultStore();
  let tick = T0;
  const stamp = () => (tick += 1000);

  const photoBlob = await crypto.encryptBlob(PHOTO, key);
  await web.putEncrypted(
    'memories',
    { id: 'mem-interop-1', date: '2026-02-14', caption: 'Our first trip ✨', mime: 'image/webp', imageBlob: photoBlob, updatedAt: stamp(), deleted: false },
    key
  );
  await web.putEncrypted(
    'memories',
    { id: 'mem-interop-2', date: '2025-12-24', caption: 'Precious moment 💕', mime: 'image/jpeg', imageBlob: await crypto.encryptBlob(PHOTO.slice(0, 100), key), updatedAt: stamp(), deleted: false },
    key
  );
  await web.putEncrypted('milestones', { id: 'ms-interop-1', title: 'First date', date: '2021-06-14', updatedAt: stamp(), deleted: false }, key);
  await web.putEncrypted('milestones', { id: 'ms-interop-gone', title: 'Will be deleted', date: '2022-01-01', updatedAt: stamp(), deleted: false }, key);
  const goneLive = rowToWire(await web.table('milestones').get('ms-interop-gone'));
  await web.softDelete('milestones', 'ms-interop-gone', key);
  await web.putEncrypted('dateIdeas', { id: 'roulette-current', ideaId: 'd3', category: 'food', revealed: true, updatedAt: stamp(), deleted: false }, key);
  await web.putEncrypted(
    'letters',
    { id: 'let-interop-open', title: 'Read me now', unlockDate: null, isOpened: false, createdAt: T0 - 100, updatedAt: stamp(), deleted: false, content: 'I miss you every single day.\nSee you soon 💌' },
    key
  );
  await web.putEncrypted(
    'letters',
    {
      id: 'let-interop-past',
      title: 'A letter from last year',
      unlockDate: '2020-01-01',
      isOpened: true,
      openedAt: T0 - 50,
      createdAt: T0 - 200,
      updatedAt: stamp(),
      deleted: false,
      sealedContent: await crypto.sealTimeLocked('This one was sealed until 2020.', '2020-01-01', key, { context: 'let-interop-past' }),
    },
    key
  );
  await web.putEncrypted(
    'letters',
    {
      id: 'let-interop-future',
      title: 'Open on our anniversary',
      unlockDate: '2099-12-31',
      isOpened: false,
      createdAt: T0 - 300,
      updatedAt: stamp(),
      deleted: false,
      sealedContent: await crypto.sealTimeLocked('Not yet, my love.', '2099-12-31', key, { context: 'let-interop-future' }),
    },
    key
  );
  await web.putEncrypted(
    'bucketList',
    { id: 'bkt-interop-1', text: 'Fly to Japan during cherry blossom season', category: 'Travel', completed: true, completedAt: T0 - 10, createdAt: 3, updatedAt: stamp(), deleted: false },
    key
  );
  await web.putEncrypted('loveBursts', { id: `burst-${WEB_DEVICE}`, count: 7, lastSentAt: T0 - 20, updatedAt: stamp() }, key);
  await web.putEncrypted(
    'dailyAnswers',
    {
      id: dq.answerRecordId('2026-10', slotA),
      ownerId: slotA,
      month: '2026-10',
      answers: {
        '2026-10-08': { questionId: 'b1-001', text: 'Way too much about volcanoes.', answeredAt: T0 - 30 },
        '2026-10-09': { questionId: 'b1-002', text: 'Kind, stubborn, glowing.', answeredAt: T0 - 25 },
      },
      updatedAt: stamp(),
    },
    key
  );
  await people.savePerson({ cryptoKey: key, store: web, personId: slotA, name: 'Sam', pronoun: 'he', addDeviceId: WEB_DEVICE, timestamp: stamp });
  await people.savePerson({ cryptoKey: key, store: web, personId: slotB, name: 'Alex', pronoun: 'she', timestamp: stamp });
  await web.putEncrypted('people', { id: people.presenceRecordId(slotA), personId: slotA, lastActiveAt: T0 - 15, updatedAt: stamp() }, key);

  const rows = {};
  for (const table of SYNCED_TABLES) {
    rows[table] = [];
    for (const row of await web.table(table).toArray()) {
      const plain = await crypto.decryptRecord(row, key, { table });
      rows[table].push({ row: rowToWire(row), expected: toJsonValue(plain) });
    }
  }

  const otherKey = await crypto.deriveKeyFromPassphrase('someone else entirely, not us', crypto.generateSalt(), { iterations: 1000 });
  const milestoneRow = (await web.table('milestones').get('ms-interop-1'));
  const memoryRow = await web.table('memories').get('mem-interop-1');
  const letterRow = await web.table('letters').get('let-interop-open');
  const legacy = await crypto.encryptJSON({ id: 'mem-legacy', caption: 'from before bindings', updatedAt: 5, deleted: false }, key);
  const tamperCases = [
    { name: 'header updatedAt edited', table: 'milestones', row: { ...milestoneRow, updatedAt: milestoneRow.updatedAt + 1 } },
    { name: 'header id edited', table: 'milestones', row: { ...milestoneRow, id: 'ms-someone-else' } },
    { name: 'header deleted flipped', table: 'milestones', row: { ...milestoneRow, deleted: true } },
    { name: 'sealed for another table', table: 'milestones', row: letterRow },
    { name: 'photo bytes swapped', table: 'memories', row: { ...memoryRow, imageBlob: (() => { const b = new Uint8Array(memoryRow.imageBlob); b[40] ^= 1; return b; })() } },
    { name: 'photo removed', table: 'memories', row: (() => { const r = { ...memoryRow }; delete r.imageBlob; return r; })() },
    { name: 'legacy row without bindings', table: 'memories', row: { id: 'mem-legacy', updatedAt: 5, deleted: false, v: 2, ciphertext: legacy.ciphertext, iv: legacy.iv, imageBlob: PHOTO.slice(0, 16) } },
    { name: 'sealed with another key', table: 'milestones', row: await crypto.encryptRecord({ id: 'ms-forged', updatedAt: 5 }, otherKey, { table: 'milestones' }) },
    { name: 'ciphertext bit flipped', table: 'milestones', row: (() => { const b = crypto.base64ToBuffer(milestoneRow.ciphertext); b[3] ^= 1; return { ...milestoneRow, ciphertext: crypto.bufferToBase64(b) }; })() },
    { name: 'not an envelope', table: 'milestones', row: { id: 'ms-plain', updatedAt: 1, deleted: false, title: 'plaintext' } },
  ];
  const tampered = [];
  for (const c of tamperCases) {
    let expected;
    try {
      expected = toJsonValue(await crypto.decryptRecord(c.row, key, { table: c.table }));
    } catch {
      expected = 'throws';
    }
    tampered.push({ name: c.name, table: c.table, row: rowToWire(c.row), expected });
  }

  const manifestPlain = await web.getManifest();
  const manifestSealed = await crypto.encryptJSON(manifestPlain, key);

  const timeLocks = [];
  for (const [plain, unlockDate, context] of [
    ['A small secret for later.', '2020-05-05', 'ctx-1'],
    ['No context at all.', '2019-02-28', ''],
    ['An ISO boundary in UTC.', '2021-01-01T10:00:00Z', 'let-iso'],
    ['Still locked.', '2099-01-01', 'let-locked'],
  ]) {
    const sealed = await crypto.sealTimeLocked(plain, unlockDate, key, { context });
    timeLocks.push({ plain, unlockDate, context, sealed, boundaryLocal: crypto.getTimeLockBoundary(unlockDate) });
  }

  const texts = [];
  for (const [plain, aad] of [
    ['plain text, no aad', undefined],
    ['text bound to a string ✨', 'our-space/some-binding'],
    ['', undefined],
  ]) {
    const sealed = await crypto.encryptText(plain, key, aad);
    texts.push({ plain, aad: aad === undefined ? null : aad, ...sealed });
  }

  const blob = { plain: crypto.bufferToBase64(PHOTO), packed: crypto.bufferToBase64(await crypto.encryptBlob(PHOTO, key)) };

  const normalizeInputs = [
    'plain ascii passphrase here',
    '  padded with spaces passphrase  ',
    'ｆｕｌｌｗｉｄｔｈ ｐａｓｓｐｈｒａｓｅ ｈｅｒｅ',
    'é combining accents in my passphrase',
    'ligature ﬁ and ① circled passphrase',
    ' nbsp and ideographic　space passphrase　',
    '\u0085next line is not trimmed by js\u0085',
    '﻿tab\tand bom passphrase here\t',
  ];
  const normalizeVectors = normalizeInputs.map((input) => ({ input, output: crypto.normalizePassphrase(input) }));

  const kdfVectors = [];
  for (const [passphrase, salt, iterations, normalize] of [
    ['ｆｕｌｌｗｉｄｔｈ ｐａｓｓｐｈｒａｓｅ ｈｅｒｅ', SALT, 1000, true],
    ['ｆｕｌｌｗｉｄｔｈ ｐａｓｓｐｈｒａｓｅ ｈｅｒｅ', SALT, 1000, false],
    ['  a passphrase with outer spaces  ', 'AAECAwQFBgcICQoLDA0ODw', 1, true],
    ['short-salted passphrase for test', '-_-_-_-_-_-_-_-_-_-_-w', 2000, true],
  ]) {
    const out = new Uint8Array(await crypto.deriveVaultKeyBits(passphrase, salt, { iterations, normalize }));
    kdfVectors.push({ passphrase, salt, iterations, normalize, bits: crypto.bufferToBase64(out) });
  }

  const rawPassphrase = '  ｒａｗ passphrase saved before normalising  ';
  const rawKey = await crypto.deriveKeyFromPassphrase(rawPassphrase, SALT, { iterations: 1000, normalize: false });
  const rawCanary = await crypto.createCanary(rawKey, { coupleNames: 'Raw', startDate: '2020-01-01', createdAt: 1, updatedAt: 2 });
  const rawVault = { passphrase: rawPassphrase, salt: SALT, kdfIterations: 1000, ...rawCanary };

  const base64Inputs = ['AAEC', 'AAE', 'AA', 'A', '-_8', 'AB==', 'AQ==', 'AQ=', 'not base64!!', '', 'AAECAwQFBgcICQoLDA0ODw==', 'AAECAwQFBgcICQoLDA0ODw', 'AAECAwQFBgcICQoLDA0ODxA='];
  const base64Vectors = base64Inputs.map((input) => {
    let bytes = null;
    try {
      bytes = crypto.bufferToBase64(crypto.base64ToBuffer(input));
    } catch {
      bytes = null;
    }
    return { input, valid: crypto.isValidBase64(input), validSalt: crypto.isValidSalt(input), bytes };
  });

  const recordKeyIds = ['letter-apart-1', 'ans-2026-09-a/b+c=d', 'ñ✨ unicode id', 'x', 'person-0123456789abcdef01234567'];
  const recordKeys = recordKeyIds.map((id) => ({ id, key: mailbox.recordKey(id) }));

  const order = await dq.buildQuestionOrder(key);
  const whens = [0, 86399999, 86400000, T0, 1767225600000, -86400001, 1790000000000];
  const questionForDay = [];
  for (const when of whens) {
    const q = await dq.getQuestionForDay(key, when);
    questionForDay.push({ when, id: q.question.id, day: q.day, index: q.index, dayIndex: dq.dayIndex(when) });
  }

  const peerId = 'love-0123456789abcdef';
  const builds = [
    { peerId, salt: SALT, options: { baseUrl: 'https://sameskytonight.vercel.app/', startDate: '2021-06-14', coupleNames: 'Sam & Alex ✨' } },
    { peerId, salt: SALT, options: { baseUrl: 'https://sameskytonight.vercel.app/', startDate: '2021-06-14', coupleNames: 'Sam + Alex = us/2', canary, canaryIv } },
    { peerId, salt: SALT, options: 'https://example.test/app' },
    { peerId, salt: null, options: { baseUrl: 'https://x.test/' } },
  ];
  const built = builds.map((b) => {
    const url = invite.buildInviteUrl(b.peerId, b.salt, b.options);
    return { ...b, url, parsed: invite.parseInvite(url) };
  });
  const parseInputs = [
    built[0].url,
    built[1].url,
    `https://sameskytonight.vercel.app/?x=1#connect=${peerId}&salt=${encodeURIComponent(SALT)}&start=2021-02-30&names=+Spaced+Names+`,
    `connect=${peerId}&salt=${SALT}`,
    `?connect=${peerId}&civ=AAAA&canary=AAAA`,
    `${peerId}.${SALT}`,
    `short.${SALT}`,
    peerId,
    '   love-trimmed-id   ',
    'http://not.a.peer/id',
    'bad id with spaces',
    '',
    '#connect=love-hash-only&salt=AAECAwQFBgcICQoLDA0ODw&start=2026-13-01',
    '#salt=AAECAwQFBgcICQoLDA0ODw',
    `https://sameskytonight.vercel.app/#connect=${peerId}&names=${'n'.repeat(130)}&salt=bad`,
  ];
  const parsed = parseInputs.map((input) => ({ input, result: invite.parseInvite(input) }));

  const dayVectors = whens.map((when) => ({ when, dayKey: dq.dayKey(when), monthKey: dq.monthKey(dq.dayKey(when)), dayIndex: dq.dayIndex(when) }));

  const answersStore = new FakeVaultStore();
  const answerRows = [
    { id: dq.answerRecordId('2026-10', slotA), ownerId: slotA, month: '2026-10', answers: { '2026-10-08': { questionId: 'b1-001', text: 'mine one', answeredAt: 10 }, '2026-10-09': { questionId: 'b1-002', text: 'mine two', answeredAt: 30 } }, updatedAt: 1 },
    { id: dq.answerRecordId('2026-10', 'old-device-tag'), ownerId: 'old-device-tag', month: '2026-10', answers: { '2026-10-09': { questionId: 'b1-002', text: 'mine from old device', answeredAt: 40 }, '2026-10-07': { questionId: 'b1-003', text: 'older', answeredAt: 5 } }, updatedAt: 2 },
    { id: dq.answerRecordId('2026-10', slotB), ownerId: slotB, month: '2026-10', answers: { '2026-10-09': { questionId: 'b1-002', text: 'theirs two', answeredAt: 35 }, '2026-10-06': { questionId: 'b1-004', text: 'theirs only', answeredAt: 1 }, '2026-10-05': { text: '' } }, updatedAt: 3 },
    { id: 'ans-2026-10-mismatch', ownerId: slotB, month: '2026-10', answers: { '2026-10-04': { questionId: 'b1-005', text: 'wrong id', answeredAt: 1 } }, updatedAt: 4 },
  ];
  for (const row of answerRows) await answersStore.putEncrypted('dailyAnswers', row, key);
  const ownerIds = [slotA, 'old-device-tag'];
  const dailyDomain = {
    rows: answerRows,
    ownerId: slotA,
    ownerIds,
    readDay: [],
    archive: toJsonValue(await dq.listArchive({ cryptoKey: key, ownerId: slotA, ownerIds, store: answersStore })),
    answered: toJsonValue(await dq.listAnswered({ cryptoKey: key, ownerId: slotA, ownerIds, store: answersStore })),
    theirArchive: toJsonValue(await dq.listArchive({ cryptoKey: key, ownerId: slotB, store: answersStore, limit: 2 })),
  };
  for (const day of ['2026-10-09', '2026-10-08', '2026-10-06', '2026-10-01']) {
    const when = Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)), 15);
    dailyDomain.readDay.push({ when, result: toJsonValue(await dq.readDay({ cryptoKey: key, ownerId: slotA, ownerIds, store: answersStore, when })) });
  }
  const swapPlan = await dq.planAnswerSwap({ cryptoKey: key, store: answersStore, personA: slotA, personB: slotB, since: 20, timestamp: async () => 777 });
  dailyDomain.swap = { since: 20, rows: swapPlan.rows };

  const identityCases = [];
  const peopleStore = new FakeVaultStore();
  await peopleStore.putEncrypted('people', { id: people.personRecordId(slotA), personId: slotA, name: '  Sam   the\tman ', pronoun: 'he', deviceIds: ['dev-aaaaaaaa', 'bad tag', 'dev-aaaaaaaa', 'dev-bbbbbbbb'], createdAt: 100, updatedAt: 1 }, key);
  await peopleStore.putEncrypted('people', { id: people.personRecordId(slotB), personId: slotB, name: 'Alex', pronoun: 'xe', deviceIds: ['dev-cccccccc'], createdAt: 50, lastActiveAt: 5, updatedAt: 2 }, key);
  await peopleStore.putEncrypted('people', { id: people.presenceRecordId(slotB), personId: slotB, lastActiveAt: 999, updatedAt: 3 }, key);
  await peopleStore.putEncrypted('people', { id: 'person-mismatch', personId: slotA, name: 'Imposter', updatedAt: 4 }, key);
  for (const [deviceId, hint] of [
    ['dev-aaaaaaaa', null],
    ['dev-cccccccc', null],
    ['dev-unknown1', null],
    ['dev-unknown1', slotB],
    ['dev-cccccccc', slotA],
    ['dev-aaaaaaaa', 'not-a-person-tag'],
  ]) {
    if (hint) localStorage.setItem('sweetheart_person_id_v1', hint);
    else localStorage.removeItem('sweetheart_person_id_v1');
    people.clearLocalPersonId();
    if (hint) localStorage.setItem('sweetheart_person_id_v1', hint);
    const result = await people.resolveIdentity({ cryptoKey: key, store: peopleStore, deviceId });
    identityCases.push({
      deviceId,
      hint,
      status: result.status,
      me: result.me ? result.me.personId : null,
      partner: result.partner ? result.partner.personId : null,
      hintAfter: localStorage.getItem('sweetheart_person_id_v1'),
    });
  }
  people.clearLocalPersonId();
  const peopleList = toJsonValue(await people.listPeople({ cryptoKey: key, store: peopleStore }));

  const nameVectors = ['  Sam  ', 'Ale\n\nx', 'x'.repeat(50), '   ', 42, 'Chris', 'JAMES', `${'a'.repeat(39)}  b`];
  const sanitizeNames = nameVectors.map((input) => ({ input, output: people.sanitizeName(input), possessive: people.possessiveOf({ name: input }) }));

  const burstVectors = [];
  for (const [total, connected, name] of [[0, false, 'Sam'], [1, false, 'Sam'], [2, true, '  Alex  '], [150, false, ''], [99, true, null], [100, false, 'your partner']]) {
    burstVectors.push({ total, connected, name, text: bursts.describeBursts(total, connected, name) });
  }

  const dateVectors = [];
  for (const [kind, input] of [
    ['formatDatePretty', '2026-02-14'],
    ['formatDatePretty', '2021-06-04'],
    ['formatDatePretty', ''],
    ['formatLastSeen', T0 - 30 * 1000],
    ['formatLastSeen', T0 - 5 * 60 * 1000],
    ['formatLastSeen', T0 - 3 * 3600 * 1000],
    ['formatLastSeen', T0 - 30 * 3600 * 1000],
    ['formatLastSeen', T0 - 3 * 86400 * 1000],
    ['formatLastConnected', T0 - 59 * 1000],
    ['formatLastConnected', T0 - 6 * 86400 * 1000 - 1],
  ]) {
    let output;
    if (kind === 'formatDatePretty') output = dates.formatDatePretty(input);
    else output = dates[kind](input, T0);
    dateVectors.push({ kind, input, output });
  }

  const backupSource = new FakeVaultStore();
  await backupSource.vaultMeta.put(vaultMeta);
  for (const table of SYNCED_TABLES) {
    for (const row of await web.table(table).toArray()) await backupSource.table(table).put({ ...row });
  }
  const backupContainer = await crypto.createEncryptedBackup(await backupSource.exportRawDataForBackup(), BACKUP_PASSPHRASE);

  const { kv, binding } = makeKv();
  const restore = routeFetchToWorker(binding);
  let published;
  try {
    published = await mailbox.publish({ cryptoKey: key, ownerId: slotA, overrides: MAILBOX_CONFIG, store: web });
  } finally {
    restore();
  }
  if (!published.ok) throw new Error(`web publish failed: ${JSON.stringify(published)}`);
  const liveIds = {};
  for (const table of SYNCED_TABLES) {
    liveIds[table] = (await web.table(table).toArray()).filter((row) => row.deleted !== true).map((row) => row.id).sort();
  }

  const fixture = {
    generatedBy: 'mobile/tool/interop.mjs',
    passphrase: PASSPHRASE,
    salt: SALT,
    kdfIterations: ITERATIONS,
    keyBits: crypto.bufferToBase64(bits),
    vaultMeta,
    canaryConfig: config,
    constants: {
      recordSchemaVersion: crypto.RECORD_SCHEMA_VERSION,
      minPassphraseLength: crypto.MIN_PASSPHRASE_LENGTH,
      pbkdf2Iterations: crypto.PBKDF2_ITERATIONS_CURRENT,
      maxImageBlobBytes: limits.MAX_IMAGE_BLOB_BYTES,
      maxSingleRecordBytes: limits.MAX_SINGLE_RECORD_BYTES,
      maxBatchPayloadBytes: limits.MAX_BATCH_PAYLOAD_BYTES,
      maxObjectBytes: mailbox.MAX_OBJECT_BYTES,
      syncedTables: SYNCED_TABLES,
      exportedTables: EXPORTED_TABLES,
    },
    derived: {
      mailboxId: await mailbox.deriveMailboxId(key),
      personSlots: [slotA, slotB],
      questionOrder: order.map((q) => q.id),
      questionForDay,
      recordKeys,
    },
    questions: bank.ALL_QUESTIONS.map((q) => ({ id: q.id, tone: q.tone, text: q.text })),
    rows,
    tampered,
    manifest: { plain: manifestPlain, sealed: manifestSealed },
    blob,
    timeLocks,
    texts,
    normalizeVectors,
    kdfVectors,
    rawVault,
    base64Vectors,
    invites: { built, parsed },
    dayVectors,
    dailyDomain: toJsonValue(dailyDomain),
    identity: { cases: identityCases, people: peopleList, slots: [slotA, slotB] },
    sanitizeNames,
    burstVectors,
    dateVectors,
    backup: { passphrase: BACKUP_PASSPHRASE, container: backupContainer },
    mailbox: {
      config: MAILBOX_CONFIG,
      origin: MAILBOX_ORIGIN,
      ownerId: slotA,
      published,
      kv: kvDump(kv),
      liveIds,
      tombstones: [{ table: 'milestones', id: 'ms-interop-gone', liveRow: goneLive }],
    },
  };

  mkdirSync(dirname(FIXTURE), { recursive: true });
  writeFileSync(FIXTURE, JSON.stringify(fixture, null, 2));
  console.log(`wrote ${FIXTURE}`);
  console.log(
    `  ${Object.values(rows).reduce((n, list) => n + list.length, 0)} sealed rows across ${SYNCED_TABLES.length} tables, ${tampered.length} tamper cases, ${timeLocks.length} time locks, ${parsed.length} invite inputs, ${Object.keys(fixture.mailbox.kv).length} mailbox objects`
  );
}

async function verify() {
  if (!existsSync(DART_SEALED)) {
    console.error(`missing ${DART_SEALED} — run "flutter test" first`);
    process.exit(1);
  }
  const dart = JSON.parse(readFileSync(DART_SEALED, 'utf8'));
  const failures = [];
  let passed = 0;
  const check = (label, ok, detail) => {
    if (ok) {
      passed++;
      console.log(`  ok   ${label}`);
    } else {
      failures.push(label);
      console.log(`  FAIL ${label}${detail ? `\n       ${detail}` : ''}`);
    }
  };

  console.log('== Web opens what Dart sealed ==');

  const meta = dart.vaultMeta;
  const bits = new Uint8Array(await crypto.deriveVaultKeyBits(dart.passphrase, meta.salt, { iterations: meta.kdfIterations }));
  check('web derives the same 256-bit key from the passphrase and Dart salt', crypto.bufferToBase64(bits) === dart.keyBits);
  const key = await crypto.importVaultKeyFromBits(bits);
  const canary = await crypto.readCanary(key, meta);
  check('web reads the canary Dart sealed', canary !== null && canary.token === crypto.VAULT_CANARY_TOKEN);
  check('and the couple config inside it', canary && same({ coupleNames: canary.coupleNames, startDate: canary.startDate }, dart.expectedConfig));
  check('web unlock flow accepts the Dart vault', await crypto.verifyPassphraseAgainstMeta(dart.passphrase, meta));
  check('and refuses a wrong passphrase', !(await crypto.verifyPassphraseAgainstMeta(`${dart.passphrase}x`, meta)));

  check('mailbox id matches', (await mailbox.deriveMailboxId(key)) === dart.derived.mailboxId);
  check('person slots match', same(await people.derivePersonSlots(key), dart.derived.personSlots));
  check('daily question order matches', same((await dq.buildQuestionOrder(key)).map((q) => q.id), dart.derived.questionOrder));
  for (const entry of dart.derived.recordKeys) {
    check(`record key for ${JSON.stringify(entry.id)}`, mailbox.recordKey(entry.id) === entry.key);
  }

  let rowCount = 0;
  const fresh = new FakeVaultStore();
  const importTables = {};
  for (const [table, list] of Object.entries(dart.rows)) {
    importTables[table] = [];
    for (const { row: wire, expected } of list) {
      rowCount++;
      const row = rowFromWire(wire);
      let plain;
      try {
        plain = await crypto.decryptRecord(row, key, { table });
      } catch (err) {
        check(`${table}/${wire.id} opens`, false, err && err.message);
        continue;
      }
      const flags = ['_headerTampered', '_binaryTampered', '_binaryUnverified', '_tableTampered', '_tableUnverified'];
      check(`${table}/${wire.id} opens with every integrity flag clear`, flags.every((f) => plain[f] === false), JSON.stringify(flags.map((f) => [f, plain[f]])));
      check(`${table}/${wire.id} plaintext matches`, same(toJsonValue(plain), expected), `web=${JSON.stringify(canonical(toJsonValue(plain)))}\n       dart=${JSON.stringify(canonical(expected))}`);
      check(`${table}/${wire.id} wire shape is the web shape`, same(Object.keys(wire).filter((k) => k !== '_del').sort(), [...['ciphertext', 'deleted', 'id', 'iv', 'updatedAt', 'v'], ...(wire.imageBlobBase64 ? ['imageBlobBase64'] : [])].sort()));
      importTables[table].push(wire);
    }
  }
  check(`Dart sealed a row for every table (${rowCount} rows)`, SYNCED_TABLES.every((t) => (dart.rows[t] || []).length > 0));
  const plan = await fresh.planBackupMerge(importTables, key);
  const tombstones = Object.values(dart.rows).flat().filter(({ row }) => row.deleted === true).length;
  check('web merge accepts every Dart row as authentic', plan.totals.tampered === 0 && plan.totals.undecryptable === 0 && plan.totals.unauthenticated === 0, JSON.stringify(plan.totals));
  check('and adds all live ones', plan.totals.added === rowCount - tombstones, `${plan.totals.added} of ${rowCount - tombstones}`);

  for (const [table, list] of Object.entries(dart.tampered || {})) {
    for (const { name, row: wire, expected } of list) {
      let outcome;
      try {
        const plain = await crypto.decryptRecord(rowFromWire(wire), key, { table });
        outcome = { _headerTampered: plain._headerTampered, _tableTampered: plain._tableTampered, _binaryTampered: plain._binaryTampered };
      } catch {
        outcome = 'throws';
      }
      check(`Dart tamper case "${name}" is caught the same way by the web`, same(outcome, expected), JSON.stringify(outcome));
    }
  }

  const manifest = await crypto.decryptJSON(dart.manifest.sealed.ciphertext, dart.manifest.sealed.iv, key);
  check('web opens the Dart manifest', same(manifest, dart.manifest.plain));

  const blobPlain = await crypto.decryptBlob(crypto.base64ToBuffer(dart.blob.packed), key);
  check('web opens the Dart photo blob', crypto.bufferToBase64(new Uint8Array(await blobPlain.arrayBuffer())) === dart.blob.plain);

  for (const lock of dart.timeLocks) {
    try {
      const plain = await crypto.unsealTimeLocked(lock.sealed, key, { context: lock.context });
      check(`web unseals Dart time lock "${lock.context}"`, plain === lock.plain);
    } catch (err) {
      check(`web unseals Dart time lock "${lock.context}"`, lock.locked === true && err instanceof crypto.TimeLockedError, err && err.message);
    }
  }

  for (const text of dart.texts) {
    const plain = await crypto.decryptText(text.ciphertext, text.iv, key, text.aad === null ? undefined : text.aad);
    check(`web opens Dart text ${JSON.stringify(text.plain)}`, plain === text.plain);
  }

  for (const entry of dart.invites) {
    const parsed = invite.parseInvite(entry.url);
    check(`web parses Dart invite ${entry.url.slice(0, 60)}...`, same(parsed, entry.expected), JSON.stringify(parsed));
    if (entry.args) {
      const rebuilt = invite.buildInviteUrl(entry.args.peerId, entry.args.salt, entry.args.options);
      check('and builds the identical link from the same inputs', rebuilt === entry.url, rebuilt);
    }
  }

  const restored = await crypto.decryptBackupContainer(dart.backup.container, dart.backup.passphrase);
  const backupStore = new FakeVaultStore();
  const backupPlan = await backupStore.planBackupMerge(restored.tables, key);
  check('web opens the Dart backup file', Array.isArray(restored.tables.vaultMeta) && restored.tables.vaultMeta[0].salt === meta.salt);
  check('and every row in it is authentic', backupPlan.totals.added === dart.backup.expectedAdded && backupPlan.totals.tampered === 0, JSON.stringify(backupPlan.totals));

  const { kv, binding } = makeKv();
  for (const [k, v] of Object.entries(dart.mailbox.kv)) kv.set(k, v);
  const herPhone = new FakeVaultStore();
  for (const { table, liveRow } of dart.mailbox.tombstones || []) {
    await herPhone.table(table).put(herPhone._withDelIndex(rowFromWire(liveRow)));
  }
  const restore = routeFetchToWorker(binding);
  let got;
  try {
    got = await collectInto(herPhone, key, dart.mailbox.ownerId);
  } finally {
    restore();
  }
  check('web collects what Dart published, through the real worker', got.ok === true && got.applied === dart.mailbox.expectedApplied, JSON.stringify(got));
  for (const [table, ids] of Object.entries(dart.mailbox.liveIds)) {
    const have = (await herPhone.table(table).toArray()).filter((r) => r.deleted !== true).map((r) => r.id).sort();
    check(`mailbox delivered every live ${table} row`, same(have, ids), JSON.stringify(have));
  }
  for (const { table, id, expected } of dart.mailbox.samples) {
    const plain = await herPhone.getDecrypted(table, id, key);
    check(`collected ${table}/${id} reads the same on the web`, plain && same(stripFlags(toJsonValue(plain)), stripFlags(expected)));
  }
  const tombstoneCases = dart.mailbox.tombstones || [];
  for (const { table, id } of tombstoneCases) {
    const row = await herPhone.table(table).get(id);
    check(`Dart tombstone ${table}/${id} travels and kills the web copy`, Boolean(row) && row.deleted === true);
  }

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length > 0) {
    console.error('INTEROP VERIFY FAILED:');
    for (const f of failures) console.error(`  - ${f}`);
    process.exit(1);
  }
}

function stripFlags(value) {
  const out = {};
  for (const [k, v] of Object.entries(value || {})) {
    if (k.startsWith('_')) continue;
    out[k] = v;
  }
  return out;
}

const mode = process.argv[2];
if (mode === 'verify') {
  await verify();
} else {
  await generate();
}
