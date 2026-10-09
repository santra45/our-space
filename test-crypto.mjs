import {
  generateSalt,
  generateSecureNonce,
  generateUrlSafeNonce,
  bufferToBase64,
  base64ToBuffer,
  isValidBase64,
  isValidSalt,
  deriveKeyFromPassphrase,
  deriveKeyWithVerification,
  deriveVaultKeyBits,
  importVaultKeyFromBits,
  normalizePassphrase,
  PBKDF2_ITERATIONS_CURRENT,
  MIN_PASSPHRASE_LENGTH,
  createCanary,
  readCanary,
  verifyPassphraseAgainstMeta,
  VAULT_CANARY_TOKEN,
  encryptText,
  decryptText,
  encryptJSON,
  decryptJSON,
  encryptBlob,
  decryptBlob,
  encryptRecord,
  decryptRecord,
  RECORD_SCHEMA_VERSION,
  PLAINTEXT_RECORD_FIELDS,
  sealTimeLocked,
  unsealTimeLocked,
  isTimeLockOpen,
  getTimeLockBoundary,
  TimeLockedError,
  createEncryptedBackup,
  decryptBackupContainer,
  recordHasAuthenticatedHeader,
} from './src/services/crypto.js';
import { buildInviteUrl, parseInvite } from './src/utils/invite.js';
import db, {
  SweetheartDatabase,
  EXPORTED_TABLES,
  readBackupVaultIdentity,
  compareVaultIdentity,
} from './src/db/index.js';
import peerSync from './src/services/peerSync.js';

let passed = 0;
const failures = [];

function check(label, condition) {
  if (condition) {
    passed++;
    console.log(`  ✔ ${label}`);
  } else {
    failures.push(label);
    console.log(`  ✘ ${label}`);
  }
}

async function checkThrows(label, fn, match) {
  try {
    await fn();
    failures.push(label);
    console.log(`  ✘ ${label}  (it resolved, and should not have)`);
  } catch (err) {
    if (match && !match(err)) {
      failures.push(label);
      console.log(`  ✘ ${label}  (threw the wrong thing: ${err && err.message})`);
      return;
    }
    passed++;
    console.log(`  ✔ ${label}`);
  }
}

function section(title) {
  console.log(`\n── ${title}`);
}

const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const fastKey = (passphrase, salt) => deriveKeyFromPassphrase(passphrase, salt, { iterations: 2000 });

class FakeVaultStore {
  constructor(seed = {}) {
    this._tables = new Map();
    for (const name of EXPORTED_TABLES) {
      this._tables.set(name, new Map((seed[name] || []).map((row) => [row.id, row])));
    }
    this.failReads = false;
  }

  table(name) {
    const rows = this._tables.get(name);
    if (!rows) throw new Error(`FakeVaultStore: unknown table "${name}"`);
    const store = this;
    return {
      async get(id) {
        if (store.failReads) throw new Error('simulated IndexedDB failure');
        return rows.get(id);
      },
      async put(row) {
        rows.set(row.id, row);
      },
      async toArray() {
        return Array.from(rows.values());
      },
      async bulkGet(ids) {
        if (store.failReads) throw new Error('simulated IndexedDB failure');
        return ids.map((id) => rows.get(id));
      },
      async bulkPut(list) {
        for (const row of list) rows.set(row.id, row);
      },
      toCollection() {
        return {
          async primaryKeys() {
            if (store.failReads) throw new Error('simulated IndexedDB failure');
            return Array.from(rows.keys());
          },
        };
      },
      orderBy(field) {
        return {
          async eachKey(callback) {
            if (store.failReads) throw new Error('simulated IndexedDB failure');
            for (const row of rows.values()) callback(row[field], { primaryKey: row.id });
          },
        };
      },
      where(field) {
        return {
          equals(value) {
            return {
              async primaryKeys() {
                if (store.failReads) throw new Error('simulated IndexedDB failure');
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
  'readVaultIdentity',
  'exportRawDataForBackup',
  'planBackupMerge',
  'applyBackupMerge',
  'restoreVaultIdentity',
  'putEncrypted',
  'putEncryptedMany',
  'softDelete',
  '_withDelIndex',
  'getDecrypted',
  'listDecrypted',
  'getManifest',
]) {
  if (typeof SweetheartDatabase.prototype[method] !== 'function') {
    throw new Error(`test harness is stale: SweetheartDatabase has no ${method}()`);
  }
  FakeVaultStore.prototype[method] = SweetheartDatabase.prototype[method];
}

async function run() {
  console.log('=== Our Space — crypto verification suite ===');

  const passphrase = 'my-super-secret-couple-passphrase-2026';
  const salt = generateSalt();

  section('1. Primitives');

  check('generateSalt() produces a valid 16-byte salt', isValidSalt(salt));
  check('base64 round-trips arbitrary bytes', (() => {
    const bytes = new Uint8Array([0, 1, 127, 128, 255, 42]);
    return eq(Array.from(base64ToBuffer(bufferToBase64(bytes))), Array.from(bytes));
  })());
  check('base64ToBuffer accepts the URL-safe alphabet', (() => {
    const bytes = base64ToBuffer('-_8');
    return bytes.byteLength === 2;
  })());
  await checkThrows(
    'base64ToBuffer rejects malformed input instead of silently truncating',
    async () => base64ToBuffer('A')
  );
  check('nonces do not repeat', generateSecureNonce(16) !== generateSecureNonce(16));
  check(
    'generateUrlSafeNonce emits no +, / or = (X9: peer ids keep full entropy)',
    !/[+/=]/.test(generateUrlSafeNonce(10))
  );
  check(
    'generateUrlSafeNonce(10) carries all 80 bits (X9: the old id mangling lost 8)',
    base64ToBuffer(generateUrlSafeNonce(10)).byteLength === 10
  );
  check('isValidSalt rejects a short salt', !isValidSalt('app'));
  check('isValidSalt rejects a 32-byte value', !isValidSalt(bufferToBase64(new Uint8Array(32))));
  check('isValidBase64 rejects non-base64 characters', !isValidBase64('not base64!!'));

  section('2. KDF derivation (X8)');

  check('every vault derives at 600,000 iterations', PBKDF2_ITERATIONS_CURRENT === 600000);

  const countedSalt = generateSalt();
  const countedKey = await deriveKeyFromPassphrase(passphrase, countedSalt, { iterations: 2000 });
  const countedMeta = {
    salt: countedSalt,
    kdfIterations: 2000,
    ...(await createCanary(countedKey, { coupleNames: 'Us', startDate: '2021-06-14' })),
  };
  const countedOpen = await deriveKeyWithVerification(
    passphrase,
    countedSalt,
    async (candidate) => (await readCanary(candidate, countedMeta)) !== null,
    { iterations: countedMeta.kdfIterations }
  );
  check("a vault's recorded count is the one unlock derives at", countedOpen.iterations === 2000);

  await checkThrows(
    'and a derive that ignores the recorded count produces the WRONG key',
    async () => {
      const wrong = await deriveKeyFromPassphrase(passphrase, countedSalt);
      const canary = await readCanary(wrong, countedMeta);
      if (canary === null) throw new Error('wrong key, as expected');
      return canary;
    },
    (err) => err.message.includes('as expected')
  );

  const uncountedSalt = generateSalt();
  const uncountedKey = await deriveKeyFromPassphrase(passphrase, uncountedSalt, {
    iterations: PBKDF2_ITERATIONS_CURRENT,
  });
  const uncountedMeta = {
    salt: uncountedSalt,
    ...(await createCanary(uncountedKey, { coupleNames: 'Us', startDate: '2021-06-14' })),
  };
  const uncountedOpen = await deriveKeyWithVerification(
    passphrase,
    uncountedSalt,
    async (candidate) => (await readCanary(candidate, uncountedMeta)) !== null,
    { iterations: uncountedMeta.kdfIterations }
  );
  check(
    'a vaultMeta row with no recorded count derives at 600,000',
    uncountedOpen.iterations === PBKDF2_ITERATIONS_CURRENT
  );

  section('3. Passphrase handling');

  await checkThrows(
    `a passphrase under ${MIN_PASSPHRASE_LENGTH} chars is refused`,
    async () => fastKey('short123', salt)
  );
  check(
    'normalizePassphrase strips surrounding whitespace (mobile autocorrect)',
    normalizePassphrase('  a-very-long-passphrase-here  ') === 'a-very-long-passphrase-here'
  );
  check(
    'normalizePassphrase folds NFD to NFC (iOS vs Android composition)',
    normalizePassphrase('café-passphrase-long') === normalizePassphrase('café-passphrase-long')
  );

  const spaced = await deriveKeyWithVerification(
    `  ${passphrase}  `,
    countedSalt,
    async (candidate) => (await readCanary(candidate, countedMeta)) !== null,
    { iterations: countedMeta.kdfIterations }
  );
  check('a pasted passphrase with stray whitespace still opens the vault', spaced.normalized === true);

  await checkThrows(
    'a genuinely wrong passphrase is refused after every candidate',
    async () =>
      deriveKeyWithVerification(
        'definitely-not-the-right-passphrase',
        countedSalt,
        async (candidate) => (await readCanary(candidate, countedMeta)) !== null,
        { iterations: countedMeta.kdfIterations }
      ),
    (err) => /Incorrect passphrase/.test(err.message)
  );

  section('4. Canary (D3 — backup and pairing passphrase proof)');

  const key = await fastKey(passphrase, salt);
  const meta = {
    salt,
    kdfIterations: 2000,
    ...(await createCanary(key, { coupleNames: 'Alex & Sam', startDate: '2021-06-14' })),
  };

  const payload = await readCanary(key, meta);
  check('readCanary returns the config it carries', payload && payload.coupleNames === 'Alex & Sam');
  check('the canary carries the expected token', payload && payload.token === VAULT_CANARY_TOKEN);

  const wrongKey = await fastKey('a-completely-different-passphrase', salt);
  check('readCanary returns null for the wrong key', (await readCanary(wrongKey, meta)) === null);
  check(
    'verifyPassphraseAgainstMeta accepts the real passphrase',
    (await verifyPassphraseAgainstMeta(passphrase, uncountedMeta)) === true
  );
  check(
    'verifyPassphraseAgainstMeta rejects a typo (this is what stops an unopenable backup)',
    (await verifyPassphraseAgainstMeta(passphrase + 'x', uncountedMeta)) === false
  );

  section('5. AES-GCM and associated data');

  const secret = 'I love you to the moon and back 💕';
  const { ciphertext, iv } = await encryptText(secret, key);
  check('ciphertext is not the plaintext', !ciphertext.includes('love'));
  check('IV is 96 bits', base64ToBuffer(iv).byteLength === 12);
  check('text round-trips', (await decryptText(ciphertext, iv, key)) === secret);

  const tampered = ciphertext.slice(0, -6) + (ciphertext.slice(-6) === 'AAAAAA' ? 'BBBBBB' : 'AAAAAA');
  await checkThrows('the GCM auth tag rejects tampered ciphertext', async () =>
    decryptText(tampered, iv, key)
  );

  const bound = await encryptText(secret, key, 'record-id-42');
  check(
    'associated data decrypts when supplied again',
    (await decryptText(bound.ciphertext, bound.iv, key, 'record-id-42')) === secret
  );
  await checkThrows('associated data BINDS: a different value fails', async () =>
    decryptText(bound.ciphertext, bound.iv, key, 'record-id-43')
  );
  await checkThrows('associated data BINDS: omitting it fails', async () =>
    decryptText(bound.ciphertext, bound.iv, key)
  );

  const json = { caption: 'Bali sunset 🌅', tags: ['beach', 'love'], n: 7 };
  const encJson = await encryptJSON(json, key);
  check('JSON round-trips', eq(await decryptJSON(encJson.ciphertext, encJson.iv, key), json));

  const imageBytes = new Uint8Array(4096).map((_, i) => (i * 31) % 256);
  const packed = await encryptBlob(new Blob([imageBytes]), key);
  check('encryptBlob packs the IV in front of the ciphertext', packed.byteLength > imageBytes.length);
  const roundTripped = new Uint8Array(await (await decryptBlob(packed, key)).arrayBuffer());
  check('binary blob round-trips byte for byte', eq(Array.from(roundTripped), Array.from(imageBytes)));

  section('6. Record envelopes — schema v2 encrypted metadata');

  const blobBytes = new Uint8Array([1, 2, 3, 4, 5]);
  const plain = {
    id: 'mem-abc123',
    updatedAt: 1750000000000,
    deleted: false,
    caption: 'Our first sunset',
    date: '2026-06-15',
    category: 'travel',
    mime: 'image/webp',
    imageBlob: blobBytes,
  };

  const row = await encryptRecord(plain, key);
  check('the stored row is stamped v2', row.v === RECORD_SCHEMA_VERSION);
  check(
    'only id/updatedAt/deleted stay in plaintext',
    eq(
      Object.keys(row).filter((k) => !['v', 'ciphertext', 'iv', 'imageBlob'].includes(k)).sort(),
      [...PLAINTEXT_RECORD_FIELDS].sort()
    )
  );
  check('DECISION 2: `date` is no longer readable at rest', row.date === undefined);
  check('DECISION 2: `category` is no longer readable at rest', row.category === undefined);
  check('the caption is not in the row as plaintext', !JSON.stringify(row.ciphertext).includes('sunset'));
  check('binary stays top-level and uninflated', row.imageBlob === blobBytes);

  const back = await decryptRecord(row, key);
  check('every encrypted field comes back', back.caption === 'Our first sunset' && back.date === '2026-06-15');
  check('binary comes back attached', eq(Array.from(back.imageBlob), Array.from(blobBytes)));
  check('updatedAt is preserved exactly', back.updatedAt === plain.updatedAt);
  check('decryptRecord reports the schema version', back._schemaVersion === 2);
  check('an untouched row is not flagged as tampered', back._headerTampered === false);
  check('recordHasAuthenticatedHeader accepts a genuine envelope', recordHasAuthenticatedHeader(row) === true);

  const forged = { ...row, updatedAt: 9999999999999 };
  const forgedBack = await decryptRecord(forged, key);
  check(
    'rewriting the plaintext updatedAt is DETECTED (_headerTampered)',
    forgedBack._headerTampered === true
  );
  check(
    'the authenticated inner value wins over the forged header',
    forgedBack.updatedAt === plain.updatedAt
  );

  const forgedId = await decryptRecord({ ...row, id: 'mem-evil' }, key);
  check('rewriting the plaintext id is DETECTED', forgedId._headerTampered === true);

  await checkThrows('a record encrypted under another key does not decrypt', async () =>
    decryptRecord(row, wrongKey)
  );
  await checkThrows('encryptRecord demands a string id', async () => encryptRecord({ caption: 'x' }, key));

  section('6b. Photo bytes are bound into the envelope');

  check('an untouched row reports its binary as verified', back._binaryTampered === false);
  check('and not as merely unverified', back._binaryUnverified === false);
  check('the digest is not readable at rest', row._bin === undefined && row.imageBlob === blobBytes);

  const swappedBytes = new Uint8Array([9, 9, 9, 9, 9]);
  const swappedPhoto = await decryptRecord({ ...row, imageBlob: swappedBytes }, key);
  check('swapping the photo bytes is DETECTED (_binaryTampered)', swappedPhoto._binaryTampered === true);
  check(
    'and it is surfaced as _headerTampered, so every existing gate refuses it',
    swappedPhoto._headerTampered === true
  );

  const strippedPhoto = await decryptRecord(
    (({ imageBlob, ...rest }) => rest)(row),
    key
  );
  check('stripping the photo out of a row that had one is DETECTED', strippedPhoto._binaryTampered === true);

  const tombstone = await encryptRecord({ id: 'mem-abc123', updatedAt: 1750000000001, deleted: true }, key);
  const bolted = await decryptRecord({ ...tombstone, imageBlob: blobBytes }, key);
  check(
    'bolting a photo onto an envelope sealed without one is DETECTED',
    bolted._binaryTampered === true
  );

  const forgedDigest = await encryptRecord(
    { id: 'mem-forged-digest', updatedAt: 1750000000002, deleted: false, imageBlob: blobBytes, _bin: { imageBlob: 'not-a-real-digest' } },
    key
  );
  const forgedDigestBack = await decryptRecord(forgedDigest, key);
  check(
    'a caller-supplied _bin is ignored, not trusted',
    forgedDigestBack._binaryTampered === false && forgedDigestBack._bin === undefined
  );
  check(
    'and swapping THAT row still trips the real digest',
    (await decryptRecord({ ...forgedDigest, imageBlob: swappedBytes }, key))._binaryTampered === true
  );

  const preDigestPayload = {
    id: 'mem-pre-digest',
    updatedAt: 1750000000003,
    deleted: false,
    caption: 'Sealed before digests existed',
    date: '2024-01-01',
  };
  const preDigestSealed = await encryptJSON(preDigestPayload, key);
  const preDigestRow = {
    id: preDigestPayload.id,
    updatedAt: preDigestPayload.updatedAt,
    deleted: false,
    v: RECORD_SCHEMA_VERSION,
    ciphertext: preDigestSealed.ciphertext,
    iv: preDigestSealed.iv,
    imageBlob: blobBytes,
  };
  const preDigestBack = await decryptRecord(preDigestRow, key);
  check('a v2 row sealed before digests still opens', preDigestBack.caption === 'Sealed before digests existed');
  check('its photo still comes back attached', eq(Array.from(preDigestBack.imageBlob), Array.from(blobBytes)));
  check('it is NOT flagged as tampered', preDigestBack._binaryTampered === false && preDigestBack._headerTampered === false);
  check('but it is honestly reported as unverified', preDigestBack._binaryUnverified === true);
  check(
    'a partner still on the older build is therefore accepted, not rejected',
    recordHasAuthenticatedHeader(preDigestRow) === true
  );

  await checkThrows(
    'and a photo bolted onto a row with no envelope is not a record at all',
    async () =>
      decryptRecord(
        { id: 'mem-no-envelope', updatedAt: 1690000000000, deleted: false, imageBlob: blobBytes },
        key
      ),
    (err) => /not a sealed record/.test(err.message)
  );

  section('7. There is exactly one record shape');

  const oldShapeCipher = await encryptText('Read me on our anniversary', key);
  const oldShaped = {
    id: 'let-old-001',
    updatedAt: 1700000000000,
    deleted: false,
    unlockDate: '2027-06-14',
    isOpened: false,
    titleCipher: oldShapeCipher.ciphertext,
    titleIv: oldShapeCipher.iv,
    v: 1,
    needsReencrypt: 1,
  };
  await checkThrows(
    'a row in the old shape is not a record: decryptRecord refuses it outright',
    async () => decryptRecord(oldShaped, key),
    (err) => /not a sealed record/.test(err.message)
  );
  await checkThrows(
    'and claiming v:2 without an envelope does not help',
    async () => decryptRecord({ ...oldShaped, v: 2 }, key),
    (err) => /not a sealed record/.test(err.message)
  );
  await checkThrows('nor does an empty-string envelope open', async () =>
    decryptRecord({ id: 'x', updatedAt: 0, deleted: false, v: 2, ciphertext: '', iv: '' }, key)
  );
  check(
    'and the gates refuse it on the predicate, not on the error message',
    recordHasAuthenticatedHeader({ id: 'x', updatedAt: 0, deleted: false, v: 2, ciphertext: '', iv: '' }) ===
      false
  );
  check(
    'recordHasAuthenticatedHeader agrees, and it is the predicate every gate uses',
    recordHasAuthenticatedHeader(oldShaped) === false
  );

  const v2Row = await encryptRecord(
    {
      id: 'let-legacy-001',
      updatedAt: 1700000000000,
      deleted: false,
      title: 'Read me on our anniversary',
      content: 'You still make me laugh every single day.',
      unlockDate: '2027-06-14',
      isOpened: false,
    },
    key
  );
  check('the stored row is v2', v2Row.v === RECORD_SCHEMA_VERSION);
  check('unlockDate is not readable at rest', v2Row.unlockDate === undefined);
  check('isOpened is not readable at rest', v2Row.isOpened === undefined);
  check('and it has an authenticated header', recordHasAuthenticatedHeader(v2Row) === true);

  const v2Decrypted = await decryptRecord(v2Row, key);
  check('the letter title survives', v2Decrypted.title === 'Read me on our anniversary');
  check(
    'the letter body survives',
    v2Decrypted.content === 'You still make me laugh every single day.'
  );
  check('unlockDate survived inside the envelope', v2Decrypted.unlockDate === '2027-06-14');
  check('isOpened survived inside the envelope', v2Decrypted.isOpened === false);
  check(
    'envelope bookkeeping never leaks into the logical record',
    v2Decrypted.v === undefined && v2Decrypted.ciphertext === undefined && v2Decrypted._del === undefined
  );
  await checkThrows('a row under the wrong key throws rather than resolving to nothing', async () =>
    decryptRecord(v2Row, wrongKey)
  );

  const memRow = await encryptRecord(
    {
      id: 'mem-legacy-002',
      updatedAt: 1690000000000,
      deleted: false,
      caption: 'Bali, 2019',
      date: '2019-08-02',
      imageBlob: blobBytes,
    },
    key
  );
  const memBack = await decryptRecord(memRow, key);
  check('a photo caption round-trips', memBack.caption === 'Bali, 2019');
  check('the photo date is not readable at rest', memRow.date === undefined);
  check(
    'the encrypted image bytes are untouched',
    eq(Array.from(memBack.imageBlob), Array.from(blobBytes))
  );

  section('8. Time-locked letters (DECISION 3)');

  const DAY = 24 * 60 * 60 * 1000;
  const future = '2099-01-01';
  const past = '2000-01-01';
  const letterId = 'let-timelock-001';
  const body = 'Happy tenth anniversary. I would do all of it again.';

  const sealed = await sealTimeLocked(body, future, key, { context: letterId });
  check('the sealed envelope declares its version', sealed.lockVersion === 1);
  check('the body is nowhere in the envelope as plaintext', !JSON.stringify(sealed).includes('anniversary'));
  check(
    'the content key is wrapped, not stored',
    typeof sealed.wrappedKey === 'string' && sealed.wrappedKey.length > 0
  );
  check('the unlock date is stored verbatim', sealed.unlockDate === future);

  await checkThrows(
    'a sealed letter REFUSES to open before its date',
    async () => unsealTimeLocked(sealed, key, { context: letterId }),
    (err) => err instanceof TimeLockedError && err.unlockDate === future
  );

  const openable = await sealTimeLocked(body, past, key, { context: letterId });
  check(
    'a letter past its date opens and returns the exact body',
    (await unsealTimeLocked(openable, key, { context: letterId })) === body
  );

  await checkThrows(
    'DECISION 3: editing the stored unlockDate makes decryption FAIL, not unlock',
    async () =>
      unsealTimeLocked({ ...sealed, unlockDate: past }, key, { context: letterId }),
    (err) => !(err instanceof TimeLockedError)
  );
  await checkThrows(
    'moving a sealed payload onto another record fails (context is bound)',
    async () => unsealTimeLocked(openable, key, { context: 'let-someone-elses-letter' }),
    (err) => !(err instanceof TimeLockedError)
  );
  await checkThrows('a sealed letter needs the vault key', async () =>
    unsealTimeLocked(openable, wrongKey, { context: letterId })
  );
  await checkThrows('a truncated envelope is rejected, not half-read', async () =>
    unsealTimeLocked({ ...openable, wrappedKey: undefined }, key, { context: letterId })
  );

  const cheated = await unsealTimeLocked(sealed, key, {
    context: letterId,
    now: getTimeLockBoundary(future) + 1,
  });
  check(
    'HONEST LIMIT: a forward clock opens it early — the README says so plainly',
    cheated === body
  );

  const boundary = getTimeLockBoundary('2026-03-01');
  const asLocal = new Date(2026, 2, 1, 0, 0, 0, 0).getTime();
  check('P6: an unlock date is LOCAL midnight, not UTC midnight', boundary === asLocal);
  check('getTimeLockBoundary rejects an unparseable date', getTimeLockBoundary('not-a-date') === null);
  check('isTimeLockOpen is false before the boundary', isTimeLockOpen(future) === false);
  check('isTimeLockOpen is true after the boundary', isTimeLockOpen(past) === true);
  check('a letter with no unlock date is not locked', isTimeLockOpen(null) === true);
  check('isTimeLockOpen accepts a sealed envelope directly', isTimeLockOpen(sealed) === false);
  check(
    'isTimeLockOpen honours an explicit `now`',
    isTimeLockOpen(future, getTimeLockBoundary(future) + DAY) === true
  );
  await checkThrows('sealing without an unlock date is refused', async () =>
    sealTimeLocked(body, '', key)
  );

  section('9. Encrypted backup containers');

  const backupPassphrase = 'a-different-backup-passphrase-2026';
  const rawVault = {
    version: 2,
    exportedAt: new Date().toISOString(),
    tables: { letters: [v2Row], memories: [] },
  };

  const container = await createEncryptedBackup(rawVault, backupPassphrase);
  check('the container is version 2', container.version === 2);
  check('the container records its own iteration count', container.kdfIterations === PBKDF2_ITERATIONS_CURRENT);
  check('the container carries its own fresh salt', isValidSalt(container.salt) && container.salt !== salt);
  check('no letter id is visible in the container', !JSON.stringify(container).includes('let-legacy-001'));

  const restored = await decryptBackupContainer(container, backupPassphrase);
  check('a backup round-trips', eq(restored, rawVault));

  await checkThrows(
    'a wrong backup passphrase is refused with a clear message',
    async () => decryptBackupContainer(container, 'not-the-backup-passphrase'),
    (err) => /Incorrect backup passphrase/.test(err.message)
  );
  await checkThrows('a tampered container fails before anything is imported', async () =>
    decryptBackupContainer({ ...container, ciphertext: container.ciphertext.slice(0, -8) + 'AAAAAAAA' }, backupPassphrase)
  );

  const uncountedBody = await encryptText(JSON.stringify(rawVault), uncountedKey);
  const uncountedContainer = {
    magic: container.magic,
    version: 2,
    salt: uncountedSalt,
    iv: uncountedBody.iv,
    ciphertext: uncountedBody.ciphertext,
    exportedAt: '2024-01-01T00:00:00.000Z',
  };
  check(
    'a container with no recorded count opens at the current one',
    eq(await decryptBackupContainer(uncountedContainer, passphrase), rawVault)
  );
  await checkThrows(
    'and it still refuses the wrong passphrase',
    async () => decryptBackupContainer(uncountedContainer, 'not-the-right-passphrase-at-all'),
    (err) => /Incorrect backup passphrase/.test(err.message)
  );
  await checkThrows(
    'a container with a foreign magic header is rejected outright',
    async () => decryptBackupContainer({ ...uncountedContainer, magic: 'SOMETHING_ELSE' }, passphrase),
    (err) => /unrecognized container header/.test(err.message)
  );

  section('10. Invite parsing (a stranger must not choose our PBKDF2 salt)');

  const inviteUrl = buildInviteUrl('love-A1B2C3D4E5F6G7H8', salt, {
    baseUrl: 'https://our-space.example/',
    startDate: '2021-06-14',
    coupleNames: 'Alex & Sam',
  });
  const invite = parseInvite(inviteUrl);

  check('an invite round-trips its peer id', invite.partnerPeerId === 'love-A1B2C3D4E5F6G7H8');
  check('an invite round-trips the salt EXACTLY as stored', invite.salt === salt);
  check('an invite round-trips the anniversary', invite.startDate === '2021-06-14');
  check(
    'an invite never publishes a KDF count for a stranger to choose',
    !inviteUrl.includes('kdf=') && invite.kdfIterations === undefined
  );
  check(
    'the app never publishes the canary — that would be an offline cracking oracle',
    invite.canary === null && !inviteUrl.includes('canary=')
  );

  const proofInvite = parseInvite(
    buildInviteUrl('love-A1B2C3D4E5F6G7H8', salt, {
      baseUrl: 'https://our-space.example/',
      canary: meta.canary,
      canaryIv: meta.canaryIv,
    })
  );
  check('when a canary IS supplied it round-trips intact', proofInvite.canary === meta.canary);
  check('a round-tripped canary still verifies the passphrase', (await readCanary(key, proofInvite)) !== null);
  check("a bare domain is not an invite ('ourspace.app')", parseInvite('ourspace.app') === null);
  check("a version string is not an invite ('v1.2.3')", parseInvite('v1.2.3') === null);
  check(
    'a malformed salt is DROPPED rather than fed to PBKDF2',
    parseInvite('#connect=love-abcdefgh&salt=app').salt === null
  );
  check(
    'half a passphrase proof is not adopted',
    parseInvite(`#connect=love-abcdefgh&canary=${meta.canary}`).canary === null
  );
  check('a bare peer id is still a valid invite', parseInvite('love-abcdefgh').partnerPeerId === 'love-abcdefgh');
  check('junk is rejected', parseInvite('!!!') === null && parseInvite('') === null);
  check(
    'a kdf parameter in a hostile link is ignored entirely',
    parseInvite('#connect=love-abcdefgh&kdf=12').kdfIterations === undefined &&
      parseInvite('#connect=love-abcdefgh&kdf=1e9').kdfIterations === undefined
  );
  check(
    'and it does not stop the rest of the link parsing',
    parseInvite(`#connect=love-abcdefgh&kdf=12&salt=${encodeURIComponent(salt)}`).salt === salt
  );
  check(
    'an over-long couple name is truncated, not passed through',
    parseInvite(`#connect=love-abcdefgh&names=${'x'.repeat(500)}`).coupleNames.length === 120
  );

  section('11. A foreign vault cannot overwrite a colliding live record');

  const NOW = Date.now();
  const MINUTE = 60 * 1000;

  const liveBucket = await encryptRecord(
    {
      id: 'bkt-default-1',
      updatedAt: NOW - 10 * MINUTE,
      deleted: false,
      text: 'Watch the sunrise from the roof',
      completed: false,
    },
    key
  );
  const liveRoulette = await encryptRecord(
    { id: 'roulette-current', updatedAt: NOW - 10 * MINUTE, deleted: false, idea: 'Pizza and a bad film' },
    key
  );

  const foreignSalt = generateSalt();
  const foreignKey = await fastKey('an-entirely-different-couples-passphrase', foreignSalt);
  const foreignMeta = {
    salt: foreignSalt,
    kdfIterations: 2000,
    ...(await createCanary(foreignKey, { coupleNames: 'Someone Else', startDate: '2020-01-01' })),
  };
  const foreignBucket = await encryptRecord(
    { id: 'bkt-default-1', updatedAt: NOW, deleted: false, text: 'Not your list', completed: true },
    foreignKey
  );
  const foreignRoulette = await encryptRecord(
    { id: 'roulette-current', updatedAt: NOW, deleted: false, idea: 'Not your date' },
    foreignKey
  );

  const foreignTables = {
    vaultMeta: [{ id: 'config', ...foreignMeta, updatedAt: NOW }],
    bucketList: [foreignBucket],
    dateIdeas: [foreignRoulette],
  };
  const liveStore = new FakeVaultStore({ bucketList: [liveBucket], dateIdeas: [liveRoulette] });

  const foreignIdentity = readBackupVaultIdentity(foreignTables);
  check('a container carries a readable vault identity', foreignIdentity?.salt === foreignSalt);
  check(
    'a backup from another vault is classified FOREIGN',
    compareVaultIdentity(foreignIdentity, { ok: true, meta: { salt } }) === 'foreign'
  );
  check(
    'the same file against its own vault is classified SAME',
    compareVaultIdentity(foreignIdentity, { ok: true, meta: { salt: foreignSalt } }) === 'same'
  );
  check(
    'a FAILED local read is `unknown`, never `no-local-vault`',
    compareVaultIdentity(foreignIdentity, { ok: false, meta: null }) === 'unknown'
  );
  check(
    "the stranger's row is newer, so timestamp precedence alone would let it win",
    peerSync._incomingWins(liveBucket, foreignBucket) === true
  );

  const foreignPlan = await liveStore.planBackupMerge(foreignTables, key);
  check(
    'both colliding foreign rows are refused as undecryptable',
    foreignPlan.totals.undecryptable === 2
  );
  check(
    'nothing from a foreign vault is added or updated',
    foreignPlan.totals.added === 0 && foreignPlan.totals.updated === 0
  );
  check('the plan queues no writes at all', foreignPlan.writes.length === 0);
  check(
    'vaultMeta is never a merge target, even in a foreign file',
    foreignPlan.skippedTables.includes('vaultMeta')
  );

  const foreignApplied = await liveStore.applyBackupMerge(foreignPlan);
  check(
    'applying an all-refused plan writes nothing',
    Object.keys(foreignApplied.written).length === 0
  );
  const survivingBucket = await liveStore.table('bucketList').get('bkt-default-1');
  const survivingPlain = await decryptRecord(survivingBucket, key);
  check(
    'the live bkt-default-1 is untouched and still readable',
    survivingPlain.text === 'Watch the sunrise from the roof' && survivingPlain.completed === false
  );
  section('11b. A row carrying NO ciphertext cannot get into a table at all');

  const bareTombstone = {
    id: 'bkt-default-1',
    updatedAt: NOW + MINUTE,
    deleted: true,
    v: 2,
  };

  check(
    'a row with no envelope has no authenticated header',
    recordHasAuthenticatedHeader(bareTombstone) === false
  );
  check(
    'an empty-string envelope is not one either',
    recordHasAuthenticatedHeader({ id: 'x', v: 2, ciphertext: '', iv: '' }) === false
  );
  check('a genuine envelope IS one', recordHasAuthenticatedHeader(liveBucket) === true);

  const barePlan = await liveStore.planBackupMerge(
    { bucketList: [bareTombstone], dateIdeas: [{ ...bareTombstone, id: 'roulette-current' }] },
    key
  );
  check(
    'both unauthenticated rows are refused, not counted as updates',
    barePlan.totals.undecryptable === 2 && barePlan.totals.updated === 0
  );
  check('an unauthenticated plan queues no writes', barePlan.writes.length === 0);

  await liveStore.applyBackupMerge(barePlan);
  const afterBare = await decryptRecord(
    await liveStore.table('bucketList').get('bkt-default-1'),
    key
  );
  check(
    'the live encrypted row survived the bare tombstone',
    afterBare.text === 'Watch the sunrise from the roof' && afterBare.deleted === false
  );

  const bareCreate = { id: 'bkt-never-seen', updatedAt: NOW, deleted: false, v: 2 };
  const bareCreatePlan = await liveStore.planBackupMerge({ bucketList: [bareCreate] }, key);
  check(
    'an unsealed row cannot create either, so nothing unsealed ever lands',
    bareCreatePlan.totals.added === 0 &&
      bareCreatePlan.totals.undecryptable === 1 &&
      bareCreatePlan.writes.length === 0
  );
  await liveStore.applyBackupMerge(bareCreatePlan);
  check(
    'and applying that plan leaves the id empty',
    (await liveStore.table('bucketList').get('bkt-never-seen')) === undefined
  );

  const bareSmuggle = await liveStore.applyBackupMerge({
    writes: [{ table: 'bucketList', row: bareCreate }],
    incomingWins: () => true,
  });
  check(
    'a hand-built plan cannot smuggle an unsealed row in as a creation',
    (bareSmuggle.written.bucketList || 0) === 0 && bareSmuggle.refusedSincePreview === 1
  );

  const priorKey = peerSync.cryptoKey;
  peerSync.cryptoKey = key;
  try {
    const wireVerdict = await peerSync._verifyRecordIntegrity(bareTombstone);
    check(
      'the sync path also refuses it, as `unauthenticated`',
      wireVerdict.ok === false && wireVerdict.code === 'unauthenticated'
    );
    const wireGenuine = await peerSync._verifyRecordIntegrity(liveBucket);
    check('a genuine row still passes the sync gate', wireGenuine.ok === true);
  } finally {
    peerSync.cryptoKey = priorKey;
  }

  check(
    'the wire gate refuses a version-1 header outright',
    peerSync._validateWireRecord({ id: 'x', updatedAt: NOW, deleted: false, v: 1 }).code ===
      'bad_version'
  );
  check(
    'and one with no version at all - absent is not a pass',
    peerSync._validateWireRecord({ id: 'x', updatedAt: NOW, deleted: false }).code === 'bad_version'
  );
  check(
    'the import path refuses both the same way',
    (await liveStore.planBackupMerge({ bucketList: [{ ...bareCreate, v: 1 }] }, key)).totals
      .invalid === 1
  );

  const survivingRoulette = await decryptRecord(
    await liveStore.table('dateIdeas').get('roulette-current'),
    key
  );
  check('the live roulette-current is untouched', survivingRoulette.idea === 'Pizza and a bad film');

  section('11bis. A decoy cipher pair is not a record');

  const livePhotoBytes = new Uint8Array([1, 2, 3, 4]);
  const liveMemory = await encryptRecord(
    {
      id: 'mem-1',
      updatedAt: NOW - 10 * MINUTE,
      deleted: false,
      caption: 'Us on the roof',
      imageBlob: livePhotoBytes,
    },
    key
  );
  await liveStore.table('memories').put(liveMemory);

  const decoy = await encryptText('anything at all', key);

  const forgedTombstone = {
    id: 'mem-1',
    updatedAt: NOW + MINUTE,
    deleted: true,
    v: 1,
    captionCipher: decoy.ciphertext,
    captionIv: decoy.iv,
  };

  check(
    'the decoy pair buys nothing: there is no authenticated header',
    recordHasAuthenticatedHeader(forgedTombstone) === false
  );
  check('and a genuine envelope does have one', recordHasAuthenticatedHeader(liveMemory) === true);
  await checkThrows(
    'the row cannot even be opened - the decoy is never reached',
    async () => decryptRecord(forgedTombstone, key),
    (err) => /not a sealed record/.test(err.message)
  );

  const forgedPlan = await liveStore.planBackupMerge({ memories: [forgedTombstone] }, key);
  check(
    'the forgery is refused, and never counted as an update',
    forgedPlan.totals.updated === 0 && forgedPlan.totals.deleted === 0
  );
  check('the forgery queues no write', forgedPlan.writes.length === 0);

  await liveStore.applyBackupMerge(forgedPlan);
  const survivedForgery = await liveStore.table('memories').get('mem-1');
  check(
    'the live photo row is intact: not tombstoned, bytes still present',
    survivedForgery.deleted !== true && survivedForgery.imageBlob?.length === 4
  );

  const smuggled = await liveStore.applyBackupMerge({
    writes: [{ table: 'memories', row: forgedTombstone }],
    incomingWins: () => true,
  });
  check(
    'a hand-built plan cannot smuggle the forgery past the transaction',
    (smuggled.written.memories || 0) === 0
  );
  const survivedSmuggle = await liveStore.table('memories').get('mem-1');
  check(
    'the photo survived the smuggled plan too',
    survivedSmuggle.deleted !== true && survivedSmuggle.imageBlob?.length === 4
  );

  const forgedNew = {
    id: 'mem-never-seen',
    updatedAt: NOW,
    deleted: false,
    v: 1,
    captionCipher: decoy.ciphertext,
    captionIv: decoy.iv,
  };
  const createPlan = await liveStore.planBackupMerge({ memories: [forgedNew] }, key);
  check(
    'and it can no longer create at an unused id either',
    createPlan.totals.added === 0 && createPlan.writes.length === 0
  );

  section('11d. A swapped photo cannot ride in on a valid envelope');

  const pierBytes = new Uint8Array(64).map((_, i) => (i * 13) % 256);
  const pierRow = await encryptRecord(
    {
      id: 'mem-pier',
      updatedAt: NOW - 30 * MINUTE,
      deleted: false,
      caption: 'The pier at night',
      imageBlob: pierBytes,
    },
    key
  );
  const photoStore = new FakeVaultStore({ memories: [pierRow] });

  const asContainerRow = (storedRow) => {
    const { imageBlob, ...rest } = storedRow;
    return imageBlob ? { ...rest, imageBlobBase64: bufferToBase64(imageBlob) } : rest;
  };

  const swappedWire = {
    ...asContainerRow(pierRow),
    imageBlobBase64: bufferToBase64(new Uint8Array(64).fill(255)),
  };

  const swapPlan = await photoStore.planBackupMerge({ memories: [swappedWire] }, key);
  check(
    'the swapped photo is refused by the integrity gate',
    swapPlan.totals.tampered === 1 &&
      swapPlan.totals.added === 0 &&
      swapPlan.totals.updated === 0
  );
  check(
    'and it is NOT reported as undecryptable - it opened under this very key',
    swapPlan.totals.undecryptable === 0
  );
  check('it queues no write', swapPlan.writes.length === 0);
  await photoStore.applyBackupMerge(swapPlan);
  const survivingPhoto = await decryptRecord(await photoStore.table('memories').get('mem-pier'), key);
  check(
    'the live photo bytes are still the originals, byte for byte',
    eq(Array.from(survivingPhoto.imageBlob), Array.from(pierBytes))
  );

  const savedPeerKey = peerSync.cryptoKey;
  peerSync.cryptoKey = key;
  try {
    const swappedIncoming = { ...pierRow, imageBlob: new Uint8Array(64).fill(255) };
    const wireVerdict = await peerSync._verifyRecordIntegrity(swappedIncoming);
    check(
      'the sync path refuses a swapped photo and names the reason',
      wireVerdict.ok === false && wireVerdict.code === 'binary_tampered'
    );
    const honestVerdict = await peerSync._verifyRecordIntegrity(pierRow);
    check('and still accepts the genuine row', honestVerdict.ok === true);
    const preDigestVerdict = await peerSync._verifyRecordIntegrity(preDigestRow);
    check(
      'a partner on the older build is still accepted (unverified, not refused)',
      preDigestVerdict.ok === true
    );
  } finally {
    peerSync.cryptoKey = savedPeerKey;
  }

  const freshPhotoDevice = new FakeVaultStore({});
  const honestPlan = await freshPhotoDevice.planBackupMerge(
    { memories: [asContainerRow(pierRow), asContainerRow(preDigestRow)] },
    key
  );
  check(
    'an untouched photo row and a pre-digest one both restore',
    honestPlan.totals.added === 2 && honestPlan.totals.undecryptable === 0
  );
  await freshPhotoDevice.applyBackupMerge(honestPlan);
  const restoredPier = await decryptRecord(
    await freshPhotoDevice.table('memories').get('mem-pier'),
    key
  );
  check(
    'the restored photo survives base64 and the digest check together',
    eq(Array.from(restoredPier.imageBlob), Array.from(pierBytes)) &&
      restoredPier._binaryTampered === false
  );

  section('11ter. A replayed envelope with a swapped photo cannot win the tie-break');

  const tieReplayBase = await encryptRecord(
    { id: 'mem-replay', updatedAt: NOW, deleted: false, caption: 'Real photo' },
    key
  );
  const tieRealPhoto = { ...tieReplayBase, imageBlob: new Uint8Array(64) };
  const tieSwappedPhoto = { ...tieReplayBase, imageBlob: new Uint8Array(900) };

  check(
    'the two rows differ ONLY in the attached blob',
    tieSwappedPhoto.ciphertext === tieRealPhoto.ciphertext &&
      tieSwappedPhoto.iv === tieRealPhoto.iv &&
      tieSwappedPhoto.updatedAt === tieRealPhoto.updatedAt
  );
  check(
    'a longer garbage blob no longer wins the tie-break',
    peerSync._incomingWins(tieRealPhoto, tieSwappedPhoto) === false
  );
  check(
    'and the comparison is symmetric - neither side flips on blob length',
    peerSync._incomingWins(tieSwappedPhoto, tieRealPhoto) === false
  );
  check(
    'blob length is gone from the fingerprint entirely',
    peerSync._fingerprint(tieRealPhoto) === peerSync._fingerprint(tieSwappedPhoto)
  );

  await liveStore.table('memories').put(tieRealPhoto);
  const tieReplayPlan = await liveStore.planBackupMerge({ memories: [tieSwappedPhoto] }, key);
  check(
    'the replay is counted stale, never as an update',
    tieReplayPlan.totals.updated === 0 && tieReplayPlan.totals.deleted === 0
  );
  await liveStore.applyBackupMerge(tieReplayPlan);
  const tieSurvived = await liveStore.table('memories').get('mem-replay');
  check(
    'the real photo bytes survived the replay',
    tieSurvived.imageBlob?.length === 64
  );

  const tieGenuineEdit = await encryptRecord(
    { id: 'mem-replay', updatedAt: NOW + MINUTE, deleted: false, caption: 'Edited' },
    key
  );
  check(
    'a genuinely newer edit still wins',
    peerSync._incomingWins(tieRealPhoto, tieGenuineEdit) === true
  );

  section('11quater. A hostile row cannot insert an invisible delete or abort the import');

  const forgedNewTombstone = await encryptRecord(
    { id: 'bkt-default-3', updatedAt: NOW, deleted: true },
    key,
    { table: 'bucketList' }
  );
  const tombPlan = await liveStore.planBackupMerge({ bucketList: [forgedNewTombstone] }, key);
  check(
    'a tombstone for an id we have never seen is refused, not "added"',
    tombPlan.totals.added === 0 && tombPlan.totals.invalid === 1
  );
  check('and it queues no write', tombPlan.writes.length === 0);
  const noGhost = await liveStore.table('bucketList').get('bkt-default-3');
  check('so no invisible row is left to suppress the starter seed', !noGhost);

  const hugeAlloc = await encryptRecord(
    { id: 'mem-huge', updatedAt: NOW, deleted: false, caption: 'x' },
    key
  );
  const goodRow = await encryptRecord(
    { id: 'mem-good', updatedAt: NOW, deleted: false, caption: 'keep me' },
    key
  );
  let survivedHostileBlob = true;
  let hostilePlan = null;
  try {
    hostilePlan = await liveStore.planBackupMerge(
      { memories: [{ ...hugeAlloc, imageBlob: 9e15 }, goodRow] },
      key
    );
  } catch {
    survivedHostileBlob = false;
  }
  check('a 9e15 imageBlob does not abort the whole import', survivedHostileBlob);
  check(
    'the hostile row is rejected as invalid, and the legitimate row still lands',
    hostilePlan && hostilePlan.totals.invalid === 1 && hostilePlan.totals.added === 1
  );

  section('11e. An envelope sealed for one table cannot be replayed into another');

  const crossLetter = await encryptRecord(
    {
      id: 'shared-id-1',
      updatedAt: NOW - MINUTE,
      deleted: false,
      title: 'Open when you miss me',
      content: 'Still here.',
    },
    key,
    { table: 'letters' }
  );
  const crossTombstone = await encryptRecord(
    { id: 'shared-id-1', updatedAt: NOW, deleted: true },
    key,
    { table: 'bucketList' }
  );

  const crossStore = new FakeVaultStore({ letters: [crossLetter] });
  const crossPlan = await crossStore.planBackupMerge({ letters: [crossTombstone] }, key);
  check(
    'a bucketList tombstone filed under `letters` is refused as tampered',
    crossPlan.totals.tampered === 1 && crossPlan.totals.deleted === 0
  );
  check('and it queues no write', crossPlan.writes.length === 0);
  await crossStore.applyBackupMerge(crossPlan);
  const survivingLetter = await crossStore.table('letters').get('shared-id-1');
  check(
    'the live letter is still there and still not a tombstone',
    Boolean(survivingLetter) && survivingLetter.deleted !== true
  );
  const readableLetter = await decryptRecord(survivingLetter, key, { table: 'letters' });
  check('and it still reads correctly in its own table', readableLetter.content === 'Still here.');

  await crossStore.table('bucketList').put(
    await encryptRecord(
      { id: 'shared-id-1', updatedAt: NOW - MINUTE, deleted: false, text: 'A real bucket item' },
      key,
      { table: 'bucketList' }
    )
  );
  const honestTombPlan = await crossStore.planBackupMerge({ bucketList: [crossTombstone] }, key);
  check(
    'the same tombstone in its OWN table is accepted, and counted as destructive',
    honestTombPlan.totals.deleted === 1 && honestTombPlan.totals.tampered === 0
  );

  const savedCrossKey = peerSync.cryptoKey;
  peerSync.cryptoKey = key;
  try {
    const wrongTable = await peerSync._verifyRecordIntegrity(crossTombstone, 'letters');
    check(
      'the sync gate refuses a cross-table replay and names the reason',
      wrongTable.ok === false && wrongTable.code === 'table_mismatch'
    );
    const rightTable = await peerSync._verifyRecordIntegrity(crossTombstone, 'bucketList');
    check('and still accepts the row in the table it was sealed for', rightTable.ok === true);
  } finally {
    peerSync.cryptoKey = savedCrossKey;
  }

  const unboundRow = await encryptRecord(
    { id: 'pre-binding-1', updatedAt: NOW, deleted: false, text: 'Sealed before the binding' },
    key
  );
  const unboundPlain = await decryptRecord(unboundRow, key, { table: 'letters' });
  check(
    'a pre-binding envelope is `unverified`, NOT tampered, whatever table it is read as',
    unboundPlain._tableUnverified === true &&
      unboundPlain._tableTampered === false &&
      unboundPlain._headerTampered === false
  );
  const compatPlan = await new FakeVaultStore().planBackupMerge({ letters: [unboundRow] }, key);
  check(
    'so an older vault still restores',
    compatPlan.totals.added === 1 && compatPlan.totals.tampered === 0
  );

  const unboundTombstone = await encryptRecord(
    { id: 'shared-id-2', updatedAt: NOW, deleted: true },
    key
  );
  const gapStore = new FakeVaultStore({
    letters: [
      await encryptRecord(
        { id: 'shared-id-2', updatedAt: NOW - MINUTE, deleted: false, content: 'Reachable' },
        key,
        { table: 'letters' }
      ),
    ],
  });
  const gapPlan = await gapStore.planBackupMerge({ letters: [unboundTombstone] }, key);
  check(
    'an UNBOUND tombstone can no longer delete a live letter',
    gapPlan.totals.deleted === 0 && gapPlan.totals.unauthenticated === 1
  );
  await gapStore.applyBackupMerge(gapPlan);
  const gapSurvivor = await gapStore.table('letters').get('shared-id-2');
  check('the live letter survived the unbound tombstone', gapSurvivor.deleted !== true);

  const unboundCreate = await encryptRecord(
    { id: 'let-from-old-vault', updatedAt: NOW, deleted: false, content: 'Old but honest' },
    key
  );
  const createGapPlan = await gapStore.planBackupMerge({ letters: [unboundCreate] }, key);
  check(
    'but an unbound row for an unused id still creates, so old backups restore',
    createGapPlan.totals.added === 1 && createGapPlan.totals.unauthenticated === 0
  );

  const editedUnbound = await gapStore.putEncrypted(
    'letters',
    { id: 'let-from-old-vault', updatedAt: NOW + MINUTE, deleted: false, content: 'Edited' },
    key
  );
  const editedPlain = await decryptRecord(editedUnbound, key, { table: 'letters' });
  check(
    'an ordinary edit is what binds an old row, and it binds it fully',
    editedPlain._tableUnverified === false && editedPlain._tableTampered === false
  );
  const editedAway = await decryptRecord(editedUnbound, key, { table: 'bucketList' });
  check(
    'so the edited row IS refused in another table',
    editedAway._tableTampered === true && editedAway._headerTampered === true
  );

  section('11quinquies. An unverified binding may create but never overwrite');

  const qSweptStore = new FakeVaultStore({
    memories: [
      {
        ...(await encryptRecord(
          { id: 'mem-swept', updatedAt: NOW - MINUTE, deleted: false, caption: 'Bound and swept' },
          key,
          { table: 'memories' }
        )),
        imageBlob: new Uint8Array(64),
      },
    ],
  });

  const qHeldEnvelope = await encryptRecord(
    { id: 'mem-swept', updatedAt: NOW + MINUTE, deleted: false, caption: 'Bound and swept' },
    key
  );

  const qSwapPlan = await qSweptStore.planBackupMerge(
    { memories: [{ ...qHeldEnvelope, imageBlob: new Uint8Array(900) }] },
    key
  );
  check(
    'a held pre-binding envelope cannot overwrite, even on a swept device',
    qSwapPlan.totals.updated === 0 &&
      qSwapPlan.totals.unauthenticated + qSwapPlan.totals.tampered === 1
  );

  const qStripPlan = await qSweptStore.planBackupMerge({ memories: [qHeldEnvelope] }, key);
  check(
    'and it cannot erase the photo by omitting the bytes either',
    qStripPlan.totals.updated === 0 && qStripPlan.totals.unauthenticated === 1
  );

  await qSweptStore.applyBackupMerge(qSwapPlan);
  await qSweptStore.applyBackupMerge(qStripPlan);
  const qSweptSurvivor = await qSweptStore.table('memories').get('mem-swept');
  check(
    'the photo bytes survived both',
    qSweptSurvivor.imageBlob?.length === 64 && qSweptSurvivor.deleted !== true
  );

  const qOldCreate = await encryptRecord(
    { id: 'mem-from-old-backup', updatedAt: NOW, deleted: false, caption: 'Honest and old' },
    key
  );
  const qOldCreatePlan = await qSweptStore.planBackupMerge({ memories: [qOldCreate] }, key);
  check(
    'an unverified row for an unused id still creates',
    qOldCreatePlan.totals.added === 1 && qOldCreatePlan.totals.unauthenticated === 0
  );

  const qBoundNewer = await encryptRecord(
    {
      id: 'mem-swept',
      updatedAt: NOW + 2 * MINUTE,
      deleted: false,
      caption: 'Legit edit',
      imageBlob: new Uint8Array(64),
    },
    key,
    { table: 'memories' }
  );
  const qBoundPlan = await qSweptStore.planBackupMerge({ memories: [qBoundNewer] }, key);
  check(
    'a properly bound newer row still overwrites, so records are not frozen',
    qBoundPlan.totals.updated === 1 && qBoundPlan.totals.unauthenticated === 0
  );

  section('11sexies. An attacker-authored row cannot be created, so there is nothing to launder');

  const sxDonor = await encryptRecord(
    { id: 'sxDonor', updatedAt: NOW, deleted: false, note: 'any row from the file' },
    key,
    { table: 'letters' }
  );
  const sxForged = {
    id: 'let-victim',
    updatedAt: NOW + 60 * MINUTE,
    deleted: false,
    v: 1,
    contentCipher: sxDonor.ciphertext,
    contentIv: sxDonor.iv,
  };

  const sxVictimStore = new FakeVaultStore({
    letters: [
      await encryptRecord(
        { id: 'let-victim', updatedAt: NOW, deleted: false, content: 'The real letter' },
        key,
        { table: 'letters' }
      ),
    ],
  });
  const sxDirectPlan = await sxVictimStore.planBackupMerge({ letters: [sxForged] }, key);
  check(
    'CONTROL: the forgery is refused an overwrite',
    sxDirectPlan.totals.updated === 0 && sxDirectPlan.writes.length === 0
  );

  const sxLaunderStore = new FakeVaultStore({});
  const sxCreatedPlan = await sxLaunderStore.planBackupMerge({ letters: [sxForged] }, key);
  check(
    'THE POINT: it cannot be created on a device that lacks the id either',
    sxCreatedPlan.totals.added === 0 && sxCreatedPlan.writes.length === 0
  );
  await sxLaunderStore.applyBackupMerge(sxCreatedPlan);
  check(
    'so nothing lands at that id at all, and there is nothing to promote later',
    (await sxLaunderStore.table('letters').get('let-victim')) === undefined
  );

  check(
    'and the database has no re-seal sweep left to promote anything with',
    typeof SweetheartDatabase.prototype.migrateLegacyRecords !== 'function' &&
      typeof SweetheartDatabase.prototype.countLegacyRecords !== 'function'
  );
  check(
    'nor the provenance machinery that existed only to patch that sweep',
    typeof SweetheartDatabase.prototype._inheritedProvenance !== 'function'
  );

  const sxVictimSurvivor = await sxVictimStore.table('letters').get('let-victim');
  const sxVictimPlain = await decryptRecord(sxVictimSurvivor, key, { table: 'letters' });
  check('the real letter body survived the full chain', sxVictimPlain.content === 'The real letter');

    section('11septies. A refusal we cannot verify is NOT staleness and must not read as "up to date"');

  const withFakeDb = async (store, fn) => {
    const hadTable = Object.prototype.hasOwnProperty.call(db, 'table');
    const hadTransaction = Object.prototype.hasOwnProperty.call(db, 'transaction');
    const savedTable = db.table;
    const savedTransaction = db.transaction;
    db.table = (name) => store.table(name);
    db.transaction = (mode, tables, body) => body();
    try {
      return await fn();
    } finally {
      if (hadTable) db.table = savedTable;
      else delete db.table;
      if (hadTransaction) db.transaction = savedTransaction;
      else delete db.transaction;
    }
  };

  const spSavedKey = peerSync.cryptoKey;
  const spSavedAuth = peerSync.isAuthorized;
  peerSync.cryptoKey = key;
  peerSync.isAuthorized = true;

  const spLive = await encryptRecord(
    { id: 'let-sp', updatedAt: NOW, deleted: false, content: 'Local copy' },
    key,
    { table: 'letters' }
  );
  const spOldBuildEdit = await encryptRecord(
    { id: 'let-sp', updatedAt: NOW + 60 * MINUTE, deleted: false, content: 'Their newer edit' },
    key
  );
  const spOldBuildDelete = await encryptRecord(
    { id: 'let-sp', updatedAt: NOW + 90 * MINUTE, deleted: true },
    key
  );
  const spOldBuildCreate = await encryptRecord(
    { id: 'let-sp-new', updatedAt: NOW + 60 * MINUTE, deleted: false, content: 'Something new' },
    key
  );
  const spBoundNewer = await encryptRecord(
    { id: 'let-sp', updatedAt: NOW + 120 * MINUTE, deleted: false, content: 'A swept edit' },
    key,
    { table: 'letters' }
  );
  const spBoundOlder = await encryptRecord(
    { id: 'let-sp', updatedAt: NOW - 60 * MINUTE, deleted: false, content: 'Genuinely older' },
    key,
    { table: 'letters' }
  );

  const spCommit = async (wireRow) => {
    const store = new FakeVaultStore({ letters: [spLive] });
    const { staged, rejected } = await peerSync._stageIncomingRecords([
      { table: 'letters', data: wireRow },
    ]);
    const result = await withFakeDb(store, () => peerSync._commitStagedRecords(staged));
    return { ...result, rejected, staged: staged.length, store };
  };

  const spEdit = await spCommit(spOldBuildEdit);
  check(
    'an edit from a partner on the previous build is staged, then refused',
    spEdit.staged === 1 && spEdit.rejected === 0 && spEdit.applied === 0
  );
  check(
    'REGRESSION FIXED: it is counted as `unverifiable`, never as `stale`',
    spEdit.unverifiable === 1 && spEdit.stale === 0
  );

  const spDelete = await spCommit(spOldBuildDelete);
  check(
    'their delete is refused the same way, and counted the same way',
    spDelete.applied === 0 && spDelete.unverifiable === 1 && spDelete.stale === 0
  );

  const spStale = await spCommit(spBoundOlder);
  check(
    'a genuinely older BOUND row is still `stale`, and not `unverifiable`',
    spStale.applied === 0 && spStale.stale === 1 && spStale.unverifiable === 0
  );
  const spWins = await spCommit(spBoundNewer);
  check(
    'a newer BOUND row still applies - the gate did not get stricter',
    spWins.applied === 1 && spWins.unverifiable === 0
  );
  const spCreate = await spCommit(spOldBuildCreate);
  check(
    'and an unverifiable CREATE still lands: may create, never overwrite',
    spCreate.applied === 1 && spCreate.unverifiable === 0
  );

  const spStatuses = [];
  const spCapture = (status) => spStatuses.push(status);
  peerSync.on('status', spCapture);
  const spBroadcastStore = new FakeVaultStore({ letters: [spLive] });
  await withFakeDb(spBroadcastStore, () =>
    peerSync._applySingleLiveRecord({ table: 'letters', data: spOldBuildEdit })
  );
  peerSync.off('status', spCapture);

  const spWarned = spStatuses.find((status) => status.code === 'records_unverifiable');
  check(
    'a discarded live edit raises a warning instead of passing in silence',
    Boolean(spWarned) && spWarned.unverifiable === 1
  );
  check(
    'the warning text names the count and the actual remedy, in plain words',
    typeof spWarned?.warning === 'string' &&
      spWarned.warning.includes('1 change') &&
      spWarned.warning.includes('did not come through') &&
      spWarned.warning.includes('up to date on both phones') &&
      !/verif|authenticat|integrity|unverifiable/i.test(spWarned.warning)
  );
  check(
    'and it is a WARNING, so it cannot paint the live connection as dead',
    spWarned?.error === undefined && spWarned?.state !== 'error'
  );
  const spSurvivor = await decryptRecord(
    await spBroadcastStore.table('letters').get('let-sp'),
    key,
    { table: 'letters' }
  );
  check('the local copy is untouched by the refused broadcast', spSurvivor.content === 'Local copy');

  const spTieBase = await encryptRecord(
    { id: 'let-tie', updatedAt: NOW, deleted: false, content: 'Mine' },
    key,
    { table: 'letters' }
  );
  check(
    'a stray Cipher field on a v2 replay no longer wins the tie-break',
    peerSync._incomingWins(spTieBase, { ...spTieBase, contentCipher: 'zzzz' }) === false
  );
  check(
    'and the fingerprint of a v2 row ignores it entirely',
    peerSync._fingerprint(spTieBase) === peerSync._fingerprint({ ...spTieBase, contentCipher: 'zzzz' })
  );
  const spTieOther = await encryptRecord(
    { id: 'let-tie', updatedAt: NOW, deleted: false, content: 'Theirs' },
    key,
    { table: 'letters' }
  );
  const spHigher =
    peerSync._fingerprint(spTieOther) > peerSync._fingerprint(spTieBase) ? spTieOther : spTieBase;
  const spLower = spHigher === spTieOther ? spTieBase : spTieOther;
  check(
    'a genuine tie is still broken deterministically, and both ways round',
    peerSync._incomingWins(spLower, spHigher) === true &&
      peerSync._incomingWins(spHigher, spLower) === false
  );

  peerSync.cryptoKey = spSavedKey;
  peerSync.isAuthorized = spSavedAuth;

  section('11octies. Refusals on the RESTORE path are legible, and the re-check is real');

  const soLive = await encryptRecord(
    { id: 'let-so', updatedAt: NOW, deleted: false, content: 'On the device' },
    key,
    { table: 'letters' }
  );
  const soOldBackupNewer = await encryptRecord(
    { id: 'let-so', updatedAt: NOW + 60 * MINUTE, deleted: false, content: 'Newer, in the file' },
    key
  );
  const soOldBackupOlder = await encryptRecord(
    { id: 'let-so', updatedAt: NOW - 60 * MINUTE, deleted: false, content: 'Older, in the file' },
    key
  );

  const soStore = new FakeVaultStore({ letters: [soLive] });
  const soNewerPlan = await soStore.planBackupMerge({ letters: [soOldBackupNewer] }, key);
  check(
    'a pre-binding backup row still cannot repair a row the device holds',
    soNewerPlan.totals.updated === 0 && soNewerPlan.totals.unauthenticated === 1
  );
  check(
    'but the innocent case is now counted apart, not just refused',
    soNewerPlan.totals.unverifiable === 1 && soNewerPlan.perTable.letters.unverifiable === 1
  );
  check(
    'and the sub-case that actually cost the user something is named: the file copy was NEWER',
    soNewerPlan.totals.unverifiableNewer === 1
  );
  const soOlderPlan = await new FakeVaultStore({ letters: [soLive] }).planBackupMerge(
    { letters: [soOldBackupOlder] },
    key
  );
  check(
    'an OLDER unverifiable row is unverifiable but not `unverifiableNewer` - nothing was lost',
    soOlderPlan.totals.unverifiable === 1 && soOlderPlan.totals.unverifiableNewer === 0
  );
  check(
    'the umbrella counter the preview already renders is unchanged',
    soOlderPlan.totals.unauthenticated === 1
  );

  const soCrossTable = await encryptRecord(
    { id: 'let-so', updatedAt: NOW + 120 * MINUTE, deleted: false, text: 'Sealed for bucketList' },
    key,
    { table: 'bucketList' }
  );
  check(
    'the smuggled row does carry a well-formed v2 header - that check alone was never enough',
    recordHasAuthenticatedHeader(soCrossTable) === true
  );
  const soHandBuiltStore = new FakeVaultStore({ letters: [soLive] });
  const soHandBuilt = await soHandBuiltStore.applyBackupMerge({
    writes: [{ table: 'letters', row: soCrossTable }],
    incomingWins: () => true,
  });
  check(
    'a hand-built plan with no key cannot overwrite an existing row at all',
    (soHandBuilt.written.letters || 0) === 0 && soHandBuilt.refusedSincePreview === 1
  );
  const soKeyedStore = new FakeVaultStore({ letters: [soLive] });
  const soKeyed = await soKeyedStore.applyBackupMerge({
    key,
    writes: [{ table: 'letters', row: soCrossTable }],
    incomingWins: () => true,
  });
  check(
    'and with a key the cross-table envelope is refused on its own merits',
    (soKeyed.written.letters || 0) === 0 && soKeyed.refusedSincePreview === 1
  );
  const soIntact = await decryptRecord(await soKeyedStore.table('letters').get('let-so'), key, {
    table: 'letters',
  });
  check('the live letter survived both hand-built plans', soIntact.content === 'On the device');

  const soHonestStore = new FakeVaultStore({ letters: [soLive] });
  const soHonestNewer = await encryptRecord(
    { id: 'let-so', updatedAt: NOW + 60 * MINUTE, deleted: false, content: 'A real newer copy' },
    key,
    { table: 'letters' }
  );
  const soHonestPlan = await soHonestStore.planBackupMerge({ letters: [soHonestNewer] }, key);
  check('a fully bound newer backup row still plans an update', soHonestPlan.totals.updated === 1);
  const soHonestApplied = await soHonestStore.applyBackupMerge(soHonestPlan);
  check(
    'and the real re-check lets it through',
    (soHonestApplied.written.letters || 0) === 1 && soHonestApplied.refusedSincePreview === 0
  );

  section('11nonies. A swapped photo under a bound envelope is flagged on READ');

  const snBytes = new Uint8Array(32).map((_, i) => (i * 7) % 256);
  const snBound = await encryptRecord(
    { id: 'mem-sn', updatedAt: NOW, deleted: false, caption: 'Bound on every dimension', imageBlob: snBytes },
    key,
    { table: 'memories' }
  );
  const snSwapped = { ...snBound, imageBlob: new Uint8Array(32).fill(9) };

  const snStore = new FakeVaultStore({ memories: [snSwapped] });
  const snRead = await snStore.getDecrypted('memories', 'mem-sn', key);
  check(
    'a fully bound row with swapped bytes reads as tampered',
    snRead._binaryTampered === true && snRead._headerTampered === true
  );
  check(
    'and listDecrypted reports it the same way rather than quietly dropping it',
    (await snStore.listDecrypted('memories', key)).some(
      (r) => r.id === 'mem-sn' && r._headerTampered === true
    )
  );
  check(
    'the row is left byte-identical, so every gate keeps refusing it too',
    eq(
      Array.from((await snStore.table('memories').get('mem-sn')).imageBlob),
      Array.from(snSwapped.imageBlob)
    )
  );
  const snSwapPlan = await new FakeVaultStore({ memories: [snBound] }).planBackupMerge(
    { memories: [snSwapped] },
    key
  );
  check('the import gate calls it tampered, not stale', snSwapPlan.totals.tampered === 1);

  const snCleanStore = new FakeVaultStore({ memories: [snBound] });
  const snClean = await snCleanStore.getDecrypted('memories', 'mem-sn', key);
  check(
    'the untouched row is not flagged',
    snClean._headerTampered === false &&
      snClean._binaryTampered === false &&
      snClean._binaryUnverified === false
  );

  section('11nonies. An id never comes to hold content this vault did not author');

  const spDonor = await encryptRecord(
    { id: 'sp-donor', updatedAt: NOW, deleted: false, note: 'harvested' },
    key,
    { table: 'letters' }
  );
  const spStore = new FakeVaultStore({});
  const spHostile = {
    id: 'sp-victim',
    updatedAt: NOW,
    deleted: false,
    v: 1,
    contentCipher: spDonor.ciphertext,
    contentIv: spDonor.iv,
  };
  const spPlan = await spStore.planBackupMerge({ letters: [spHostile] }, key);
  await spStore.applyBackupMerge(spPlan);
  check(
    'the chain cannot start: the hostile row is never created',
    spPlan.totals.added === 0 && (await spStore.table('letters').get('sp-victim')) === undefined
  );

  const spFresh = await spStore.putEncrypted(
    'letters',
    { id: 'sp-mine', updatedAt: NOW, deleted: false, content: 'Mine' },
    key
  );
  check('an ordinary write produces a fully sealed row', recordHasAuthenticatedHeader(spFresh) === true);
  const spFreshPlain = await decryptRecord(spFresh, key, { table: 'letters' });
  check(
    'sealed to its own table, so it cannot be replayed into another',
    spFreshPlain._tableUnverified === false && spFreshPlain._headerTampered === false
  );

  const spTomb = await spStore.softDelete('letters', 'sp-mine', key);
  check('a delete mints a sealed tombstone', recordHasAuthenticatedHeader(spTomb) === true);
  const spTombPlain = await decryptRecord(spTomb, key, { table: 'letters' });
  check(
    'bound to the id it is deleting and to nothing else',
    spTombPlain.deleted === true && spTombPlain.id === 'sp-mine' && spTombPlain._tableUnverified === false
  );

  const spPartner = new FakeVaultStore({
    letters: [
      await encryptRecord(
        { id: 'sp-mine', updatedAt: NOW, deleted: false, content: 'The real letter' },
        key,
        { table: 'letters' }
      ),
    ],
  });
  const spTombPlan = await spPartner.planBackupMerge({ letters: [spTomb] }, key);
  check(
    "THE POINT: a genuine delete now reaches the partner instead of being held back",
    spTombPlan.totals.deleted === 1
  );

  section('11decies. A same-instant delete is pulled instead of diverging forever');

  const dmLocal = [{ id: 'x1', updatedAt: NOW, deleted: false }];
  const dmRemoteDeleted = [{ id: 'x1', updatedAt: NOW, deleted: true }];

  const dmDiff = async (localRows, remoteRows) => {
    const saved = db.getManifest;
    db.getManifest = async () => ({ letters: localRows });
    try {
      return await peerSync._diffManifest({ letters: remoteRows });
    } finally {
      db.getManifest = saved;
    }
  };

  const dmPull = await dmDiff(dmLocal, dmRemoteDeleted);
  check(
    'a same-instant tombstone IS requested, so the deletion converges',
    dmPull.length === 1 && dmPull[0].id === 'x1'
  );

  const dmNoPull = await dmDiff(
    [{ id: 'x1', updatedAt: NOW, deleted: true }],
    [{ id: 'x1', updatedAt: NOW, deleted: false }]
  );
  check(
    'the reverse case asks for nothing - exactly one side pulls, so no ping-pong',
    dmNoPull.length === 0
  );

  const dmBothLive = await dmDiff(dmLocal, [{ id: 'x1', updatedAt: NOW, deleted: false }]);
  check('two same-instant edits still do not loop', dmBothLive.length === 0);

  const dmNewer = await dmDiff(dmLocal, [{ id: 'x1', updatedAt: NOW + 1000, deleted: false }]);
  check('a genuinely newer remote row is still requested', dmNewer.length === 1);

  section('11undecies. A tombstone written in bulk keeps its `_del` index mirror');

  const tsTomb = await encryptRecord(
    { id: 'ts-gone', updatedAt: NOW, deleted: true },
    key,
    { table: 'letters' }
  );
  check(
    'encryptRecord itself never emits `_del` - it must not reach an envelope',
    tsTomb._del === undefined
  );

  const tsLive = await encryptRecord(
    { id: 'ts-here', updatedAt: NOW, deleted: false, content: 'still here' },
    key,
    { table: 'letters' }
  );

  const tsStore = new FakeVaultStore({});
  check(
    'the write helper stamps a tombstone as 1',
    tsStore._withDelIndex({ ...tsTomb })._del === 1
  );
  check(
    'and a live row as 0, never undefined',
    tsStore._withDelIndex({ ...tsLive })._del === 0
  );

  const tsTarget = new FakeVaultStore({
    letters: [
      await encryptRecord(
        { id: 'ts-gone', updatedAt: NOW - MINUTE, deleted: false, content: 'about to go' },
        key,
        { table: 'letters' }
      ),
    ],
  });
  const tsPlan = await tsTarget.planBackupMerge({ letters: [tsTomb] }, key);
  await tsTarget.applyBackupMerge(tsPlan);
  const tsWritten = await tsTarget.table('letters').get('ts-gone');
  check(
    'a tombstone restored through applyBackupMerge is indexed as deleted',
    tsWritten.deleted === true && tsWritten._del === 1
  );

  section('11duodecies. A future clock does not permanently future-date this phone');

  const clkKey = 'sweetheart_sync_clock';
  const clkSavedRemote = peerSync._observedRemoteMax;
  const clkSavedIssued = peerSync._lastIssuedStamp;

  const clkHadLS = typeof globalThis.localStorage !== 'undefined';
  if (!clkHadLS) {
    const store = new Map();
    globalThis.localStorage = {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => store.set(k, String(v)),
      removeItem: (k) => store.delete(k),
    };
  }
  const clkSaved = (() => {
    try { return localStorage.getItem(clkKey); } catch { return null; }
  })();

  const YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  try {
    localStorage.setItem(clkKey, String(Date.now() + YEAR_MS));
    peerSync._observedRemoteMax = 0;
    peerSync._lastIssuedStamp = 0;

    const clkNow = Date.now();
    const clkStamp = peerSync.getSyncSafeTimestamp();
    check(
      'a year-ahead floor is clamped back to roughly now',
      clkStamp > clkNow - 1000 && clkStamp < clkNow + 60 * 1000
    );
    check(
      'and the poisoned value is not written back to storage',
      Number(localStorage.getItem(clkKey)) < clkNow + 60 * 1000
    );

    const DAY_MS = 24 * 60 * 60 * 1000;
    peerSync._observedRemoteMax = Date.now() + YEAR_MS;
    const clkStamp2 = peerSync.getSyncSafeTimestamp();
    check(
      'a far-future remote high-water mark is clamped to the wire ceiling, not obeyed',
      clkStamp2 <= Date.now() + DAY_MS + 1000 && clkStamp2 < Date.now() + 2 * DAY_MS
    );

    peerSync._observedRemoteMax = 0;
    const a = peerSync.getSyncSafeTimestamp();
    const b = peerSync.getSyncSafeTimestamp();
    check('stamps are still strictly increasing', b > a);
  } finally {
    peerSync._observedRemoteMax = clkSavedRemote;
    peerSync._lastIssuedStamp = clkSavedIssued;
    try {
      if (clkSaved === null) localStorage.removeItem(clkKey);
      else localStorage.setItem(clkKey, clkSaved);
    } catch {}
    if (!clkHadLS) delete globalThis.localStorage;
  }

  section('11terdecies. A cross-table row is spotted on read, not just on write');

  const xtRow = await encryptRecord(
    { id: 'xt-1', updatedAt: NOW, deleted: false, content: 'sealed for letters' },
    key,
    { table: 'letters' }
  );
  const xtStore = new FakeVaultStore({ bucketList: [xtRow], letters: [xtRow] });

  const xtHonest = await xtStore.getDecrypted('letters', 'xt-1', key);
  check(
    'read from the table it was sealed for: nothing flagged',
    xtHonest._tableTampered !== true && xtHonest._headerTampered !== true
  );

  const xtCross = await xtStore.getDecrypted('bucketList', 'xt-1', key);
  check(
    'read from a DIFFERENT table: flagged as tampered',
    xtCross._tableTampered === true && xtCross._headerTampered === true
  );

  const xtList = await xtStore.listDecrypted('bucketList', key);
  const xtListed = xtList.find((r) => r.id === 'xt-1');
  check(
    'listDecrypted flags it too, so screens can hide it',
    xtListed && xtListed._headerTampered === true
  );

  const xtUnbound = await encryptRecord(
    { id: 'xt-old', updatedAt: NOW, deleted: false, content: 'from an older build' },
    key
  );
  const xtOldStore = new FakeVaultStore({ letters: [xtUnbound] });
  const xtOld = await xtOldStore.getDecrypted('letters', 'xt-old', key);
  check(
    'a pre-binding row is unverified, NOT tampered, so it still shows',
    xtOld._tableUnverified === true && xtOld._headerTampered !== true
  );

  section('11quaterdecies. No read path may skip the sealed-table check');

  const { readdirSync, readFileSync, statSync } = await import('node:fs');
  const { join } = await import('node:path');

  const walkSrc = (dir) => {
    const out = [];
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) out.push(...walkSrc(full));
      else if (/\.(js|jsx)$/.test(entry)) out.push(full);
    }
    return out;
  };

  const stripComments = (src) =>
    src.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1 ');

  const callArgs = (src) => {
    const out = [];
    const needle = 'decryptRecord(';
    let at = src.indexOf(needle);
    while (at !== -1) {
      let depth = 0;
      let i = at + needle.length - 1;
      for (; i < src.length; i++) {
        if (src[i] === '(') depth++;
        else if (src[i] === ')') {
          depth--;
          if (depth === 0) break;
        }
      }
      out.push(src.slice(at + needle.length, i));
      at = src.indexOf(needle, i === -1 ? at + needle.length : i);
    }
    return out;
  };

  const TABLE_CHECK_SKIP = new Set([join('src', 'services', 'crypto.js')]);

  const offenders = [];
  for (const file of walkSrc('src')) {
    if (TABLE_CHECK_SKIP.has(file)) continue;
    for (const args of callArgs(stripComments(readFileSync(file, 'utf8')))) {
      if (!/\btable\b/.test(args)) {
        offenders.push(`${file} -> decryptRecord(${args.replace(/\s+/g, ' ').trim()})`);
      }
    }
  }

  check(
    'every decryptRecord() caller names its table — offenders: ' +
      (offenders.join(' | ') || 'none'),
    offenders.length === 0
  );

  section('11c. A backup whose origin cannot be established is `unknown`, not `same`');

  const healthyLocalRead = { ok: true, meta: { salt } };

  check(
    'a container with no vaultMeta at all is `unknown` against a HEALTHY local read',
    compareVaultIdentity(readBackupVaultIdentity({ bucketList: [] }), healthyLocalRead) === 'unknown'
  );
  check(
    'a vaultMeta row with a salt but no canary is `unknown` too, not `foreign`',
    compareVaultIdentity(
      readBackupVaultIdentity({ vaultMeta: [{ id: 'config', salt: foreignSalt }] }),
      healthyLocalRead
    ) === 'unknown'
  );
  check(
    'unknown is not silently collapsed into same',
    compareVaultIdentity(null, healthyLocalRead) !== 'same'
  );

  const unknownOriginStore = new FakeVaultStore();
  const mineButUnlabelled = await encryptRecord(
    { id: 'bkt-unknown-origin', updatedAt: NOW, deleted: false, text: 'Actually mine' },
    key
  );
  const theirsUnlabelled = await encryptRecord(
    { id: 'bkt-not-mine', updatedAt: NOW, deleted: false, text: 'Not mine' },
    foreignKey
  );
  const unknownPlan = await unknownOriginStore.planBackupMerge(
    { bucketList: [mineButUnlabelled, theirsUnlabelled] },
    key
  );
  check(
    'an unlabelled file still only writes rows that decrypt under the live key',
    unknownPlan.totals.added === 1 && unknownPlan.totals.undecryptable === 1
  );
  check(
    'and the one queued write is the row this vault actually authored',
    unknownPlan.writes.length === 1 && unknownPlan.writes[0].row.id === 'bkt-unknown-origin'
  );

  section("12. An older backup does not revert newer local work (peerSync's own rule)");

  const liveLetterA = await encryptRecord(
    { id: 'let-merge-a', updatedAt: NOW, deleted: false, title: 'Newer local edit' },
    key,
    { table: 'letters' }
  );
  const liveLetterB = await encryptRecord(
    { id: 'let-merge-b', updatedAt: NOW - 30 * MINUTE, deleted: false, title: 'Older local copy' },
    key,
    { table: 'letters' }
  );
  const backupLetterA = await encryptRecord(
    { id: 'let-merge-a', updatedAt: NOW - 60 * MINUTE, deleted: false, title: 'Stale backup copy' },
    key,
    { table: 'letters' }
  );
  const backupLetterB = await encryptRecord(
    { id: 'let-merge-b', updatedAt: NOW - 5 * MINUTE, deleted: false, title: 'Newer backup copy' },
    key,
    { table: 'letters' }
  );
  const backupLetterC = await encryptRecord(
    { id: 'let-merge-c', updatedAt: NOW - 90 * MINUTE, deleted: false, title: 'Only in the backup' },
    key,
    { table: 'letters' }
  );

  const mergeStore = new FakeVaultStore({ letters: [liveLetterA, liveLetterB] });
  const olderBackup = { letters: [backupLetterA, backupLetterB, backupLetterC] };

  const realIncomingWins = peerSync._incomingWins;
  let ruleCalls = 0;
  let mergePlan;
  try {
    peerSync._incomingWins = function spy(existing, incoming) {
      ruleCalls++;
      return realIncomingWins.call(this, existing, incoming);
    };
    mergePlan = await mergeStore.planBackupMerge(olderBackup, key);
  } finally {
    peerSync._incomingWins = realIncomingWins;
  }
  check(
    'planBackupMerge calls peerSync._incomingWins itself, once per collision',
    ruleCalls === 2
  );

  check('the stale backup row is counted stale', mergePlan.perTable.letters.stale === 1);
  check('the newer backup row is counted as an update', mergePlan.perTable.letters.updated === 1);
  check('the missing row is counted as an addition', mergePlan.perTable.letters.added === 1);
  check(
    'a same-vault backup produces no invalid or undecryptable rows',
    mergePlan.totals.invalid === 0 && mergePlan.totals.undecryptable === 0
  );
  check(
    'the stale row is never queued for writing',
    !mergePlan.writes.some((entry) => entry.row.id === 'let-merge-a')
  );

  await mergeStore.applyBackupMerge(mergePlan);
  const afterA = await decryptRecord(await mergeStore.table('letters').get('let-merge-a'), key);
  const afterB = await decryptRecord(await mergeStore.table('letters').get('let-merge-b'), key);
  const afterC = await decryptRecord(await mergeStore.table('letters').get('let-merge-c'), key);
  check('THE POINT: restoring an old backup did not revert the newer letter', afterA.title === 'Newer local edit');
  check('a genuinely newer backup copy does replace the local one', afterB.title === 'Newer backup copy');
  check('a letter only in the backup is restored', afterC.title === 'Only in the backup');

  const agrees = (existing, incoming) =>
    mergePlan.incomingWins(existing, incoming) === realIncomingWins.call(peerSync, existing, incoming);
  const tiedDeletion = { ...backupLetterA, updatedAt: liveLetterA.updatedAt, deleted: true };
  const tiedEdit = { ...backupLetterA, updatedAt: liveLetterA.updatedAt };
  check('plan and sync agree that a missing local row loses', agrees(undefined, backupLetterC));
  check('plan and sync agree on newer-wins', agrees(liveLetterB, backupLetterB));
  check('plan and sync agree on older-loses', agrees(liveLetterA, backupLetterA));
  check(
    'plan and sync agree that a same-instant deletion is not resurrected',
    agrees(liveLetterA, tiedDeletion) && mergePlan.incomingWins(liveLetterA, tiedDeletion) === true
  );
  check(
    'plan and sync break an exact tie the same way, and deterministically',
    agrees(liveLetterA, tiedEdit) &&
      mergePlan.incomingWins(liveLetterA, tiedEdit) !== mergePlan.incomingWins(tiedEdit, liveLetterA)
  );

  try {
    peerSync._incomingWins = undefined;
    await checkThrows(
      'the merge REFUSES to run when the sync rule cannot be loaded',
      async () => mergeStore.planBackupMerge(olderBackup, key),
      (err) => /which copy of a record is newer/.test(err.message)
    );
  } finally {
    peerSync._incomingWins = realIncomingWins;
  }
  await checkThrows(
    'the merge refuses to plan while the vault is locked (nothing can be verified)',
    async () => mergeStore.planBackupMerge(olderBackup, null),
    (err) => /locked/.test(err.message)
  );

  const raceStore = new FakeVaultStore();
  const racePlan = await raceStore.planBackupMerge({ letters: [backupLetterC] }, key);
  const arrivedMidPreview = await encryptRecord(
    { id: 'let-merge-c', updatedAt: NOW, deleted: false, title: 'Landed from the partner mid-preview' },
    key,
    { table: 'letters' }
  );
  await raceStore.table('letters').put(arrivedMidPreview);
  const raceApplied = await raceStore.applyBackupMerge(racePlan);
  check('a row superseded after the preview is reported, not silently written', raceApplied.supersededSincePreview === 1);
  check('and it is not counted as written', raceApplied.written.letters === 0);
  const raceRow = await decryptRecord(await raceStore.table('letters').get('let-merge-c'), key);
  check(
    'the copy that arrived during the preview survives the confirmation',
    raceRow.title === 'Landed from the partner mid-preview'
  );

  section('13. Rescue restore — adopt an identity, unlock with the ORIGINAL passphrase');

  const rescuePassphrase = 'the-passphrase-she-actually-remembers-2026';
  const filePassphrase = 'a-different-file-passphrase-entirely';
  const rescueSalt = generateSalt();
  const rescueKey = await deriveKeyFromPassphrase(rescuePassphrase, rescueSalt, {
    iterations: PBKDF2_ITERATIONS_CURRENT,
  });
  const rescueMeta = {
    id: 'config',
    salt: rescueSalt,
    kdfIterations: PBKDF2_ITERATIONS_CURRENT,
    updatedAt: NOW - 5 * MINUTE,
    ...(await createCanary(rescueKey, { coupleNames: 'Alex & Sam', startDate: '2021-06-14' })),
  };

  const rescuePhoto = new Uint8Array(512).map((_, i) => (i * 7) % 256);
  const sourceDevice = new FakeVaultStore({
    vaultMeta: [rescueMeta],
    memories: [
      await encryptRecord(
        {
          id: 'mem-rescue-1',
          updatedAt: NOW - 20 * MINUTE,
          deleted: false,
          caption: 'The morning we moved in',
          date: '2024-02-11',
          imageBlob: rescuePhoto,
        },
        rescueKey
      ),
    ],
    letters: [
      await encryptRecord(
        {
          id: 'let-rescue-1',
          updatedAt: NOW - 21 * MINUTE,
          deleted: false,
          title: 'For your thirtieth',
          content: 'Still yours.',
        },
        rescueKey
      ),
    ],
  });

  const exported = await sourceDevice.exportRawDataForBackup();
  check(
    'the export carries the vault identity, which is what makes rescue possible',
    Array.isArray(exported.tables.vaultMeta) && exported.tables.vaultMeta.length === 1
  );
  check(
    'a photo leaves as base64, not a live blob',
    typeof exported.tables.memories[0].imageBlobBase64 === 'string' &&
      exported.tables.memories[0].imageBlob === undefined
  );

  const rescueContainer = await createEncryptedBackup(exported, filePassphrase);
  const reopened = await decryptBackupContainer(rescueContainer, filePassphrase);
  const rescueIdentity = readBackupVaultIdentity(reopened.tables);
  check(
    'the identity survives the container round-trip intact',
    rescueIdentity.salt === rescueSalt &&
      rescueIdentity.canary === rescueMeta.canary &&
      rescueIdentity.kdfIterations === PBKDF2_ITERATIONS_CURRENT
  );
  check(
    'TWO PASSPHRASES: the file passphrase does NOT open the vault it contains',
    (await verifyPassphraseAgainstMeta(filePassphrase, rescueIdentity)) === false
  );
  check(
    "the vault passphrase is proved against the backup's own canary before any write",
    (await verifyPassphraseAgainstMeta(rescuePassphrase, rescueIdentity)) === true
  );
  check(
    'a container with no vaultMeta cannot be used to restore an identity',
    readBackupVaultIdentity({ letters: [] }) === null
  );
  check(
    'a vaultMeta row with no canary is refused: the passphrase could not be proved',
    readBackupVaultIdentity({ vaultMeta: [{ id: 'config', salt: rescueSalt }] }) === null
  );

  const derived = await deriveKeyWithVerification(
    rescuePassphrase,
    rescueIdentity.salt,
    async (candidate) => (await readCanary(candidate, rescueIdentity)) !== null,
    { iterations: rescueIdentity.kdfIterations }
  );

  const freshDevice = new FakeVaultStore();
  const emptyRead = await freshDevice.readVaultIdentity();
  check('a blank device reports ok:true with no vault', emptyRead.ok === true && emptyRead.meta === null);
  freshDevice.failReads = true;
  const brokenRead = await freshDevice.readVaultIdentity();
  check(
    'a FAILED read reports ok:false — never "there is nothing here to lose"',
    brokenRead.ok === false && brokenRead.meta === null && brokenRead.error instanceof Error
  );
  check(
    'and that failure is `unknown` to compareVaultIdentity, so callers stop',
    compareVaultIdentity(rescueIdentity, brokenRead) === 'unknown'
  );
  freshDevice.failReads = false;

  await freshDevice.restoreVaultIdentity({ ...rescueIdentity, kdfIterations: derived.iterations });
  const adopted = (await freshDevice.readVaultIdentity()).meta;
  check('the adopted row carries the salt', adopted.salt === rescueSalt);
  check(
    'the adopted row carries the canary pair',
    adopted.canary === rescueIdentity.canary && adopted.canaryIv === rescueIdentity.canaryIv
  );
  check(
    'the adopted row records the count that actually worked',
    adopted.kdfIterations === PBKDF2_ITERATIONS_CURRENT
  );

  const coldUnlock = await deriveKeyWithVerification(
    rescuePassphrase,
    adopted.salt,
    async (candidate) => (await readCanary(candidate, adopted)) !== null,
    { iterations: adopted.kdfIterations }
  );
  const coldPayload = await readCanary(coldUnlock.key, adopted);
  check('the ORIGINAL vault passphrase unlocks the rescued device', coldPayload.coupleNames === 'Alex & Sam');
  check('and the couple config comes back with it', coldPayload.startDate === '2021-06-14');
  await checkThrows(
    'a wrong passphrase is still refused on the rescued device',
    async () =>
      deriveKeyWithVerification(
        'not-the-vault-passphrase-at-all',
        adopted.salt,
        async (candidate) => (await readCanary(candidate, adopted)) !== null,
        { iterations: adopted.kdfIterations }
      ),
    (err) => /Incorrect passphrase/.test(err.message)
  );

  const restorePlan = await freshDevice.planBackupMerge(reopened.tables, coldUnlock.key);
  check(
    'every record in the rescue file is accepted by the re-derived key',
    restorePlan.totals.added === 2 &&
      restorePlan.totals.undecryptable === 0 &&
      restorePlan.totals.invalid === 0
  );
  check('the identity table is not merged as ordinary data', restorePlan.skippedTables.includes('vaultMeta'));
  await freshDevice.applyBackupMerge(restorePlan);
  const restoredMemory = await decryptRecord(
    await freshDevice.table('memories').get('mem-rescue-1'),
    coldUnlock.key
  );
  check('a rescued photo caption is readable again', restoredMemory.caption === 'The morning we moved in');
  check('a rescued photo date survived inside the envelope', restoredMemory.date === '2024-02-11');
  check(
    'the rescued photo bytes survived base64 and back, byte for byte',
    eq(Array.from(restoredMemory.imageBlob), Array.from(rescuePhoto))
  );
  const restoredLetter = await decryptRecord(
    await freshDevice.table('letters').get('let-rescue-1'),
    coldUnlock.key
  );
  check('a rescued letter is readable again', restoredLetter.content === 'Still yours.');

  const uncountedRescueRow = {
    id: 'config',
    salt: uncountedSalt,
    canary: uncountedMeta.canary,
    canaryIv: uncountedMeta.canaryIv,
  };
  const uncountedIdentity = readBackupVaultIdentity({ vaultMeta: [uncountedRescueRow] });
  check(
    'a backup with no recorded count is read as a 600,000-iteration vault',
    uncountedIdentity.kdfIterations === PBKDF2_ITERATIONS_CURRENT
  );
  const uncountedDevice = new FakeVaultStore();
  await uncountedDevice.restoreVaultIdentity(uncountedIdentity);
  const uncountedAdopted = (await uncountedDevice.readVaultIdentity()).meta;
  check(
    'the adopted row writes the count down, so the next unlock is one PBKDF2 run',
    uncountedAdopted.kdfIterations === PBKDF2_ITERATIONS_CURRENT
  );
  check(
    'and the original passphrase opens the rescued vault',
    (await readCanary(uncountedKey, uncountedAdopted)) !== null
  );

  section('14. Import sanitising — a restored clock artefact must not win forever');

  const SKEW_LIMIT = 24 * 60 * 60 * 1000;
  const clockOk = await encryptRecord(
    { id: 'bkt-clock-ok', updatedAt: NOW + 60 * MINUTE, deleted: false, text: 'Written on a slightly fast phone' },
    key
  );
  const clockNegative = await encryptRecord(
    { id: 'bkt-clock-negative', updatedAt: -1, deleted: false, text: 'Stamped before the epoch' },
    key
  );
  const clockFuture = await encryptRecord(
    {
      id: 'bkt-clock-future',
      updatedAt: NOW + SKEW_LIMIT + 60 * MINUTE,
      deleted: false,
      text: 'Stamped in the far future',
    },
    key
  );
  const badVersion = {
    ...(await encryptRecord({ id: 'bkt-bad-version', updatedAt: NOW, deleted: false, text: 'x' }, key)),
    v: 3,
  };
  const badId = {
    ...(await encryptRecord({ id: 'bkt-bad-id', updatedAt: NOW, deleted: false, text: 'x' }, key)),
    id: '',
  };

  const planOne = async (record) =>
    (await new FakeVaultStore().planBackupMerge({ bucketList: [record] }, key)).totals;

  const negativeTotals = await planOne(clockNegative);
  check(
    'a negative updatedAt is refused at the STRUCTURE gate',
    negativeTotals.invalid === 1 && negativeTotals.added === 0 && negativeTotals.undecryptable === 0
  );
  const futureTotals = await planOne(clockFuture);
  check(
    'an updatedAt past the skew ceiling is refused at the STRUCTURE gate',
    futureTotals.invalid === 1 && futureTotals.added === 0 && futureTotals.undecryptable === 0
  );
  check(
    'WHY: either stamp, if restored, would beat every real edit forever',
    peerSync._incomingWins(liveBucket, clockNegative) === false &&
      peerSync._incomingWins(liveBucket, clockFuture) === true
  );
  check('an unknown schema version is refused', (await planOne(badVersion)).invalid === 1);
  check('an empty id is refused', (await planOne(badId)).invalid === 1);
  check(
    'a plausible fast clock (+1h) is still accepted — the gate is a ceiling, not a ban',
    (await planOne(clockOk)).added === 1
  );

  const clockStore = new FakeVaultStore();
  const clockPlan = await clockStore.planBackupMerge(
    { bucketList: [clockOk, clockNegative, clockFuture, badVersion, badId] },
    key
  );
  check(
    'in a mixed file the four bad rows are dropped and the good one is kept',
    clockPlan.totals.invalid === 4 && clockPlan.totals.added === 1
  );
  check(
    'only the acceptable row is queued',
    clockPlan.writes.length === 1 && clockPlan.writes[0].row.id === 'bkt-clock-ok'
  );

  const clockThirtyHours = await encryptRecord(
    {
      id: 'bkt-clock-30h',
      updatedAt: NOW + 30 * 60 * MINUTE,
      deleted: false,
      text: 'Thirty hours ahead',
    },
    key
  );
  check(
    'a +30h stamp is refused on the IMPORT path',
    (await planOne(clockThirtyHours)).invalid === 1
  );
  check(
    'and on the WIRE path, for the same reason and with the same verdict',
    peerSync._validateWireRecord(clockThirtyHours).code === 'future_timestamp'
  );
  check(
    'while a +1h stamp is accepted by BOTH, so the ceiling is still a ceiling',
    (await planOne(clockOk)).added === 1 && peerSync._validateWireRecord(clockOk).ok === true
  );

  section('15. One tampered record does not poison the rest of the restore');

  const goodOne = await encryptRecord(
    { id: 'mem-intact-1', updatedAt: NOW - 3 * MINUTE, deleted: false, caption: 'Intact one' },
    key
  );
  const goodTwo = await encryptRecord(
    { id: 'mem-intact-2', updatedAt: NOW - 2 * MINUTE, deleted: false, caption: 'Intact two' },
    key
  );
  const goodThree = await encryptRecord(
    { id: 'mem-intact-3', updatedAt: NOW - 1 * MINUTE, deleted: false, caption: 'Intact three' },
    key
  );
  const victim = await encryptRecord(
    { id: 'mem-tampered', updatedAt: NOW - 4 * MINUTE, deleted: false, caption: 'Header rewritten' },
    key
  );
  const headerTampered = { ...victim, updatedAt: victim.updatedAt + 5000 };
  const corrupted = {
    ...(await encryptRecord({ id: 'mem-corrupt', updatedAt: NOW - 5 * MINUTE, deleted: false, caption: 'Bit rot' }, key)),
  };
  corrupted.ciphertext =
    corrupted.ciphertext.slice(0, -8) + (corrupted.ciphertext.slice(-8) === 'AAAAAAAA' ? 'BBBBBBBB' : 'AAAAAAAA');

  check(
    'the tampered row DOES decrypt — it is caught by _headerTampered, not by GCM',
    (await decryptRecord(headerTampered, key))._headerTampered === true
  );

  const tamperStore = new FakeVaultStore();
  const tamperPlan = await tamperStore.planBackupMerge(
    { memories: [goodOne, headerTampered, goodTwo, corrupted, goodThree] },
    key
  );
  check('the three intact records are still accepted', tamperPlan.totals.added === 3);
  check(
    'the tampered and the corrupt rows are both refused',
    tamperPlan.totals.undecryptable + tamperPlan.totals.tampered === 2 &&
      tamperPlan.totals.invalid === 0
  );
  check(
    'and they are counted apart: the rewritten header is `tampered`, the bit rot `undecryptable`',
    tamperPlan.totals.tampered === 1 && tamperPlan.totals.undecryptable === 1
  );
  check(
    'a bad record does not abort the merge for the good ones',
    tamperPlan.writes.length === 3 &&
      eq(
        tamperPlan.writes.map((entry) => entry.row.id).sort(),
        ['mem-intact-1', 'mem-intact-2', 'mem-intact-3']
      )
  );

  await tamperStore.applyBackupMerge(tamperPlan);
  check(
    'the tampered record was never written',
    (await tamperStore.table('memories').get('mem-tampered')) === undefined &&
      (await tamperStore.table('memories').get('mem-corrupt')) === undefined
  );
  const survivor = await decryptRecord(await tamperStore.table('memories').get('mem-intact-2'), key);
  check('and the intact ones landed, readable', survivor.caption === 'Intact two');

  section('15b. ICE servers: somewhere to fall back to');

  const ice = await import('./src/services/iceServers.js');

  const iceDefault = ice.buildIceServers({});
  check(
    'STUN comes first and is never replaced by configuration',
    iceDefault[0].urls.startsWith('stun:')
  );
  check(
    'a relay is present by default, so mobile-data-to-mobile-data can still work',
    ice.hasTurnConfigured({}) === true
  );
  check(
    'and it is last, so ICE only reaches for it when nothing direct worked',
    (() => {
      const last = iceDefault[iceDefault.length - 1];
      return Array.isArray(last.urls) && last.urls.every((u) => u.startsWith('turn'));
    })()
  );
  check(
    'every relay entry carries credentials - one without them is silently useless',
    iceDefault
      .filter((s) => String(s.urls).includes('turn:') || String(s.urls).includes('turns:'))
      .every((s) => !!s.username && !!s.credential)
  );

  const iceOwn = ice.resolveTurnConfig({
    VITE_TURN_URLS: 'turn:my.relay:3478, turns:my.relay:5349',
    VITE_TURN_USERNAME: 'me',
    VITE_TURN_CREDENTIAL: 'secret',
  });
  check(
    'a complete override replaces the public default',
    eq(iceOwn.urls, ['turn:my.relay:3478', 'turns:my.relay:5349']) &&
      iceOwn.username === 'me'
  );

  const iceHalf = ice.resolveTurnConfig({ VITE_TURN_URLS: 'turn:my.relay:3478' });
  check(
    'a half-configured relay is ignored rather than half-applied',
    iceHalf.username === 'openrelayproject'
  );

  section('16. Love bursts survive a partner who is not listening');

  const burstStore = new FakeVaultStore();
  const burstLocal = new Map();
  Object.defineProperty(globalThis, 'localStorage', {
    value: {
      getItem: (k) => (burstLocal.has(k) ? burstLocal.get(k) : null),
      setItem: (k, v) => burstLocal.set(k, String(v)),
      removeItem: (k) => burstLocal.delete(k),
    },
    configurable: true,
    writable: true,
  });

  const bursts = await import('./src/services/loveBursts.js');
  let burstClock = 1700000000000;
  const burstOpts = { store: burstStore, timestamp: () => (burstClock += 1000) };

  const burstRow1 = await bursts.sendLoveBurst(key, burstOpts);
  check(
    'a burst can be sent with no connection at all - it is just a write',
    burstRow1 && typeof burstRow1.id === 'string'
  );
  check(
    'and it is sealed like every other record, not stored in the clear',
    recordHasAuthenticatedHeader(burstRow1) &&
      burstRow1.count === undefined &&
      burstRow1.ciphertext !== undefined
  );

  const burstMine = await burstStore.getDecrypted(
    bursts.LOVE_BURST_TABLE,
    bursts.ownBurstRecordId(),
    key
  );
  check('the first burst leaves a tally of one', burstMine.count === 1);

  await bursts.sendLoveBurst(key, burstOpts);
  await bursts.sendLoveBurst(key, burstOpts);
  const burstMine3 = await burstStore.getDecrypted(
    bursts.LOVE_BURST_TABLE,
    bursts.ownBurstRecordId(),
    key
  );
  check('three taps make one record, not three', burstMine3.count === 3);
  check(
    'the whole table is still one row - this is what keeps sync manifests small',
    (await burstStore.table(bursts.LOVE_BURST_TABLE).toArray()).length === 1
  );

  const burstOwn = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('a device never celebrates its own tally', burstOwn.total === 0);

  const HER_ID = 'burst-her-device-tag';
  const putHerTally = async (count, lastSentAt) => {
    const row = await encryptRecord(
      { id: HER_ID, count, lastSentAt, updatedAt: (burstClock += 1000) },
      key,
      { table: bursts.LOVE_BURST_TABLE }
    );
    await burstStore.table(bursts.LOVE_BURST_TABLE).put(row);
    return row;
  };

  await putHerTally(3, burstClock);

  burstLocal.delete('sweetheart_burst_seen_v1');
  const burstFirstLook = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'a first look adopts the tally where it stands instead of replaying history',
    burstFirstLook.total === 0
  );

  await putHerTally(6, burstClock);
  const burstAway = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'three bursts sent while the app was closed are all counted on return',
    burstAway.total === 3
  );
  check(
    'and the wording says so',
    bursts.describeBursts(burstAway.total, false) ===
      'Your partner sent you 3 love bursts while you were away 💕'
  );
  check(
    'while a live one reads as happening now',
    bursts.describeBursts(1, true) === 'Your partner sent you a love burst! 💕'
  );

  check(
    'a burst says who it came from',
    bursts.describeBursts(1, true, 'Noor') === 'Noor sent you a love burst! 💕'
  );
  check(
    'including one that arrived while they were away',
    bursts.describeBursts(3, false, 'Noor') ===
      'Noor sent you 3 love bursts while you were away 💕'
  );
  check(
    'a blank name falls back rather than leaving a gap',
    bursts.describeBursts(1, true, '   ') === 'Your partner sent you a love burst! 💕'
  );
  check(
    'and so does a name that is not a string',
    bursts.describeBursts(1, true, { evil: true }) === 'Your partner sent you a love burst! 💕'
  );
  check('no bursts is still no sentence', bursts.describeBursts(0, true, 'Noor') === '');

  bursts.markBurstsSeen(burstAway.records);
  const burstAgain = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('once shown, the same bursts are not counted again', burstAgain.total === 0);

  await putHerTally(7, burstClock);
  const burstOneMore = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('but the next one still lands', burstOneMore.total === 1);
  bursts.markBurstsSeen(burstOneMore.records);

  await putHerTally(2, burstClock);
  const burstBackwards = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'a tally that somehow went backwards is ignored, not counted as negative',
    burstBackwards.total === 0
  );

  await putHerTally(50, burstClock);
  const burstHonest = await burstStore.table(bursts.LOVE_BURST_TABLE).get(HER_ID);
  await burstStore
    .table(bursts.LOVE_BURST_TABLE)
    .put({ ...burstHonest, updatedAt: burstHonest.updatedAt + 5000 });
  const burstTampered = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'a burst tally whose header was rewritten is refused, like every other record',
    burstTampered.total === 0
  );

  section('17. Quick unlock: sealing the vault key behind the phone sensor');

  const bioB64 = (bytes) => Buffer.from(bytes).toString('base64');

  const bioOpens = async (sealed, key) => {
    try {
      return await decryptText(sealed.ciphertext, sealed.iv, key);
    } catch {
      return null;
    }
  };

  async function fakePrf(secret, saltBytes) {
    const k = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    return await crypto.subtle.sign('HMAC', k, saltBytes);
  }

  function makeFakeAuthenticator() {
    const secrets = new Map();
    let counter = 0;
    let dismiss = false;
    let withholdPrf = false;
    let denyPrfAtCreate = false;
    const counts = { create: 0, get: 0 };

    const refuse = () => {
      const err = new Error('dismissed');
      err.name = 'NotAllowedError';
      return err;
    };

    return {
      secrets,
      counts,
      dismissNext(v) {
        dismiss = v;
      },
      denyPrfAtCreateNext(v) {
        denyPrfAtCreate = v;
      },
      withholdPrfNext(v) {
        withholdPrf = v;
      },
      credentials: {
        async create() {
          counts.create += 1;
          if (dismiss) throw refuse();
          counter += 1;
          const rawId = new Uint8Array(16);
          rawId[0] = counter;
          const secret = crypto.getRandomValues(new Uint8Array(32));
          secrets.set(bioB64(rawId), secret);
          if (denyPrfAtCreate) {
            return {
              rawId: rawId.buffer,
              response: { getTransports: () => ['internal'] },
              getClientExtensionResults: () => ({ prf: { enabled: false } }),
            };
          }
          return {
            rawId: rawId.buffer,
            response: { getTransports: () => ['internal'] },
            getClientExtensionResults: () => ({ prf: { enabled: true } }),
          };
        },
        async get({ publicKey }) {
          counts.get += 1;
          if (dismiss) throw refuse();
          const id = bioB64(new Uint8Array(publicKey.allowCredentials[0].id));
          const secret = secrets.get(id);
          if (!secret) throw refuse();
          if (withholdPrf) {
            return { getClientExtensionResults: () => ({ prf: { enabled: false } }) };
          }
          const first = await fakePrf(secret, publicKey.extensions.prf.eval.first);
          return { getClientExtensionResults: () => ({ prf: { results: { first } } }) };
        },
      },
    };
  }

  const bioStore = new Map();
  const retired = [];
  const fakeAuth = makeFakeAuthenticator();

  const define = (name, value) =>
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });

  define('window', {
    isSecureContext: true,
    crypto: globalThis.crypto,
    btoa: globalThis.btoa,
    atob: globalThis.atob,
    location: { hostname: 'localhost' },
    PublicKeyCredential: {
      isUserVerifyingPlatformAuthenticatorAvailable: async () => true,
      signalUnknownCredential: async (options) => {
        retired.push(options);
      },
    },
  });
  define('localStorage', {
    getItem: (k) => (bioStore.has(k) ? bioStore.get(k) : null),
    setItem: (k, v) => bioStore.set(k, String(v)),
    removeItem: (k) => bioStore.delete(k),
  });
  define('navigator', { credentials: fakeAuth.credentials });

  const bio = await import('./src/services/biometricUnlock.js');

  const bioPass = 'quick-unlock-passphrase-16';
  const bioSalt = generateSalt();
  const bioIters = 2000;

  const bioBits = await deriveVaultKeyBits(bioPass, bioSalt, { iterations: bioIters });
  const bioFromBits = await importVaultKeyFromBits(bioBits);
  const bioFromPass = await deriveKeyFromPassphrase(bioPass, bioSalt, { iterations: bioIters });

  const bioProbe = await encryptText('same key or not', bioFromBits);
  check(
    'deriveVaultKeyBits produces the same key as deriveKeyFromPassphrase',
    (await decryptText(bioProbe.ciphertext, bioProbe.iv, bioFromPass)) === 'same key or not'
  );
  check('importVaultKeyFromBits returns a NON-extractable key', bioFromBits.extractable === false);
  await checkThrows(
    'importVaultKeyFromBits rejects key material of the wrong size',
    () => importVaultKeyFromBits(new Uint8Array(16))
  );

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  check('enableBiometricUnlock stores a sealed record', bioStore.size === 1);

  const bioRaw = Array.from(bioStore.values())[0];
  check(
    'the stored record does not contain the passphrase',
    !bioRaw.includes(bioPass) && !bioRaw.includes(normalizePassphrase(bioPass))
  );

  const bioOpened = await bio.unlockWithBiometric(bioSalt);
  const bioSecret = await encryptText('a letter only the vault key opens', bioFromPass);
  check(
    'unlockWithBiometric returns a key that opens real vault ciphertext',
    (await bioOpens(bioSecret, bioOpened.key)) === 'a letter only the vault key opens'
  );
  check('the unsealed key is NON-extractable too', bioOpened.key.extractable === false);
  check('the vault iteration count survives the round trip', bioOpened.iterations === bioIters);
  check('isBiometricEnrolled agrees for this salt', bio.isBiometricEnrolled(bioSalt) === true);

  fakeAuth.dismissNext(true);
  await checkThrows(
    'a dismissed prompt reports cancelled, not failure',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'cancelled'
  );
  fakeAuth.dismissNext(false);
  check(
    'a dismissed prompt leaves the enrolment intact',
    bio.isBiometricEnrolled(bioSalt) === true && bioStore.size === 1
  );

  const bioOtherSalt = generateSalt();
  await checkThrows(
    'a sealed key refuses a different vault salt',
    () => bio.unlockWithBiometric(bioOtherSalt),
    (err) => err.code === 'stale'
  );
  check(
    'and clears itself, because it can never be useful again',
    bioStore.size === 0 && bio.isBiometricEnrolled(bioSalt) === false
  );

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  const bioKey = Array.from(bioStore.keys())[0];
  const bioRecord = JSON.parse(bioStore.get(bioKey));
  const bioFlipped = new Uint8Array(base64ToBuffer(bioRecord.wrapped));
  bioFlipped[0] ^= 0xff;
  bioStore.set(bioKey, JSON.stringify({ ...bioRecord, wrapped: bufferToBase64(bioFlipped) }));

  await checkThrows(
    'a flipped byte in the sealed key fails its auth tag',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'stale'
  );
  check('a tampered record is cleared rather than retried forever', bioStore.size === 0);

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  for (const id of fakeAuth.secrets.keys()) {
    fakeAuth.secrets.set(id, crypto.getRandomValues(new Uint8Array(32)));
  }
  await checkThrows(
    'the sealed key is useless to a different authenticator',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'stale'
  );

  const bioRawPass = 'trailing-space-passphrase ';
  const bioRawSalt = generateSalt();
  const bioRawKey = await deriveKeyFromPassphrase(bioRawPass, bioRawSalt, {
    iterations: bioIters,
    normalize: false,
  });
  check(
    'the raw and normalised forms of that passphrase really do differ',
    normalizePassphrase(bioRawPass) !== bioRawPass
  );

  await bio.enableBiometricUnlock({
    passphrase: bioRawPass,
    vaultSalt: bioRawSalt,
    iterations: bioIters,
    normalize: false,
  });
  const bioRawOpened = await bio.unlockWithBiometric(bioRawSalt);
  const bioRawSecret = await encryptText('keyed on the raw string', bioRawKey);
  check(
    'normalize:false seals the bits the vault was actually built with',
    (await bioOpens(bioRawSecret, bioRawOpened.key)) === 'keyed on the raw string'
  );

  bio.forgetBiometricUnlock();
  fakeAuth.withholdPrfNext(true);
  await checkThrows(
    'a passkey store that verifies but returns no PRF reports no-prf',
    () =>
      bio.enableBiometricUnlock({
        passphrase: bioPass,
        vaultSalt: bioSalt,
        iterations: bioIters,
        normalize: true,
      }),
    (err) => err.code === 'no-prf'
  );
  check(
    'a failed enrolment writes nothing at all',
    bioStore.size === 0 && bio.isBiometricEnrolled(bioSalt) === false
  );
  fakeAuth.withholdPrfNext(false);

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  const bioStored = JSON.parse(Array.from(bioStore.values())[0]);
  check(
    'the credential transports are stored, so unlock can skip the chooser',
    eq(bioStored.transports, ['internal'])
  );

  bio.forgetBiometricUnlock();
  retired.length = 0;
  fakeAuth.counts.create = 0;
  fakeAuth.counts.get = 0;
  fakeAuth.denyPrfAtCreateNext(true);

  await checkThrows(
    'a create() that reports prf.enabled:false reports no-prf',
    () =>
      bio.enableBiometricUnlock({
        passphrase: bioPass,
        vaultSalt: bioSalt,
        iterations: bioIters,
        normalize: true,
      }),
    (err) => err.code === 'no-prf'
  );
  check(
    'and does NOT spend a second fingerprint prompt to be told the same thing',
    fakeAuth.counts.create === 1 && fakeAuth.counts.get === 0
  );
  check(
    'the passkey it just made is retired, not left in the password manager',
    retired.length === 1
  );
  fakeAuth.denyPrfAtCreateNext(false);

  check(
    'the retired credential id carries no +, / or = padding',
    retired.length === 1 && !/[+/=]/.test(retired[0].credentialId)
  );
  check(
    'and it names the right relying party',
    retired.length === 1 && retired[0].rpId === 'localhost'
  );

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  const bioMalformedKey = Array.from(bioStore.keys())[0];
  const bioMalformed = JSON.parse(bioStore.get(bioMalformedKey));
  bioStore.set(
    bioMalformedKey,
    JSON.stringify({ ...bioMalformed, wrapped: 'not valid base64 !!!' })
  );
  check(
    'a record with an undecodable field reads as never set up',
    bio.isBiometricEnrolled(bioSalt) === false
  );
  await checkThrows(
    'and unlocking says so rather than failing forever',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'stale'
  );

  bio.forgetBiometricUnlock();
  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });

  const bioRealCrypto = globalThis.crypto;
  globalThis.window.crypto = {
    getRandomValues: (a) => bioRealCrypto.getRandomValues(a),
    subtle: {
      importKey: (...a) => bioRealCrypto.subtle.importKey(...a),
      deriveKey: (...a) => bioRealCrypto.subtle.deriveKey(...a),
      deriveBits: (...a) => bioRealCrypto.subtle.deriveBits(...a),
      encrypt: (...a) => bioRealCrypto.subtle.encrypt(...a),
      sign: (...a) => bioRealCrypto.subtle.sign(...a),
      decrypt: async () => {
        throw new TypeError('simulated transient failure, not a bad auth tag');
      },
    },
  };

  await checkThrows(
    'a non-OperationError during unseal reports failed, not stale',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'failed'
  );
  globalThis.window.crypto = bioRealCrypto;
  check(
    'and leaves the enrolment alone, because nothing proved it was dead',
    bio.isBiometricEnrolled(bioSalt) === true
  );

  bio.forgetBiometricUnlock();
  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  const bioOldId = JSON.parse(Array.from(bioStore.values())[0]).credentialId;

  const bioNewVaultSalt = generateSalt();
  retired.length = 0;
  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioNewVaultSalt,
    iterations: bioIters,
    normalize: true,
  });

  check(
    'setting up for a new space succeeds instead of being refused as a duplicate',
    bio.isBiometricEnrolled(bioNewVaultSalt) === true
  );
  check(
    'and the stranded passkey is retired rather than left behind',
    retired.some(
      (r) =>
        r.credentialId === bioOldId.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
    )
  );
  check(
    'exactly one enrolment record survives, not two',
    bioStore.size === 1
  );

  retired.length = 0;
  const bioLiveId = JSON.parse(Array.from(bioStore.values())[0]).credentialId;
  bio.forgetBiometricUnlock();
  check(
    'turning quick unlock off retires its passkey rather than orphaning it',
    retired.length === 1 &&
      retired[0].credentialId === bioLiveId.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  );

  bio.forgetBiometricUnlock();
  check(
    'forgetBiometricUnlock leaves nothing behind',
    bioStore.size === 0 && bio.isBiometricEnrolled(bioRawSalt) === false
  );
  await checkThrows(
    'and unlocking afterwards reports it is simply not set up',
    () => bio.unlockWithBiometric(bioRawSalt),
    (err) => err.code === 'stale'
  );


  section('18. The daily question: same question, both phones, no server');

  const dq = await import('./src/services/dailyQuestion.js');
  const bank = await import('./src/data/dailyQuestions.js');

  const dqIds = bank.ALL_QUESTIONS.map((x) => x.id);
  check('every question has a unique id', new Set(dqIds).size === dqIds.length);
  check(
    'and no two questions are the same text',
    new Set(bank.ALL_QUESTIONS.map((x) => x.text)).size === bank.ALL_QUESTIONS.length
  );
  check(
    'every question is a real prompt, not a placeholder',
    bank.ALL_QUESTIONS.every(
      (x) => x.text.length > 20 && /[?.]$/.test(x.text.trim()) && !/TODO|FIXME|xxx/i.test(x.text)
    )
  );

  const dqHerKey = await fastKey(passphrase, salt);
  const dqDay = new Date('2026-09-10T09:00:00Z');

  const dqHis = await dq.getQuestionForDay(key, dqDay);
  const dqHers = await dq.getQuestionForDay(dqHerKey, dqDay);
  check(
    'two devices holding the same key land on the same question, with no sync',
    dqHis.question.id === dqHers.question.id
  );
  check(
    'and on the same day string',
    dqHis.day === dqHers.day && dqHis.day === '2026-09-10'
  );

  const dqStranger = await deriveKeyFromPassphrase(
    'a completely different couple passphrase',
    generateSalt(),
    { iterations: 2000 }
  );
  const dqOther = await dq.getQuestionForDay(dqStranger, dqDay);
  const dqOrderMine = await dq.buildQuestionOrder(key);
  const dqOrderOther = await dq.buildQuestionOrder(dqStranger);
  check(
    'a different vault gets a different order entirely',
    !dqOrderMine.every((x, i) => x.id === dqOrderOther[i].id)
  );
  void dqOther;

  const dqSeen = new Set();
  const dqStart = dq.dayIndex(dqDay);
  for (let i = 0; i < dqOrderMine.length; i++) {
    const when = (dqStart + i) * 86400000;
    dqSeen.add((await dq.getQuestionForDay(key, when)).question.id);
  }
  check(
    'walking a full cycle asks every question exactly once - no repeats at all',
    dqSeen.size === dqOrderMine.length
  );

  const dqBatchTwo = {
    id: 'b2',
    questions: Array.from({ length: 40 }, (_, i) => ({
      id: 'b2-' + i,
      tone: 'light',
      text: 'A later question number ' + i + '?',
    })),
  };
  const dqBefore = await dq.buildQuestionOrder(key, bank.QUESTION_BATCHES);
  const dqAfter = await dq.buildQuestionOrder(key, [...bank.QUESTION_BATCHES, dqBatchTwo]);
  check(
    'adding a batch leaves the existing order byte-for-byte where it was',
    dqBefore.every((x, i) => x.id === dqAfter[i].id)
  );
  check(
    'and the new questions land after it, never in the middle',
    dqAfter.slice(dqBefore.length).every((x) => x.id.startsWith('b2-'))
  );

  const dqStore = new FakeVaultStore();
  const HIM = 'him-device';
  const HER = 'her-device';
  let dqClock = 1700000000000;
  const dqOpts = { store: dqStore, timestamp: () => (dqClock += 1000) };

  const dqRow = await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HIM,
    questionId: dqHis.question.id,
    text: 'The thing I never say out loud.',
    when: dqDay,
    ...dqOpts,
  });
  check(
    'an answer is sealed like every other record, not stored in the clear',
    recordHasAuthenticatedHeader(dqRow) && dqRow.answers === undefined
  );

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HIM,
    questionId: 'b1-002',
    text: 'A second day.',
    when: new Date('2026-09-11T09:00:00Z'),
    ...dqOpts,
  });
  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HIM,
    questionId: 'b1-003',
    text: 'A third day.',
    when: new Date('2026-09-12T09:00:00Z'),
    ...dqOpts,
  });
  check(
    'three days of answers are ONE row, not three - this is what keeps sync small',
    (await dqStore.table(dq.ANSWER_TABLE).toArray()).length === 1
  );

  const dqFreshDay = new Date('2026-09-20T09:00:00Z');
  const dqQ = await dq.getQuestionForDay(key, dqFreshDay);

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HER,
    questionId: dqQ.question.id,
    text: 'Something she would only say once.',
    when: dqFreshDay,
    ...dqOpts,
  });

  const dqBeforeMine = await dq.readDay({
    cryptoKey: key,
    ownerId: HIM,
    when: dqFreshDay,
    store: dqStore,
  });
  check(
    'her answer is withheld until his own is written',
    dqBeforeMine.partnerAnswer === null
  );
  check(
    'but he is told she HAS answered - a locked box, not an empty room',
    dqBeforeMine.partnerHasAnswered === true
  );

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HIM,
    questionId: dqQ.question.id,
    text: 'His own answer, written blind.',
    when: dqFreshDay,
    ...dqOpts,
  });
  const dqAfterMine = await dq.readDay({
    cryptoKey: key,
    ownerId: HIM,
    when: dqFreshDay,
    store: dqStore,
  });
  check(
    'and it opens the moment he answers',
    dqAfterMine.partnerAnswer !== null &&
      dqAfterMine.partnerAnswer.text === 'Something she would only say once.'
  );
  check(
    'his own answer reads back unchanged',
    dqAfterMine.mine.text === 'His own answer, written blind.'
  );

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: HER,
    questionId: 'b1-010',
    text: 'A day he never answered.',
    when: new Date('2026-09-25T09:00:00Z'),
    ...dqOpts,
  });
  const dqArchive = await dq.listAnswered({ cryptoKey: key, ownerId: HIM, store: dqStore });
  check(
    'the archive lists only days he actually answered',
    dqArchive.every((entry) => entry.mine !== null) &&
      !dqArchive.some((entry) => entry.day === '2026-09-25')
  );
  check(
    'newest first, so it reads as a diary',
    dqArchive.length > 1 && dqArchive[0].day > dqArchive[dqArchive.length - 1].day
  );
  check(
    'and each entry carries the question it was answering',
    dqArchive.every((entry) => entry.question === null || typeof entry.question.text === 'string')
  );

  const dqHerId = dq.answerRecordId('2026-09', HER);
  const dqHonest = await dqStore.table(dq.ANSWER_TABLE).get(dqHerId);
  await dqStore
    .table(dq.ANSWER_TABLE)
    .put({ ...dqHonest, updatedAt: dqHonest.updatedAt + 5000 });
  const dqTampered = await dq.readDay({
    cryptoKey: key,
    ownerId: HIM,
    when: dqFreshDay,
    store: dqStore,
  });
  check(
    'an answer whose header was rewritten is refused, like every other record',
    dqTampered.partnerAnswer === null && dqTampered.partnerHasAnswered === false
  );

  const dqMulti = new FakeVaultStore();
  const dqOldTag = 'his-old-device-tag';
  const dqPersonId = 'his-person-id-01';
  let dqMultiClock = 1700000000000;
  const dqMultiStamp = () => (dqMultiClock += 1000);
  const dqMineIds = new Set([dqPersonId, dqOldTag]);

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: dqOldTag,
    questionId: 'q1',
    text: 'written back when this app only knew devices',
    when: new Date('2026-08-04T09:00:00Z'),
    store: dqMulti,
    timestamp: dqMultiStamp,
  });
  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: dqOldTag,
    questionId: 'q2',
    text: 'and this one from the laptop',
    when: new Date('2026-08-05T09:00:00Z'),
    store: dqMulti,
    timestamp: dqMultiStamp,
  });
  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: dqPersonId,
    ownerIds: dqMineIds,
    questionId: 'q3',
    text: 'and this one now that the vault knows who I am',
    when: new Date('2026-08-06T09:00:00Z'),
    store: dqMulti,
    timestamp: dqMultiStamp,
  });

  const dqFolded = await dq.listAnswered({
    cryptoKey: key,
    ownerId: dqPersonId,
    ownerIds: dqMineIds,
    store: dqMulti,
  });
  check('a month written under two ids does not split in half', dqFolded.length === 3);
  check(
    'and the oldest of them is still readable',
    dqFolded.some((e) => e.mine.text.startsWith('written back'))
  );
  check(
    'writing under the new id folds the old one in',
    Object.keys(
      (await dqMulti.getDecrypted(dq.ANSWER_TABLE, dq.answerRecordId('2026-08', dqPersonId), key))
        .answers
    ).length === 3
  );

  const dqFoldedDay = await dq.readDay({
    cryptoKey: key,
    ownerId: dqPersonId,
    ownerIds: dqMineIds,
    when: new Date('2026-08-04T09:00:00Z'),
    store: dqMulti,
  });
  check('and a day from the old id reads back as MINE', dqFoldedDay.mine !== null);
  check('not as my partner\'s', dqFoldedDay.partnerHasAnswered === false);

  const dqUnbridged = await dq.readDay({
    cryptoKey: key,
    ownerId: dqPersonId,
    when: new Date('2026-08-04T09:00:00Z'),
    store: dqMulti,
  });
  check(
    'and with no bridge, an old row WOULD read as the partner (the bug)',
    dqUnbridged.partnerHasAnswered === true
  );

  const dqLate = new FakeVaultStore();
  const EARLY = 'him-early-starter';
  const LATE = 'her-late-starter';
  let dqLateClock = 1700000000000;
  const dqLateStamp = () => (dqLateClock += 1000);
  const dqMissedDay = new Date('2026-07-02T09:00:00Z');

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: EARLY,
    questionId: bank.ALL_QUESTIONS[0].id,
    text: 'what he wrote weeks before she ever opened the app',
    when: dqMissedDay,
    store: dqLate,
    timestamp: dqLateStamp,
  });

  const herArchiveBefore = await dq.listAnswered({
    cryptoKey: key,
    ownerId: LATE,
    store: dqLate,
  });
  check('the old archive showed her nothing at all', herArchiveBefore.length === 0);

  const herFullBefore = await dq.listArchive({ cryptoKey: key, ownerId: LATE, store: dqLate });
  check('the new one shows her the day exists', herFullBefore.length === 1);
  check('and marks it as one she missed', herFullBefore[0].missed === true);
  check('and tells her something is waiting', herFullBefore[0].partnerHasAnswered === true);
  check('but does NOT leak what he wrote', herFullBefore[0].theirs === null);
  check('and carries the question so she can answer it', herFullBefore[0].question !== null);
  check(
    'which is the one he was actually answering',
    herFullBefore[0].question.id === bank.ALL_QUESTIONS[0].id
  );

  check(
    'a day key converts back to a date on the same day',
    dq.dayKey(dq.dateFromDayKey('2026-07-02')) === '2026-07-02'
  );
  check('a malformed day key converts to nothing', dq.dateFromDayKey('not-a-day') === null);

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: LATE,
    questionId: bank.ALL_QUESTIONS[0].id,
    text: 'answering it now, weeks late',
    when: dq.dateFromDayKey('2026-07-02'),
    store: dqLate,
    timestamp: dqLateStamp,
  });

  const herFullAfter = await dq.listArchive({ cryptoKey: key, ownerId: LATE, store: dqLate });
  check('answering late clears the missed flag', herFullAfter[0].missed === false);
  check(
    'and opens what he wrote that day',
    herFullAfter[0].theirs && herFullAfter[0].theirs.text.startsWith('what he wrote')
  );
  check('her own late answer is there too', herFullAfter[0].mine.text.startsWith('answering it now'));

  const hisFullAfter = await dq.listArchive({ cryptoKey: key, ownerId: EARLY, store: dqLate });
  check('and it reaches him as well, on the same day', hisFullAfter[0].theirs !== null);
  check('with nothing marked missed on his side', hisFullAfter[0].missed === false);

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: EARLY,
    questionId: bank.ALL_QUESTIONS[1].id,
    text: 'a second day she has still not answered',
    when: new Date('2026-07-03T09:00:00Z'),
    store: dqLate,
    timestamp: dqLateStamp,
  });
  const herTwoDays = await dq.listArchive({ cryptoKey: key, ownerId: LATE, store: dqLate });
  const stillLocked = herTwoDays.find((e) => e.day === '2026-07-03');
  check('a day answered by one of you only is still withheld', stillLocked.theirs === null);
  check('and still reads as missed', stillLocked.missed === true);
  check('while the opened day stays open', herTwoDays.find((e) => e.day === '2026-07-02').theirs !== null);
  check('newest first, as before', herTwoDays[0].day === '2026-07-03');

  await dq.saveAnswer({
    cryptoKey: key,
    ownerId: EARLY,
    questionId: 'a-question-that-was-removed',
    text: 'answered back when this question still shipped',
    when: new Date('2026-07-04T09:00:00Z'),
    store: dqLate,
    timestamp: dqLateStamp,
  });
  const dqRetired = (await dq.listArchive({ cryptoKey: key, ownerId: LATE, store: dqLate })).find(
    (e) => e.day === '2026-07-04'
  );
  check('a question that left the bank leaves the day listed', dqRetired !== undefined);
  check('with no question attached, rather than a blank one', dqRetired.question === null);

  const dqSplitId = dq.answerRecordId('2026-08', dqOldTag);
  const dqSplitRow = await dqMulti.getDecrypted(dq.ANSWER_TABLE, dqSplitId, key);
  await dqMulti.putEncrypted(
    dq.ANSWER_TABLE,
    { ...dqSplitRow, ownerId: 'a-completely-different-tag', updatedAt: dqMultiStamp() },
    key
  );

  const dqSplitDay = await dq.readDay({
    cryptoKey: key,
    ownerId: dqPersonId,
    ownerIds: dqMineIds,
    when: new Date('2026-08-05T09:00:00Z'),
    store: dqMulti,
  });
  const dqSplitList = await dq.listAnswered({
    cryptoKey: key,
    ownerId: dqPersonId,
    ownerIds: dqMineIds,
    store: dqMulti,
  });
  check(
    'a row whose id and sealed owner disagree is attributed to nobody',
    dqSplitDay.partnerHasAnswered === false
  );
  check(
    'and today and the archive agree about that, because they share one rule',
    dqSplitList.some((e) => e.day === '2026-08-05' && e.theirs === null)
  );


  section('19. Anniversaries: day zero is not one');

  const { calculateNextMilestone } = await import('./src/utils/dateHelpers.js');
  const annNoon = (y, m, d) => new Date(y, m - 1, d, 12, 0, 0, 0);

  const annZero = calculateNextMilestone('2026-09-11', annNoon(2026, 9, 11));
  check(
    'on the start day the next anniversary is a year away, not today',
    annZero.anniversary.daysLeft === 365
  );
  check('and it is year 1, never year 0', annZero.anniversary.year === 1);

  const annNext = calculateNextMilestone('2026-09-11', annNoon(2026, 9, 12));
  check(
    'the day after the start counts down to year 1',
    annNext.anniversary.year === 1 && annNext.anniversary.daysLeft === 364
  );

  const annReal = calculateNextMilestone('2025-09-11', annNoon(2026, 9, 11));
  check('on a real first anniversary it is still today', annReal.anniversary.daysLeft === 0);
  check('and it is year 1', annReal.anniversary.year === 1);

  const annYears = calculateNextMilestone('2024-03-10', annNoon(2026, 9, 11));
  check('a couple of years in, it counts to the right year', annYears.anniversary.year === 3);

  const annFuture = calculateNextMilestone('2026-12-01', annNoon(2026, 9, 11));
  check('a start date set in the future never reports year 0', annFuture.anniversary.year >= 1);


  section('20. People: the vault knows which of you is holding the phone');

  const peopleStore = new FakeVaultStore();
  const peopleLocal = new Map();
  Object.defineProperty(globalThis, 'localStorage', {
    value: {
      getItem: (k) => (peopleLocal.has(k) ? peopleLocal.get(k) : null),
      setItem: (k, v) => peopleLocal.set(k, String(v)),
      removeItem: (k) => peopleLocal.delete(k),
    },
    configurable: true,
    writable: true,
  });

  const ppl = await import('./src/services/people.js');
  let pplClock = 1700000000000;
  const pplStamp = () => (pplClock += 1000);

  const HIS_PHONE = 'his-phone-tag-01';
  const HIS_LAPTOP = 'his-laptop-tag-1';
  const HER_PHONE = 'her-phone-tag-01';

  const slotsHis = await ppl.derivePersonSlots(key);
  const slotsHers = await ppl.derivePersonSlots(await fastKey(passphrase, salt));
  check('the two slots are agreed with no sync at all', eq(slotsHis, slotsHers));
  check('and they are two different people', slotsHis[0] !== slotsHis[1]);
  const slotsStranger = await ppl.derivePersonSlots(
    await deriveKeyFromPassphrase('an entirely different couple', generateSalt(), {
      iterations: 2000,
    })
  );
  check('another vault gets its own pair', slotsStranger[0] !== slotsHis[0]);
  check(
    'a slot id is a usable record id',
    ppl.personRecordId(slotsHis[0]) === `person-${slotsHis[0]}`
  );

  const pplEmpty = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
  });
  check('an empty vault reports `empty` rather than guessing', pplEmpty.status === 'empty');

  const couple = await ppl.createCouple({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
    timestamp: pplStamp,
    mine: { name: 'Harshit', pronoun: 'he' },
    theirs: { name: 'Noor', pronoun: 'she' },
  });

  check('setting up creates both halves of the couple', couple.me && couple.partner ? true : false);
  check('the device that set it up is the person who set it up', couple.me.name === 'Harshit');
  check('and the other one is the partner', couple.partner.name === 'Noor');
  check('his phone is recorded on his person', couple.me.deviceIds.includes(HIS_PHONE));
  check('couple creator has lastActiveAt initialized', Number.isFinite(couple.me.lastActiveAt));
  check('her person carries no device yet', couple.partner.deviceIds.length === 0);

  const hisId = couple.me.personId;
  const herId = couple.partner.personId;
  check('the two people are not the same person', hisId !== herId);

  peopleLocal.clear();
  ppl.clearLocalPersonId();

  const afterWipe = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
  });
  check('losing localStorage does not lose who you are', afterWipe.status === 'ready');
  check('it recovers the right person, silently', afterWipe.me.personId === hisId);
  check('and the partner still resolves', afterWipe.partner.personId === herId);
  check('the recovered hint is written back', ppl.getLocalPersonId() === hisId);

  peopleLocal.clear();
  ppl.clearLocalPersonId();

  const unclaimed = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HER_PHONE,
  });
  check('an unknown device asks instead of guessing', unclaimed.status === 'unclaimed');
  check('and it offers both of you to choose from', unclaimed.people.length === 2);
  check('it does not pick a "me" on a hunch', unclaimed.me === null);

  await ppl.claimPerson({
    cryptoKey: key,
    store: peopleStore,
    personId: herId,
    deviceId: HER_PHONE,
    timestamp: pplStamp,
  });

  const hers = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HER_PHONE,
  });
  check('one tap is all it takes to claim a device', hers.status === 'ready');
  check('her phone is her', hers.me.personId === herId);
  check('and from her phone, HE is the partner', hers.partner.personId === hisId);
  check('her device tag is now on her record', hers.me.deviceIds.includes(HER_PHONE));
  check('claiming a person initializes lastActiveAt', Number.isFinite(hers.me.lastActiveAt));

  peopleLocal.clear();
  ppl.clearLocalPersonId();

  const stillHis = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
  });
  check('claiming one person leaves the other one alone', stillHis.me.personId === hisId);

  await ppl.claimPerson({
    cryptoKey: key,
    store: peopleStore,
    personId: herId,
    deviceId: HIS_PHONE,
    timestamp: pplStamp,
  });
  const misclaimed = await ppl.listPeople({ cryptoKey: key, store: peopleStore });
  check(
    'a mis-tap moves the device onto the person tapped',
    misclaimed.find((p) => p.personId === herId).deviceIds.includes(HIS_PHONE)
  );
  check(
    'and takes it off the one it was on',
    misclaimed.find((p) => p.personId === hisId).deviceIds.includes(HIS_PHONE) === false
  );

  await ppl.claimPerson({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    deviceId: HIS_PHONE,
    timestamp: pplStamp,
  });
  const corrected = await ppl.listPeople({ cryptoKey: key, store: peopleStore });
  check(
    'correcting it puts the device back',
    corrected.find((p) => p.personId === hisId).deviceIds.includes(HIS_PHONE)
  );
  check(
    'and never leaves one device answering to two people',
    corrected.find((p) => p.personId === herId).deviceIds.includes(HIS_PHONE) === false
  );
  check(
    'her own device is untouched throughout',
    corrected.find((p) => p.personId === herId).deviceIds.includes(HER_PHONE)
  );

  await ppl.claimPerson({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    deviceId: HIS_LAPTOP,
    timestamp: pplStamp,
  });

  const twoDevices = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_LAPTOP,
  });
  check('a second device can belong to the same person', twoDevices.me.personId === hisId);
  check('his phone is still on the record too', twoDevices.me.deviceIds.includes(HIS_PHONE));
  check('and so is his laptop', twoDevices.me.deviceIds.includes(HIS_LAPTOP));

  const hisOwnerIds = ppl.ownerIdsFor(twoDevices.me);
  check('a person answers to their person id', hisOwnerIds.has(hisId));
  check('and to every device tag they have ever used', hisOwnerIds.has(HIS_PHONE));
  check('including the second one', hisOwnerIds.has(HIS_LAPTOP));
  check('but not to the other person\'s device', hisOwnerIds.has(HER_PHONE) === false);
  check('an absent person owns nothing', ppl.ownerIdsFor(null).size === 0);

  await ppl.savePerson({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    name: 'H',
    timestamp: pplStamp,
  });
  const renamed = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
  });
  check('a rename takes effect', renamed.me.name === 'H');
  check('and does NOT drop the device tags', renamed.me.deviceIds.length === 2);
  check('nor the pronoun that was not edited', renamed.me.pronoun === 'he');

  await ppl.savePerson({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    addDeviceId: HIS_LAPTOP,
    timestamp: pplStamp,
  });
  await peopleStore.putEncrypted(
    'people',
    {
      id: ppl.personRecordId(hisId),
      personId: hisId,
      name: 'H',
      pronoun: 'he',
      deviceIds: [HIS_LAPTOP],
      createdAt: 1,
      updatedAt: pplStamp(),
    },
    key
  );
  ppl.setLocalPersonId(hisId);

  const healed = await ppl.ensureDeviceClaimed({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
    timestamp: pplStamp,
  });
  check('a dropped device tag is noticed', healed !== null);
  const afterHeal = await ppl.resolveIdentity({
    cryptoKey: key,
    store: peopleStore,
    deviceId: HIS_PHONE,
  });
  check('and put back without asking', afterHeal.me.deviceIds.includes(HIS_PHONE));
  check('leaving the other device where it was', afterHeal.me.deviceIds.includes(HIS_LAPTOP));
  check(
    'and doing nothing at all when there is nothing to fix',
    (await ppl.ensureDeviceClaimed({
      cryptoKey: key,
      store: peopleStore,
      deviceId: HIS_PHONE,
      timestamp: pplStamp,
    })) === null
  );

  check('a name is trimmed', ppl.sanitizeName('  Noor  ') === 'Noor');
  check('a pasted newline cannot break a line of copy', ppl.sanitizeName('No\nor') === 'No or');
  check(
    'a name is bounded',
    ppl.sanitizeName('n'.repeat(500)).length === ppl.MAX_NAME_LENGTH
  );
  check('a non-string name is simply absent', ppl.sanitizeName({ evil: true }) === '');
  check('an unknown pronoun falls back to they', ppl.sanitizePronoun('xyzzy') === 'they');
  check('a known one is kept', ppl.sanitizePronoun('she') === 'she');

  check('they take a plural verb', ppl.grammarOf({ pronoun: 'they' }).has === 'have');
  check('she takes a singular one', ppl.grammarOf({ pronoun: 'she' }).has === 'has');
  check('and so does he', ppl.grammarOf({ pronoun: 'he' }).is === 'is');
  check('a missing person still yields usable grammar', ppl.grammarOf(null).subject === 'they');

  check('a possessive reads naturally', ppl.possessiveOf({ name: 'Noor' }) === "Noor's");
  check('a name ending in s is not mangled', ppl.possessiveOf({ name: 'Iris' }) === "Iris'");
  check('a nameless partner still has a possessive', ppl.possessiveOf(null) === "your partner's");
  check('and a usable name', ppl.nameOf(null) === 'your partner');

  check(
    'a person whose id does not match its own personId is refused',
    ppl.toPerson({ id: 'person-somebody-else', personId: 'aaaaaaaaaaaa', name: 'X' }) === null
  );
  check(
    'a tampered header is refused',
    ppl.toPerson({
      id: ppl.personRecordId('aaaaaaaaaaaa'),
      personId: 'aaaaaaaaaaaa',
      _headerTampered: true,
    }) === null
  );
  check(
    'a row sealed for another table is refused',
    ppl.toPerson({
      id: ppl.personRecordId('aaaaaaaaaaaa'),
      personId: 'aaaaaaaaaaaa',
      _tableTampered: true,
    }) === null
  );
  check('and so is a person with no id at all', ppl.toPerson({ name: 'X' }) === null);

  const personWithActive = ppl.toPerson({
    id: ppl.personRecordId('bbbbbbbbbbbb'),
    personId: 'bbbbbbbbbbbb',
    name: 'B',
    lastActiveAt: 1700000050000,
  });
  check('lastActiveAt is parsed when present', personWithActive?.lastActiveAt === 1700000050000);

  const personWithoutActive = ppl.toPerson({
    id: ppl.personRecordId('cccccccccccc'),
    personId: 'cccccccccccc',
    name: 'C',
    lastActiveAt: 'not-a-number',
  });
  check('lastActiveAt falls back to null when not a finite number', personWithoutActive?.lastActiveAt === null);

  check(
    'a presence record is not a person',
    ppl.toPerson({ id: ppl.presenceRecordId(hisId), personId: hisId, lastActiveAt: 1 }) === null
  );
  check(
    'and a person record is not presence',
    ppl.toPresence({ id: ppl.personRecordId(hisId), personId: hisId, lastActiveAt: 1 }) === null
  );
  check(
    'presence without a usable time is no presence at all',
    ppl.toPresence({ id: ppl.presenceRecordId(hisId), personId: hisId, lastActiveAt: 'soon' }) === null
  );

  const hisRowBeforeTouch = await peopleStore.getDecrypted('people', ppl.personRecordId(hisId), key);
  const touched1 = await ppl.touchPersonActive({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    minIntervalMs: 0,
    timestamp: pplStamp,
  });
  check('touchPersonActive updates lastActiveAt', touched1 !== null);
  check('in a presence record of its own', touched1?.id === ppl.presenceRecordId(hisId));
  const hisPresence = ppl.toPresence(
    await peopleStore.getDecrypted('people', ppl.presenceRecordId(hisId), key)
  );
  check('and it is stored encrypted, readable only with the key', typeof hisPresence?.lastActiveAt === 'number');
  const hisRowAfterTouch = await peopleStore.getDecrypted('people', ppl.personRecordId(hisId), key);
  check(
    'a heartbeat never rewrites the person record, so it cannot undo a rename from the other phone',
    hisRowAfterTouch.updatedAt === hisRowBeforeTouch.updatedAt &&
      hisRowAfterTouch.name === hisRowBeforeTouch.name &&
      eq(hisRowAfterTouch.deviceIds, hisRowBeforeTouch.deviceIds)
  );

  const peopleWithPresence = await ppl.listPeople({ cryptoKey: key, store: peopleStore });
  check('presence is never mistaken for a third person', peopleWithPresence.length === 2);
  check(
    'and its time is read back onto the right person',
    peopleWithPresence.find((p) => p.personId === hisId).lastActiveAt === hisPresence.lastActiveAt
  );

  const touchedThrottled = await ppl.touchPersonActive({
    cryptoKey: key,
    store: peopleStore,
    personId: hisId,
    minIntervalMs: 60000,
    timestamp: pplStamp,
  });
  check('touchPersonActive throttles when called again within minIntervalMs', touchedThrottled === null);

  const legacyStore = new FakeVaultStore();
  await legacyStore.putEncrypted(
    'people',
    { id: ppl.personRecordId(hisId), personId: hisId, name: 'Harshit', lastActiveAt: 1700000900000, createdAt: 1, updatedAt: 2 },
    key
  );
  await legacyStore.putEncrypted(
    'people',
    { id: ppl.presenceRecordId(hisId), personId: hisId, lastActiveAt: 1700000100000, updatedAt: 3 },
    key
  );
  const legacyPeople = await ppl.listPeople({ cryptoKey: key, store: legacyStore });
  check(
    'an older build\'s heartbeat on the person record still counts when it is newer',
    legacyPeople.length === 1 && legacyPeople[0].lastActiveAt === 1700000900000
  );

  const { formatLastSeen, formatLastConnected } = await import('./src/utils/dateHelpers.js');
  const now = 1700000100000;

  check('formatLastSeen returns null for missing or invalid timestamp', formatLastSeen(null, now) === null && formatLastSeen('abc', now) === null);
  check('formatLastSeen reports "Just now" for recent timestamps (< 60s)', formatLastSeen(now - 30 * 1000, now) === 'Just now');
  check('formatLastSeen reports minutes ago for < 1h', formatLastSeen(now - 15 * 60 * 1000, now) === '15m ago');
  check('formatLastSeen reports hours ago for < 24h', formatLastSeen(now - 3 * 3600 * 1000, now) === '3h ago');
  check('formatLastSeen reports "Yesterday" for 24-48h', formatLastSeen(now - 25 * 3600 * 1000, now) === 'Yesterday');
  check('formatLastSeen reports days ago for 2-6 days', formatLastSeen(now - 3 * 86400 * 1000, now) === '3d ago');

  check('formatLastConnected returns null for missing timestamp', formatLastConnected(null, now) === null);
  check('formatLastConnected reports relative minutes', formatLastConnected(now - 10 * 60 * 1000, now) === '10m ago');
  check('formatLastConnected reports "Just now" for fresh connection', formatLastConnected(now - 10 * 1000, now) === 'Just now');


  section('21. The mailbox: neither of you has to be awake');

  const mbx = await import('./src/services/mailbox.js');

  const mbxId = await mbx.deriveMailboxId(key);
  const mbxIdAgain = await mbx.deriveMailboxId(await fastKey(passphrase, salt));
  check('both phones derive the same mailbox with no sync', mbxId === mbxIdAgain);
  check('and it is a full 256 bits of address', /^[0-9a-f]{64}$/.test(mbxId));
  const mbxStranger = await mbx.deriveMailboxId(
    await deriveKeyFromPassphrase('someone else entirely', generateSalt(), { iterations: 2000 })
  );
  check('another couple cannot land on the same mailbox', mbxStranger !== mbxId);

  check(
    'a record key is URL-safe whatever the id contains',
    /^[A-Za-z0-9_-]+$/.test(mbx.recordKey('ans-2026-09-a/b+c=d'))
  );
  check('and two different ids never collide', mbx.recordKey('a') !== mbx.recordKey('b'));

  const mbxBucket = new Map();
  const mbxCalls = [];
  const realFetch = globalThis.fetch;

  globalThis.fetch = async (url, options = {}) => {
    const { pathname } = new URL(url);
    const method = options.method || 'GET';
    mbxCalls.push(`${method} ${pathname}`);

    if (options.headers?.Authorization !== 'Bearer test-token') {
      return { ok: false, status: 401, async text() { return ''; } };
    }
    if (method === 'PUT') {
      mbxBucket.set(pathname, options.body);
      return { ok: true, status: 204, async text() { return ''; } };
    }
    if (mbxBucket.has(pathname)) {
      const body = mbxBucket.get(pathname);
      return { ok: true, status: 200, async text() { return body; } };
    }
    return { ok: false, status: 404, async text() { return ''; } };
  };

  const mbxCfg = { url: 'https://mailbox.example.workers.dev', token: 'test-token' };
  const HIS_BOX = 'his-person-mailbox';
  const HER_BOX = 'her-person-mailbox';

  try {
    check('with no mailbox configured the feature reports disabled', mbx.isMailboxEnabled() === false);
    const mbxOff = await mbx.publish({ cryptoKey: key, ownerId: HIS_BOX });
    check('and publishing is a no-op rather than a crash', mbxOff.reason === 'disabled');
    const mbxOffCollect = await mbx.collect({ cryptoKey: key, partnerId: HIS_BOX });
    check('as is collecting', mbxOffCollect.reason === 'disabled');
    check(
      'half a config counts as none of it',
      mbx.isMailboxEnabled({ url: 'https://x.dev' }) === false
    );

    const hisPhone = new FakeVaultStore();
    let mbxClock = 1700000000000;
    const mbxStamp = () => (mbxClock += 1000);

    await hisPhone.putEncrypted(
      'letters',
      { id: 'letter-apart-1', title: 'While you were asleep', body: 'I wrote this at 3am.', updatedAt: mbxStamp() },
      key
    );
    await hisPhone.putEncrypted(
      'bucketList',
      { id: 'bucket-apart-1', text: 'Actually be in the same country', updatedAt: mbxStamp() },
      key
    );

    const pub = await mbx.publish({
      cryptoKey: key,
      ownerId: HIS_BOX,
      overrides: mbxCfg,
      store: hisPhone,
    });
    check('publishing succeeds', pub.ok === true);
    check('and it uploaded both records', pub.uploaded === 2);
    check(
      'the manifest is written LAST, after the records it promises',
      mbxCalls[mbxCalls.length - 1] === `PUT /m/${mbxId}/${HIS_BOX}/manifest`
    );

    const storedManifest = mbxBucket.get(`/m/${mbxId}/${HIS_BOX}/manifest`);
    check('the manifest itself is encrypted, not plaintext ids', !storedManifest.includes('letter-apart-1'));
    const storedLetter = mbxBucket.get(
      `/m/${mbxId}/${HIS_BOX}/rec/letters/${mbx.recordKey('letter-apart-1')}`
    );
    check('a stored record does not leak its contents', !storedLetter.includes('3am'));
    check('nor its title', !storedLetter.includes('While you were asleep'));
    check('it is the sealed envelope, unchanged', JSON.parse(storedLetter).ciphertext !== undefined);

    check(
      'and carries nothing beyond what addressing and last-write-wins need',
      eq(Object.keys(JSON.parse(storedLetter)).sort(), [
        'ciphertext',
        'deleted',
        'id',
        'iv',
        'updatedAt',
        'v',
      ])
    );
    check('specifically, local index bookkeeping stays local', !storedLetter.includes('_del'));

    const herPhone = new FakeVaultStore();
    const realDbManifest = db.getManifest;
    const realPlan = db.planBackupMerge;
    const realApply = db.applyBackupMerge;
    db.getManifest = () => FakeVaultStore.prototype.getManifest.call(herPhone);

    const got = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });

    check('she collects what he published', got.ok === true);
    check('fetching only what she was missing', got.fetched === 2);
    check('and it is applied to her vault', got.applied === 2);

    const herLetter = await herPhone.getDecrypted('letters', 'letter-apart-1', key);
    check('his letter is readable on her phone', herLetter && herLetter.body === 'I wrote this at 3am.');
    check('with the title intact', herLetter.title === 'While you were asleep');
    check('and the other table came too', (await herPhone.getDecrypted('bucketList', 'bucket-apart-1', key)) !== null);

    mbxCalls.length = 0;
    const again = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('a second collect applies nothing', again.applied === 0);
    check('and downloads no records at all', again.fetched === 0);
    check(
      'it costs exactly one manifest read',
      mbxCalls.length === 1 && mbxCalls[0].endsWith('/manifest')
    );

    mbxCalls.length = 0;
    const republish = await mbx.publish({
      cryptoKey: key,
      ownerId: HIS_BOX,
      overrides: mbxCfg,
      store: hisPhone,
    });
    check('re-publishing an unchanged vault uploads nothing', republish.uploaded === 0);
    check(
      'and writes nothing at all, not even the manifest',
      !mbxCalls.some((call) => call.startsWith('PUT '))
    );
    check(
      'reporting that as unchanged rather than as a failure',
      republish.ok === true && republish.unchanged === true
    );

    await hisPhone.putEncrypted(
      'letters',
      { id: 'letter-apart-1', title: 'While you were asleep', body: 'Edited it in the morning.', updatedAt: mbxStamp() },
      key
    );
    const edited = await mbx.publish({
      cryptoKey: key,
      ownerId: HIS_BOX,
      overrides: mbxCfg,
      store: hisPhone,
    });
    check('editing one record uploads exactly one record', edited.uploaded === 1);
    check(
      'and a real change still announces itself',
      mbxCalls[mbxCalls.length - 1] === `PUT /m/${mbxId}/${HIS_BOX}/manifest`
    );

    const gotEdit = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('and the edit reaches her', gotEdit.applied === 1);
    check(
      'with the newer words',
      (await herPhone.getDecrypted('letters', 'letter-apart-1', key)).body === 'Edited it in the morning.'
    );

    await hisPhone.softDelete('letters', 'letter-apart-1', key);
    const deletePub = await mbx.publish({
      cryptoKey: key,
      ownerId: HIS_BOX,
      overrides: mbxCfg,
      store: hisPhone,
    });
    check('deleting a letter publishes something', deletePub.uploaded === 1);
    check(
      'and the object is still THERE, holding a tombstone',
      mbxBucket.has(`/m/${mbxId}/${HIS_BOX}/rec/letters/${mbx.recordKey('letter-apart-1')}`)
    );
    check(
      'which is marked deleted on the wire',
      JSON.parse(
        mbxBucket.get(`/m/${mbxId}/${HIS_BOX}/rec/letters/${mbx.recordKey('letter-apart-1')}`)
      ).deleted === true
    );

    const gotDelete = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('the deletion reaches her', gotDelete.applied === 1);
    const herDeleted = await herPhone.table('letters').get('letter-apart-1');
    check('her copy is a tombstone now', herDeleted.deleted === true);
    const herDeletedPlain = await herPhone.getDecrypted('letters', 'letter-apart-1', key);
    check('and the words are actually gone from inside it', herDeletedPlain.body === undefined);
    check('title too', herDeletedPlain.title === undefined);
    check('leaving only the fact that it died', herDeletedPlain.deleted === true);

    const afterDelete = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('and it does not rise from the dead on the next sync', afterDelete.applied === 0);

    const evilKey = await deriveKeyFromPassphrase('not our passphrase at all', generateSalt(), {
      iterations: 2000,
    });
    const evilRow = await encryptRecord(
      { id: 'letter-forged', title: 'Forged', body: 'Written by the relay.', updatedAt: Date.now() },
      evilKey,
      { table: 'letters' }
    );
    mbxBucket.set(
      `/m/${mbxId}/${HIS_BOX}/rec/letters/${mbx.recordKey('letter-forged')}`,
      JSON.stringify(evilRow)
    );
    const hisManifestNow = await hisPhone.getManifest();
    hisManifestNow.letters.push({ id: 'letter-forged', updatedAt: Date.now(), deleted: false });
    const forgedManifest = await encryptJSON(hisManifestNow, key);
    mbxBucket.set(`/m/${mbxId}/${HIS_BOX}/manifest`, JSON.stringify(forgedManifest));

    const forged = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('a record the relay forged is fetched but not applied', forged.applied === 0);
    check(
      'and never reaches her vault',
      (await herPhone.table('letters').get('letter-forged')) === undefined
    );

    const brokenManifest = await hisPhone.getManifest();
    brokenManifest.letters.push({ id: 'letter-missing', updatedAt: Date.now(), deleted: false });
    mbxBucket.set(
      `/m/${mbxId}/${HIS_BOX}/manifest`,
      JSON.stringify(await encryptJSON(brokenManifest, key))
    );
    const dangling = await mbx.collect({
      cryptoKey: key,
      partnerId: HIS_BOX,
      overrides: mbxCfg,
      store: herPhone,
    });
    check('a manifest promising a missing record does not throw', dangling.ok === true);
    check('it simply applies nothing', dangling.applied === 0);

    const empty = await mbx.collect({
      cryptoKey: key,
      partnerId: HER_BOX,
      overrides: mbxCfg,
      store: hisPhone,
    });
    check('an empty mailbox is not an error', empty.ok === true);
    check('there is simply nothing published', empty.reason === 'nothing-published');

    const badToken = await mbx.publish({
      cryptoKey: key,
      ownerId: HIS_BOX,
      overrides: { url: mbxCfg.url, token: 'wrong' },
      store: hisPhone,
    });
    check('a bad token fails the publish rather than half-doing it', badToken.ok === false);

    db.getManifest = realDbManifest;
    db.planBackupMerge = realPlan;
    db.applyBackupMerge = realApply;
  } finally {
    if (realFetch) globalThis.fetch = realFetch;
    else delete globalThis.fetch;
  }


  section('22. The mailbox Worker: what it will not do');

  const worker = (await import('./worker/src/index.js')).default;

  const WK_ORIGIN = 'https://sameskytonight.vercel.app';
  const WK_ID = 'a'.repeat(64);
  const WK_KEY = `/m/${WK_ID}/person-slot-aaaa/manifest`;

  const wkKv = new Map();
  const kvBinding = {
    async get(k) {
      return wkKv.has(k) ? wkKv.get(k) : null;
    },
    async put(k, v) {
      wkKv.set(k, v);
    },
  };
  const wkR2 = new Map();
  const r2Binding = {
    async head() {
      return null;
    },
    async get(k) {
      return wkR2.has(k) ? { body: wkR2.get(k) } : null;
    },
    async put(k, v) {
      wkR2.set(k, v);
    },
  };

  const wkReq = (method, path, opts = {}) =>
    new Request(`https://w.dev${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${opts.token === undefined ? 'tok' : opts.token}`,
        Origin: opts.origin === undefined ? WK_ORIGIN : opts.origin,
      },
      body: opts.body,
    });

  for (const [label, binding] of [
    ['KV', kvBinding],
    ['R2', r2Binding],
  ]) {
    const env = { MAILBOX: binding, MAILBOX_TOKEN: 'tok', ALLOWED_ORIGIN: WK_ORIGIN };
    const before = await worker.fetch(wkReq('GET', WK_KEY), env);
    check(`${label}: an object nobody has written is a plain 404`, before.status === 404);

    const stored = await worker.fetch(wkReq('PUT', WK_KEY, { body: 'sealed-bytes' }), env);
    check(`${label}: storing one succeeds`, stored.status === 204);

    const after = await worker.fetch(wkReq('GET', WK_KEY), env);
    check(`${label}: and it comes back byte for byte`, (await after.text()) === 'sealed-bytes');
  }

  const wkEnv = { MAILBOX: kvBinding, MAILBOX_TOKEN: 'tok', ALLOWED_ORIGIN: WK_ORIGIN };

  check(
    'a wrong token is refused',
    (await worker.fetch(wkReq('GET', WK_KEY, { token: 'nope' }), wkEnv)).status === 401
  );
  check(
    'an origin that is not on the allowlist is refused',
    (await worker.fetch(wkReq('GET', WK_KEY, { origin: 'https://evil.example' }), wkEnv)).status === 403
  );
  check(
    'and the allowlist is not just reflected back',
    (
      await worker.fetch(wkReq('GET', WK_KEY, { origin: 'https://evil.example' }), wkEnv)
    ).headers.get('Access-Control-Allow-Origin') === null
  );
  check(
    'a preflight from the real origin passes',
    (
      await worker.fetch(
        new Request(`https://w.dev${WK_KEY}`, { method: 'OPTIONS', headers: { Origin: WK_ORIGIN } }),
        wkEnv
      )
    ).status === 204
  );

  check(
    'DELETE is refused - a deletion is a write, never a disappearance',
    (await worker.fetch(wkReq('DELETE', WK_KEY), wkEnv)).status === 405
  );

  check(
    'a path that is not a mailbox object is a 404',
    (await worker.fetch(wkReq('GET', `/m/${WK_ID}`), wkEnv)).status === 404
  );
  check(
    'there is no route that lists anything',
    (await worker.fetch(wkReq('GET', `/m/${WK_ID}/person-slot-aaaa/`), wkEnv)).status === 404
  );
  check(
    'traversal in a record key does not resolve to a key',
    (await worker.fetch(wkReq('GET', `/m/${WK_ID}/person-slot-aaaa/rec/letters/../../x`), wkEnv))
      .status === 404
  );
  check(
    'a mailbox id that is not hex is not a mailbox',
    (await worker.fetch(wkReq('GET', `/m/${'z'.repeat(64)}/person-slot-aaaa/manifest`), wkEnv))
      .status === 404
  );

  check(
    'an object over the size ceiling is refused',
    (await worker.fetch(wkReq('PUT', WK_KEY, { body: 'x'.repeat(17 * 1024 * 1024) }), wkEnv))
      .status === 413
  );
  const wkStored = wkKv.get(WK_KEY.replace(/^\/m\//, ''));
  check(
    'and the oversized body did not overwrite what was there',
    wkStored !== undefined && new TextDecoder().decode(wkStored) === 'sealed-bytes'
  );

  check(
    'a Worker with no store bound says so rather than half-working',
    (await worker.fetch(wkReq('GET', WK_KEY), { MAILBOX_TOKEN: 'tok', ALLOWED_ORIGIN: WK_ORIGIN }))
      .status === 500
  );

  section('23. A phone that lost its space');

  const { requestPersistentStorage } = await import('./src/services/persistentStorage.js');

  const fakeStorage = ({ persisted, persist }) => {
    const calls = { persist: 0 };
    return {
      calls,
      storage: {
        persisted: persisted === undefined ? undefined : async () => persisted,
        async persist() {
          calls.persist++;
          if (persist instanceof Error) throw persist;
          return persist;
        },
      },
    };
  };

  const psAlready = fakeStorage({ persisted: true, persist: true });
  check(
    'storage that is already kept is left alone',
    (await requestPersistentStorage({ storage: psAlready.storage })) === 'persisted' &&
      psAlready.calls.persist === 0
  );

  const psGrant = fakeStorage({ persisted: false, persist: true });
  check(
    'otherwise the browser is asked, once',
    (await requestPersistentStorage({ storage: psGrant.storage })) === 'granted' &&
      psGrant.calls.persist === 1
  );

  const psDeny = fakeStorage({ persisted: false, persist: false });
  check(
    'a refusal is reported as one, not as success',
    (await requestPersistentStorage({ storage: psDeny.storage })) === 'denied'
  );

  const psNoQuery = fakeStorage({ persisted: undefined, persist: true });
  check(
    'a browser that can only be asked is still asked',
    (await requestPersistentStorage({ storage: psNoQuery.storage })) === 'granted' &&
      psNoQuery.calls.persist === 1
  );

  const psThrows = fakeStorage({ persisted: false, persist: new Error('blocked') });
  check(
    'a browser that throws does not take unlocking down with it',
    (await requestPersistentStorage({ storage: psThrows.storage })) === 'unsupported'
  );

  check(
    'and a browser without the API is simply unsupported',
    (await requestPersistentStorage({ storage: undefined })) === 'unsupported' &&
      (await requestPersistentStorage({ storage: {} })) === 'unsupported'
  );

  const { isInstalledApp } = await import('./src/utils/appEnvironment.js');
  const { defaultLockScreenMode } = await import('./src/utils/lockScreenMode.js');

  const fakeWindow = (mode) => ({
    matchMedia: (query) => ({ matches: query === `(display-mode: ${mode})` }),
    navigator: {},
  });

  check('a home screen launch counts as installed', isInstalledApp(fakeWindow('standalone')));
  check(
    'so does a full-screen or minimal-ui one',
    isInstalledApp(fakeWindow('fullscreen')) && isInstalledApp(fakeWindow('minimal-ui'))
  );
  check('a browser tab does not', !isInstalledApp(fakeWindow('browser')));
  check('iOS saying so on navigator counts too', isInstalledApp({ navigator: { standalone: true } }));
  check(
    'a window that cannot answer is not installed',
    !isInstalledApp({
      matchMedia: () => {
        throw new Error('no media queries here');
      },
    }) && !isInstalledApp({})
  );

  const mode = (vaultCheckState, inviteHasSalt, installed) =>
    defaultLockScreenMode({ vaultCheckState, inviteHasSalt, installed });

  check(
    'a phone with a vault opens on unlock, installed or not, invite or not',
    mode('present', false, true) === 'unlock' && mode('present', true, false) === 'unlock'
  );
  check('an installed app with nothing in it opens on join', mode('absent', false, true) === 'join');
  check('a browser tab with nothing in it still opens on create', mode('absent', false, false) === 'setup');
  check('an invite opens on join either way', mode('absent', true, false) === 'join');
  check(
    'and nothing is chosen while we cannot tell',
    mode('checking', false, true) === null && mode('unreadable', true, true) === null
  );

  const { detectInAppBrowser } = await import('./src/utils/appEnvironment.js');

  const ANDROID_WEBVIEW =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Version/4.0 Chrome/129.0.0.0 Mobile Safari/537.36';
  const UA = {
    chrome:
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) ' +
      'Chrome/129.0.0.0 Mobile Safari/537.36',
    samsung:
      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) ' +
      'SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile Safari/537.36',
    safari:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 ' +
      '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
    instagramAndroid: `${ANDROID_WEBVIEW} Instagram 350.0.0.0.0 Android (34/14; 420dpi)`,
    instagramIphone:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 ' +
      '(KHTML, like Gecko) Mobile/15E148 Instagram 350.0.0.0 (iPhone15,2; iOS 18_0)',
    facebook: `${ANDROID_WEBVIEW} [FB_IAB/FB4A;FBAV/480.0.0.0;]`,
    messenger: `${ANDROID_WEBVIEW} [FB_IAB/Orca-Android;FBAV/450.0.0.0;]`,
  };

  check(
    'Chrome, Samsung Internet and Safari are ordinary browsers',
    [UA.chrome, UA.samsung, UA.safari].every((ua) => detectInAppBrowser(ua) === null)
  );
  check(
    'Instagram is recognised on both kinds of phone',
    eq(detectInAppBrowser(UA.instagramAndroid), { app: 'Instagram' }) &&
      eq(detectInAppBrowser(UA.instagramIphone), { app: 'Instagram' })
  );
  check(
    'Facebook and Messenger are told apart',
    eq(detectInAppBrowser(UA.facebook), { app: 'Facebook' }) &&
      eq(detectInAppBrowser(UA.messenger), { app: 'Messenger' })
  );
  check(
    'an Android WebView we cannot name is still caught',
    eq(detectInAppBrowser(ANDROID_WEBVIEW), { app: null })
  );
  check('and an empty user agent is no reason to warn', detectInAppBrowser('') === null);

  section('24. Swapped: when the two of you trade places by accident');

  const [SLOT_A, SLOT_B] = await ppl.derivePersonSlots(key);
  let swClock = 1760000000000;
  const swStamp = () => (swClock += 60 * 1000);

  const putPerson = async (store, personId, name, deviceIds, createdAt = 1) =>
    store.putEncrypted(
      ppl.PEOPLE_TABLE,
      {
        id: ppl.personRecordId(personId),
        personId,
        name,
        pronoun: 'they',
        deviceIds,
        createdAt,
        updatedAt: swStamp(),
      },
      key
    );

  const whoAmI = async (store, deviceId, hint) => {
    ppl.clearLocalPersonId();
    if (hint) ppl.setLocalPersonId(hint);
    const out = await ppl.resolveIdentity({ cryptoKey: key, store, deviceId });
    return { ...out, hintAfter: ppl.getLocalPersonId() };
  };

  const prec = new FakeVaultStore();
  await putPerson(prec, SLOT_A, 'Harshit', ['his-phone-tag-01']);
  await putPerson(prec, SLOT_B, 'Noor', ['her-phone-tag-01']);

  const followed = await whoAmI(prec, 'her-phone-tag-01', SLOT_A);
  check(
    'a hint pointing at a person who now belongs to another phone gives way to the records',
    followed.me && followed.me.personId === SLOT_B && followed.hintAfter === SLOT_B
  );

  const prec2 = new FakeVaultStore();
  await putPerson(prec2, SLOT_A, 'Harshit', []);
  await putPerson(prec2, SLOT_B, 'Noor', ['her-phone-tag-01']);
  const keptEmpty = await whoAmI(prec2, 'her-phone-tag-01', SLOT_A);
  check(
    'but a hinted person who lists no phone at all keeps the hint, because that is a dropped tag',
    keptEmpty.me && keptEmpty.me.personId === SLOT_A
  );

  const prec3 = new FakeVaultStore();
  await putPerson(prec3, SLOT_A, 'Harshit', ['his-phone-tag-01', 'her-phone-tag-01']);
  await putPerson(prec3, SLOT_B, 'Noor', ['her-phone-tag-01']);
  const keptListed = await whoAmI(prec3, 'her-phone-tag-01', SLOT_A);
  check(
    'and a hinted person who still lists this phone is never overruled',
    keptListed.me && keptListed.me.personId === SLOT_A
  );

  const noHint = await whoAmI(prec, 'her-phone-tag-01', null);
  check(
    'with no hint at all the records decide, as before',
    noHint.me && noHint.me.personId === SLOT_B && noHint.hintAfter === SLOT_B
  );

  const daily = await import('./src/services/dailyQuestion.js');
  const repair = await import('./src/services/peopleRepair.js');

  const HIS = 'his-phone-tag-01';
  const HIS_FIRST_INSTALL = 'his-first-install';
  const HER_OLD = 'her-old-phone-01';
  const HER_NEW = 'her-new-phone-01';
  const utc = (day, hhmm = '12:00') => Date.parse(`${day}T${hhmm}:00Z`);
  let incidentClock = utc('2026-09-21');
  const clockAt = (ms) => {
    incidentClock = ms;
  };
  const incidentStamp = () => (incidentClock += 1000);

  const putAnswers = (store, month, ownerId, days) =>
    store.putEncrypted(
      daily.ANSWER_TABLE,
      {
        id: daily.answerRecordId(month, ownerId),
        ownerId,
        month,
        answers: Object.fromEntries(
          Object.entries(days).map(([day, at]) => [
            day,
            { questionId: 'q-1', text: `${ownerId} on ${day}`, answeredAt: at },
          ])
        ),
        updatedAt: incidentStamp(),
      },
      key
    );

  const syncInto = async (from, to) => {
    for (const table of [ppl.PEOPLE_TABLE, daily.ANSWER_TABLE]) {
      for (const row of await from.table(table).toArray()) await to.table(table).put(row);
    }
  };

  const hisPhone = new FakeVaultStore();

  await putAnswers(hisPhone, '2026-08', HIS_FIRST_INSTALL, {
    '2026-08-20': utc('2026-08-20'),
    '2026-08-25': utc('2026-08-25'),
  });
  await putAnswers(hisPhone, '2026-09', HIS, {
    '2026-09-05': utc('2026-09-05'),
    '2026-09-12': utc('2026-09-12'),
    '2026-09-20': utc('2026-09-20'),
  });
  await putAnswers(hisPhone, '2026-09', HER_OLD, {
    '2026-09-06': utc('2026-09-06'),
    '2026-09-12': utc('2026-09-12', '18:00'),
    '2026-09-19': utc('2026-09-19'),
  });

  clockAt(utc('2026-09-21'));
  await putPerson(hisPhone, SLOT_A, 'Harshit', [HIS], utc('2026-09-21'));
  await putPerson(hisPhone, SLOT_B, 'Noor', [HER_OLD], utc('2026-09-21'));
  await putAnswers(hisPhone, '2026-09', SLOT_A, {
    '2026-09-21': utc('2026-09-21', '15:00'),
    '2026-09-30': utc('2026-09-30'),
  });
  await putAnswers(hisPhone, '2026-10', SLOT_A, {
    '2026-10-01': utc('2026-10-01'),
    '2026-10-03': utc('2026-10-03'),
  });

  const herPhone = new FakeVaultStore();
  clockAt(utc('2026-10-04', '11:40'));
  await ppl.createCouple({
    cryptoKey: key,
    store: herPhone,
    deviceId: HER_NEW,
    mine: { name: 'Noor', pronoun: 'she' },
    theirs: { name: 'Harshit', pronoun: 'he' },
    timestamp: incidentStamp,
  });
  await syncInto(herPhone, hisPhone);

  const looksSwapped = await whoAmI(hisPhone, HIS, SLOT_A);
  check(
    'replayed: after her setup syncs, his own phone calls him by her name',
    looksSwapped.me && looksSwapped.me.name === 'Noor'
  );

  await ppl.claimPerson({ cryptoKey: key, store: hisPhone, personId: SLOT_B, deviceId: HIS, timestamp: incidentStamp });
  await putAnswers(hisPhone, '2026-10', SLOT_B, { '2026-10-04': utc('2026-10-04', '15:21') });

  const archiveOf = async (store, deviceId, hint) => {
    const who = await whoAmI(store, deviceId, hint);
    const rows = await daily.listArchive({
      cryptoKey: key,
      store,
      ownerId: who.me.personId,
      ownerIds: ppl.ownerIdsFor(who.me),
    });
    return { who, byDay: Object.fromEntries(rows.map((r) => [r.day, r])) };
  };

  const broken = await archiveOf(hisPhone, HIS, SLOT_B);
  check(
    'replayed: his answers from after people existed now read as missed, with hers waiting',
    broken.byDay['2026-09-21'].missed === true && broken.byDay['2026-10-03'].missed === true
  );
  check(
    'replayed: while the ones under his device tag and Sunday\'s still read as his',
    broken.byDay['2026-09-05'].mine !== null && broken.byDay['2026-10-04'].mine !== null
  );

  clockAt(utc('2026-10-05', '10:00'));
  const seenBefore = Object.fromEntries(
    (await ppl.listPeople({ cryptoKey: key, store: hisPhone })).map((p) => [p.personId, p.lastActiveAt])
  );

  const writes = { single: 0, many: 0 };
  hisPhone.putEncrypted = async function (...rest) {
    writes.single++;
    return FakeVaultStore.prototype.putEncrypted.apply(this, rest);
  };
  hisPhone.putEncryptedMany = async function (...rest) {
    writes.many++;
    return FakeVaultStore.prototype.putEncryptedMany.apply(this, rest);
  };
  const fixed = await repair.swapUsBack({
    cryptoKey: key,
    store: hisPhone,
    deviceId: HIS,
    timestamp: incidentStamp,
  });
  delete hisPhone.putEncrypted;
  delete hisPhone.putEncryptedMany;
  check(
    'the whole swap lands in one transaction, with no write on its own',
    writes.many === 1 && writes.single === 0
  );

  const repaired = await archiveOf(hisPhone, HIS, ppl.getLocalPersonId());
  check(
    'his phone is slot A again, under his own name',
    repaired.who.me.personId === SLOT_A && repaired.who.me.name === 'Harshit' && fixed.holderId === SLOT_A
  );
  const hisDays = ['2026-09-05', '2026-09-12', '2026-09-20', '2026-09-21', '2026-09-30', '2026-10-01', '2026-10-03', '2026-10-04'];
  check(
    'every day he answered is his again, Sunday included',
    hisDays.every((day) => repaired.byDay[day] && repaired.byDay[day].mine && !repaired.byDay[day].missed)
  );
  check(
    'Sunday\'s answer moved under his id, and her row kept nothing of his',
    repaired.byDay['2026-10-04'].mine.text === `${SLOT_B} on 2026-10-04` &&
      fixed.answers.length === 2
  );
  check(
    'a day you both answered opens on both sides, the way it did before',
    repaired.byDay['2026-09-12'].theirs && repaired.byDay['2026-09-12'].theirs.text === `${HER_OLD} on 2026-09-12`
  );

  const fixedPeople = await ppl.listPeople({ cryptoKey: key, store: hisPhone });
  const personA = fixedPeople.find((p) => p.personId === SLOT_A);
  const personB = fixedPeople.find((p) => p.personId === SLOT_B);
  check('his record lists his phone and nothing of hers', eq(personA.deviceIds, [HIS]));
  check(
    'hers lists her new phone, and her old install comes home because it answered alongside his',
    personB.name === 'Noor' && personB.deviceIds.includes(HER_NEW) && personB.deviceIds.includes(HER_OLD)
  );
  check(
    'but his own first install, which answered only before his phone did, is left alone',
    !personB.deviceIds.includes(HIS_FIRST_INSTALL) && eq(fixed.adopted, [HER_OLD])
  );
  check(
    'and each of you keeps your own last-online time',
    personA.lastActiveAt === seenBefore[SLOT_B] && personB.lastActiveAt === seenBefore[SLOT_A]
  );

  await syncInto(hisPhone, herPhone);
  const herSide = await archiveOf(herPhone, HER_NEW, SLOT_A);
  check(
    'her phone follows on its own: slot B, her name, nobody touched it',
    herSide.who.me.personId === SLOT_B && herSide.who.me.name === 'Noor' && herSide.who.hintAfter === SLOT_B
  );
  check(
    'and it does not put her tag back on his record',
    (await ppl.ensureDeviceClaimed({ cryptoKey: key, store: herPhone, deviceId: HER_NEW })) === null
  );
  check(
    'on her phone his answers are his, and her old ones are hers',
    herSide.byDay['2026-09-21'].mine === null &&
      herSide.byDay['2026-09-21'].partnerHasAnswered === true &&
      herSide.byDay['2026-09-06'].mine !== null
  );

  check(
    'answers written before the swap never move twice',
    (await daily.swapAnswersSince({
      cryptoKey: key,
      store: hisPhone,
      personA: SLOT_A,
      personB: SLOT_B,
      since: utc('2026-10-05', '11:00'),
      timestamp: incidentStamp,
    })).length === 0
  );
  check(
    'a tag that only touches your span at one end is not adopted',
    repair.orphansAnsweringAlongside(
      new Map([
        ['mine', { first: '2026-09-10', last: '2026-09-20' }],
        ['edge', { first: '2026-09-01', last: '2026-09-10' }],
        ['inside', { first: '2026-09-11', last: '2026-09-12' }],
      ]),
      { holderIds: ['mine'], claimed: new Set(['mine']) }
    ).join() === 'inside'
  );
  await checkThrows(
    'and it refuses a vault that does not hold exactly two people',
    () => repair.swapUsBack({ cryptoKey: key, store: new FakeVaultStore(), deviceId: HIS }),
    (err) => /exactly two people/.test(err.message)
  );

  const allOrNothing = new FakeVaultStore();
  await checkThrows(
    'a batch that cannot all be sealed writes nothing at all',
    () =>
      allOrNothing.putEncryptedMany(
        [
          { table: ppl.PEOPLE_TABLE, fields: { id: ppl.personRecordId(SLOT_A), personId: SLOT_A, name: 'x', updatedAt: 1 } },
          { table: 'notATable', fields: { id: 'nope', updatedAt: 1 } },
        ],
        key
      ),
    (err) => /unknown table/.test(err.message)
  );
  check(
    'not even the rows before the bad one',
    (await allOrNothing.table(ppl.PEOPLE_TABLE).toArray()).length === 0
  );


  console.log('\n' + '='.repeat(64));
  if (failures.length > 0) {
    console.log(`FAILED: ${failures.length} of ${passed + failures.length} assertions`);
    for (const f of failures) console.log(`  ✘ ${f}`);
    process.exitCode = 1;
    return;
  }
  console.log(`ALL ${passed} ASSERTIONS PASSED`);
  console.log('');
  console.log('NOT COVERED HERE (needs a browser, and is not faked above):');
  console.log('  - Dexie version(2).upgrade() and the blocked-upgrade event/listeners.');
  console.log('  - The _del tombstone hooks (Dexie CRUD hooks).');
  console.log('  - The React gates: LockScreen restore/unreadable modes, SyncHubModal');
  console.log('    ImportPreview, VaultContext guardDestructiveWrite / vaultCheckState /');
  console.log('    wipeSyncedTables ordering, and the destroy-confirmation prompt.');
  console.log('  - peerSync transport: admission control, backoff, flood breaker, fatal close.');
  console.log('  - getSyncSafeTimestamp() localStorage floor, and softDelete() using it.');
  console.log('  - SecretCapsule retro-seal re-read/verify loop.');
  console.log('  - The WebAuthn ceremony itself: section 17 fakes the authenticator,');
  console.log('    so browser UI, platform support and PRF availability are untested.');
  console.log('Sections 11-15 run the SHIPPED db/index.js methods against an in-memory');
  console.log('table store; only the storage is fake, and the precedence rule is proved');
  console.log("to be peerSync's own by spying on it.");
}

run().catch((err) => {
  console.error('\nSUITE CRASHED:', err);
  process.exitCode = 1;
});
