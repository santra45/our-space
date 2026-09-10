/**
 * test-crypto.mjs
 * Verification suite for the zero-knowledge crypto layer.
 *
 * Run with `npm test`. No framework, no dependencies - Node's own WebCrypto is
 * the same implementation the browser uses, so everything here is a real
 * AES-GCM / PBKDF2 / HKDF operation rather than a mock.
 *
 * COVERAGE
 *   1. Primitives            base64, nonces, salts, validators
 *   2. KDF derivation        one iteration count, and what a recorded one means
 *   3. Passphrase handling   NFKC normalisation, trimming, verified derivation
 *   4. Canary                passphrase proof used by unlock, pairing and backup
 *   5. AEAD                  associated data actually binds
 *   6. Record envelopes      schema v2, metadata genuinely encrypted at rest
 *  6b. Bound photo bytes    a swapped blob under a valid envelope is detected,
 *                           and a pre-digest row still opens
 *   7. One record shape      an unsealed row is not a record and never becomes one
 *   8. Time locks            seal/unseal, and that the date is BOUND, not checked
 *   9. Backups               containers round-trip, with or without a recorded count
 *  10. Invites               a stranger's link cannot choose our PBKDF2 salt
 *  11. Foreign backups       a stranger's file cannot overwrite a colliding id
 * 11d. Photo-swap forgery   a kept envelope plus swapped bytes is refused on
 *                           both the import and the sync gate
 * 11e. Table binding       an envelope sealed for one table cannot be replayed
 *                           into another, and an unbound one may only create
 * 11septies. Honest refusals  a row refused for an unverifiable binding is
 *                           counted and reported as that, never as staleness
 * 11octies.  Restore preview  the same split on the import path, and
 *                           applyBackupMerge's re-check re-derives the verdict
 * 11nonies.  Tamper on read   a swapped photo under a bound envelope is flagged
 *                           where every screen already looks for it
 *  12. Merge precedence      an older backup does not revert newer local work
 *  13. Rescue restore        adopt an identity, unlock with the ORIGINAL phrase
 *  14. Import sanitising     a restored clock artefact cannot win forever
 *  15. Tamper isolation      one bad record does not poison the whole restore
 *
 * HOW SECTIONS 11-15 REACH db/index.js WITHOUT A BROWSER
 * `planBackupMerge`, `applyBackupMerge`, `restoreVaultIdentity`,
 * `readVaultIdentity` and `exportRawDataForBackup` are methods on a Dexie
 * subclass, but the only Dexie surface they touch is `table(name)` with
 * get/put/toArray/bulkGet/bulkPut, `transaction()` and `vaultMeta`. So
 * `FakeVaultStore` below supplies exactly that in memory and the SHIPPED methods
 * are then borrowed onto it verbatim. The storage underneath is fake; none of
 * the logic on top of it is. The precedence rule really is fetched out of
 * peerSync at call time - section 12 proves that with a spy rather than assuming
 * it.
 *
 * WHAT THIS SUITE CANNOT COVER (nothing below is stubbed to look covered)
 *  - The `blocked` event that drives
 *    isUpgradeBlocked()/subscribeUpgradeBlocked(). It needs a real IndexedDB
 *    with two live connections. There is no upgrade callback left to cover:
 *    the app declares one schema version and nothing migrates.
 *  - The `_del` tombstone hooks, which are Dexie CRUD hooks.
 *  - Every React gate: LockScreen's restore mode, its unreadable panel and its
 *    slow/blocked hint during 'checking', SyncHubModal's ImportPreview rendering
 *    (section 11c covers only the classification it branches on),
 *    SecretCapsule's sealed-vs-date-gated banner, VaultContext's
 *    guardDestructiveWrite,
 *    vaultCheckState/retryVaultCheck, wipeSyncedTables ordering and the
 *    DESTROY_CONFIRMATION_PHRASE prompt. Section 13 reproduces the crypto
 *    sequence VaultContext.restoreVaultFromBackup performs, not the UI that
 *    decides to call it.
 *  - peerSync's TRANSPORT half: admission control, per-peer backoff, the flood
 *    breaker and _emitFatal closing the connection. Those need PeerJS/WebRTC.
 *    Its APPLY half is covered: section 11septies runs the shipped
 *    _stageIncomingRecords / _verifyRecordIntegrity / _commitStagedRecords /
 *    _applySingleLiveRecord on the shipped singleton, with the `db` singleton's
 *    `table` and `transaction` pointed at a FakeVaultStore for the duration.
 *    The pure merge rule (_incomingWins/_fingerprint) is exercised directly.
 *  - getSyncSafeTimestamp()'s localStorage high-water floor, and therefore
 *    softDelete()'s use of it.
 *  - SecretCapsule's retro-seal re-read/verify loop, which is React + Dexie.
 */
import {
  // primitives
  generateSalt,
  generateSecureNonce,
  generateUrlSafeNonce,
  bufferToBase64,
  base64ToBuffer,
  isValidBase64,
  isValidSalt,
  // kdf
  deriveKeyFromPassphrase,
  deriveKeyWithVerification,
  deriveVaultKeyBits,
  importVaultKeyFromBits,
  normalizePassphrase,
  PBKDF2_ITERATIONS_CURRENT,
  MIN_PASSPHRASE_LENGTH,
  // canary
  createCanary,
  readCanary,
  verifyPassphraseAgainstMeta,
  VAULT_CANARY_TOKEN,
  // aead
  encryptText,
  decryptText,
  encryptJSON,
  decryptJSON,
  encryptBlob,
  decryptBlob,
  // records
  encryptRecord,
  decryptRecord,
  RECORD_SCHEMA_VERSION,
  PLAINTEXT_RECORD_FIELDS,
  // time locks
  sealTimeLocked,
  unsealTimeLocked,
  isTimeLockOpen,
  getTimeLockBoundary,
  TimeLockedError,
  // backups
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

/* ------------------------------------------------------------------ harness */

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

/** Asserts that `fn` rejects, optionally matching the error. */
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

/** Fast key for tests that are not about the KDF itself. */
const fastKey = (passphrase, salt) => deriveKeyFromPassphrase(passphrase, salt, { iterations: 2000 });

/* -------------------------------------------------- a device, without Dexie */

/**
 * The minimum Dexie surface db/index.js's backup and identity code actually
 * uses, backed by plain Maps.
 *
 * This exists so the REAL methods can run in Node. It deliberately implements
 * storage only - no timestamp comparison, no validation, no precedence - so a
 * bug in the shipped logic cannot be masked by a helpful reimplementation here.
 * The methods themselves are copied onto the prototype below, straight off
 * SweetheartDatabase, so these tests fail if that code changes behaviour.
 */
class FakeVaultStore {
  /** @param {Record<string, Object[]>} [seed] Rows per table, keyed by table name. */
  constructor(seed = {}) {
    this._tables = new Map();
    for (const name of EXPORTED_TABLES) {
      this._tables.set(name, new Map((seed[name] || []).map((row) => [row.id, row])));
    }
    /** Set to make every read throw, standing in for a blocked/failed IndexedDB. */
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
    };
  }

  get vaultMeta() {
    return this.table('vaultMeta');
  }

  // Dexie serialises writes here; in memory there is nothing to serialise, so the
  // body simply runs. applyBackupMerge's re-check inside it is what is under test.
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
  // The write paths, so the sections that reason about what an ordinary write
  // produces drive the real implementations rather than a restatement of them.
  'putEncrypted',
  'softDelete',
  // Stamps the `_del` index mirror. bulkPut does not fire Dexie's tombstone
  // hooks and encryptRecord strips the field, so every write site calls this
  // explicitly - which makes it a real dependency of applyBackupMerge.
  '_withDelIndex',
  // Read paths, so the sealed-table check on reads is driven for real.
  'getDecrypted',
  'listDecrypted',
]) {
  if (typeof SweetheartDatabase.prototype[method] !== 'function') {
    throw new Error(`test harness is stale: SweetheartDatabase has no ${method}()`);
  }
  FakeVaultStore.prototype[method] = SweetheartDatabase.prototype[method];
}

/* ------------------------------------------------------------------- suite */

async function run() {
  console.log('=== Our Space — crypto verification suite ===');

  const passphrase = 'my-super-secret-couple-passphrase-2026';
  const salt = generateSalt();

  /* --------------------------------------------------- 1. primitives */
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

  /* ----------------------------------------------- 2. KDF derivation */
  section('2. KDF derivation (X8)');

  // ONE COUNT. A vault still records the number it derives at, because a future
  // bump needs something to compare against and because unlock should be one
  // PBKDF2 run rather than a search - but nothing chooses between two counts any
  // more, and nothing a stranger sends gets to choose at all.
  check('every vault derives at 600,000 iterations', PBKDF2_ITERATIONS_CURRENT === 600000);

  // A vault whose recorded count is not the default. Cheap on purpose: what is
  // under test is that the RECORDED number is the one used, not the number.
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

  // The bug the whole mechanism exists to prevent.
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

  // VaultContext.unlockVault passes `meta.kdfIterations` straight through, so a
  // row that never recorded one has to land on the count every vault uses.
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

  /* ------------------------------------------ 3. passphrase handling */
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

  /* -------------------------------------------------------- 4. canary */
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
  // verifyPassphraseAgainstMeta derives at the one count there is, so its
  // fixture is built at that count rather than the fast one every other section
  // uses. This is the check that stops a typo producing a .vault file nobody can
  // ever open, so it is worth the real PBKDF2 runs.
  check(
    'verifyPassphraseAgainstMeta accepts the real passphrase',
    (await verifyPassphraseAgainstMeta(passphrase, uncountedMeta)) === true
  );
  check(
    'verifyPassphraseAgainstMeta rejects a typo (this is what stops an unopenable backup)',
    (await verifyPassphraseAgainstMeta(passphrase + 'x', uncountedMeta)) === false
  );

  /* ---------------------------------------------------------- 5. AEAD */
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

  /* ----------------------------------------- 6. record envelopes (v2) */
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

  // A hostile peer rewriting the plaintext header it can see without a key.
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

  /* ------------------------------ 6b. the photo bytes are bound too */
  section('6b. Photo bytes are bound into the envelope');

  // The hole this closes: the envelope authenticates the JSON payload, and the
  // photo is NOT in that payload - `imageBlob` rides at the top level so
  // IndexedDB stores real bytes. So one valid envelope for a memory id was
  // enough to destroy the photo under it: keep the envelope, swap the bytes, and
  // the row decrypted, reported an untampered header, and passed every gate.
  // Binding the header (0fa7116) did not touch this, because nothing about the
  // header changes when only the bytes do.
  check('an untouched row reports its binary as verified', back._binaryTampered === false);
  check('and not as merely unverified', back._binaryUnverified === false);
  check('the digest is not readable at rest', row._bin === undefined && row.imageBlob === blobBytes);

  const swappedBytes = new Uint8Array([9, 9, 9, 9, 9]); // same length, different content
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

  // A tombstone is sealed with no binary at all, so its digest map is EMPTY -
  // which is why bolting a photo onto one is detectable. An absent map means
  // something entirely different (see the pre-digest case below).
  const tombstone = await encryptRecord({ id: 'mem-abc123', updatedAt: 1750000000001, deleted: true }, key);
  const bolted = await decryptRecord({ ...tombstone, imageBlob: blobBytes }, key);
  check(
    'bolting a photo onto an envelope sealed without one is DETECTED',
    bolted._binaryTampered === true
  );

  // A caller cannot pre-supply the digest map: `_bin` is an internal field, so
  // encryptRecord drops it and hashes the real bytes itself.
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

  // BACKWARD COMPATIBILITY. Every v2 row already in a live vault was sealed
  // before this field existed and carries no digest map. Those must keep
  // opening, photo attached: a missing map is old, not forged. Only a WRONG map
  // is forged. Hand-built here because encryptRecord can no longer produce one.
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

  // A row with a photo bolted onto no envelope at all has nowhere to put a
  // digest, exactly as it has nowhere to put a bound header. It is not a
  // half-verified record - it is not a record (see section 7).
  await checkThrows(
    'and a photo bolted onto a row with no envelope is not a record at all',
    async () =>
      decryptRecord(
        { id: 'mem-no-envelope', updatedAt: 1690000000000, deleted: false, imageBlob: blobBytes },
        key
      ),
    (err) => /not a sealed record/.test(err.message)
  );

  /* --------------------------------- 7. there is one record shape */
  section('7. There is exactly one record shape');

  // The app briefly carried a second, older shape: metadata in PLAINTEXT and
  // indexed, each text field in its own `<name>Cipher` / `<name>Iv` pair. Its
  // plaintext id / updatedAt / deleted header was bound to nothing, so one
  // ciphertext made under the vault key could be aimed at any id at all - and
  // every forgery the sections below used to have to catch downstream started
  // exactly there.
  //
  // This is what "deleted" means, and it is the invariant the rest of this suite
  // now rests on: decryptRecord refuses anything that is not a complete
  // envelope, so such a row never becomes a record on any path at all.
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
  // An empty-string envelope trips the AES-GCM open rather than the shape check,
  // so the message differs - but the predicate every gate consults says no, and
  // that is what decides whether the row may be written.
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

  // The one shape, on the record that used to leak the most at rest.
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

  // A photo: bytes at the top level, everything describing them inside.
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

  /* ------------------------------------------------- 8. time locks */
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

  // The point of DECISION 3: the date is not a check that can be skipped.
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

  // Honest limit, stated in the README and the JSDoc: the vault owner can move
  // the clock. `now` is the same input a moved system clock supplies.
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

  /* --------------------------------------------------- 9. backups */
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

  // A .vault whose header does not say which count it used. The container
  // format has carried one since it existed, but a file is a file: nothing stops
  // a truncated or hand-edited one arriving without it, and falling back to the
  // one count there is beats refusing to open a backup that is perfectly good.
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

  /* --------------------------------------------------- 10. invites */
  section('10. Invite parsing (a stranger must not choose our PBKDF2 salt)');

  // Exactly what SyncHubModal builds: peer id, salt, display config.
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

  // The parameter is still supported for a channel that is already authenticated.
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
  // A link asking the joining phone to derive at 12 iterations is a link asking
  // for a weak key. The parameter is not validated any more because it is not
  // read any more - the joiner derives at the one count and nothing in the link
  // can move it.
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

  /* ------------------------------- 11. foreign backups (stable-id collision) */
  section('11. A foreign vault cannot overwrite a colliding live record');

  const NOW = Date.now();
  const MINUTE = 60 * 1000;

  // The two ids every vault built by this app shares, because they are derived
  // rather than random. They are the exact rows a blind bulkPut would destroy.
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
  // Stamped NEWER than the live rows on purpose: if precedence were the only
  // gate, the stranger's copy would win on merit. It has to be refused because
  // it does not decrypt, not because it happened to be older.
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
  /* ------------------ 11b. unauthenticated rows (the real RISK-1 hole) ------ */
  section('11b. A row carrying NO ciphertext cannot get into a table at all');

  // The adversarial review's finding, and the reason it is now structural.
  //
  // A row with no encrypted fields never exercises the key. The older record
  // shape had no envelope to demand, so such a row resolved without the key
  // being touched at all and the gate read that as "decrypted fine under our
  // key". Nobody needs a key to build one, and the seeded ids are identical in
  // every vault by construction, so this was a hand-writable overwrite of live
  // photos and letters.
  //
  // It used to be allowed to CREATE - unsealed rows had to be let in or an old
  // backup could not restore. That reason is gone, so it is refused outright now
  // whether or not anything already sits at the id.
  const bareTombstone = {
    id: 'bkt-default-1',
    updatedAt: NOW + MINUTE, // newer, so precedence alone would let it win
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

  // Now prove it end-to-end through the SHIPPED merge methods.
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

  // THE NEW RULE, and the whole point of deleting the older shape: an unsealed
  // row cannot even CREATE, at an id nothing has ever held.
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

  // applyBackupMerge must not trust a hand-built plan on the create path either.
  const bareSmuggle = await liveStore.applyBackupMerge({
    writes: [{ table: 'bucketList', row: bareCreate }],
    incomingWins: () => true,
  });
  check(
    'a hand-built plan cannot smuggle an unsealed row in as a creation',
    (bareSmuggle.written.bucketList || 0) === 0 && bareSmuggle.refusedSincePreview === 1
  );

  // Same hole existed on the wire path; same guard closes it. Lend peerSync the
  // key so the check under test is actually reached - without one it short
  // circuits on 'locked' and would pass for the wrong reason.
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

  // And the wire header check refuses the old version number before any of that.
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

  /* ------------- 11bis. decoy-ciphertext forgery (the old header hole) ----- */
  section('11bis. A decoy cipher pair is not a record');

  // The bypass an adversarial reviewer built against the first version of this
  // guard, kept as a permanent regression test.
  //
  // The old payload check only asked whether SOME ciphertext was present, and
  // the older record shape decrypted each `<base>Cipher` field on its own and
  // stamped `_headerTampered: false` unconditionally - it had no authenticated
  // copy of the header to disagree with. So ONE ciphertext made under the vault
  // key, and every backup ships one in its own vaultMeta canary, could be pasted
  // into a hand-built row as a decoy pair. The row decrypted, looked untampered,
  // and carried whatever id and `deleted: true` the forger chose. The attacker
  // needed the backup FILE passphrase and never the vault passphrase; it was
  // destroy-only, but that was quite enough.
  //
  // There is nothing left for a decoy to imitate. The gates ask for an envelope,
  // and a genuine ciphertext wearing a made-up field name is not one.
  //
  // The photo is sealed INTO the envelope (its digest is inside the payload),
  // exactly as db.putEncrypted writes it. Attaching the bytes to the row after
  // the fact would build a fixture the integrity check correctly rejects.
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

  // A real ciphertext under the vault key, standing in for the lifted canary.
  const decoy = await encryptText('anything at all', key);

  const forgedTombstone = {
    id: 'mem-1',
    updatedAt: NOW + MINUTE, // newer, so precedence would let it win
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

  // applyBackupMerge must not trust a hand-built plan either.
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

  // THE CHANGE THIS SECTION EXISTS TO RECORD: the same forgery aimed at an id
  // nothing holds used to be allowed to create, and that creation was the first
  // move of a longer chain (see 11sexies). It is refused now.
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

  /* -------- 11d. the photo-swap forgery, end to end on the import path ----- */
  section('11d. A swapped photo cannot ride in on a valid envelope');

  // The attacker here holds ONE genuine envelope for a memory id - lifted from
  // an old .vault file whose own file passphrase they know, or replayed by a
  // paired partner. They cannot edit it (AES-GCM), so they keep it verbatim and
  // replace only the bytes beside it. Before the digest binding, that row
  // decrypted, reported a clean header, passed sanitising and integrity, and
  // overwrote the only copy of the photo with garbage.
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

  /** The shape a row actually has inside a container: bytes as base64. */
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
  // The counter it lands in is load-bearing, not cosmetic: the preview renders
  // `undecryptable` as "could not be decrypted by this vault", which is what a
  // FOREIGN file looks like. This row decrypted perfectly under the live key and
  // was refused for a swapped photo, and reporting that as "wrong key" told the
  // user the reassuring story instead of the true one.
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

  // The wire path runs the same gate. _commitStagedRecords itself needs real
  // Dexie and cannot run here, but _verifyRecordIntegrity is pure and is what
  // decides whether a record is ever staged at all.
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

  // An honest restore of the very same rows still works - including a row
  // sealed before digest binding existed, which is the case that would brick
  // real photos if a missing digest were treated as a failure.
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

  /* ------------- 11ter. blob-length tie-break replay (no forgery needed) --- */
  section('11ter. A replayed envelope with a swapped photo cannot win the tie-break');

  // The third working exploit an adversarial reviewer built, kept as a guard.
  //
  // This one needed NO forgery at all. _fingerprint used to append
  // `blob:${imageBlob.byteLength}` and _incomingWins tie-break 2 compares
  // fingerprints lexicographically. So an attacker could replay a harvested
  // envelope byte for byte - same ciphertext, same iv, same updatedAt, nothing
  // re-encrypted, no vault passphrase - attach a garbage photo whose length in
  // decimal sorts high ('900' > '64'), and win the tie. The real photo was
  // overwritten and it landed in the `updated` counter, so every deletion
  // warning in the preview was bypassed too.
  const tieReplayBase = await encryptRecord(
    { id: 'mem-replay', updatedAt: NOW, deleted: false, caption: 'Real photo' },
    key
  );
  const tieRealPhoto = { ...tieReplayBase, imageBlob: new Uint8Array(64) };
  // Byte-for-byte identical envelope; only the unauthenticated blob differs.
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

  // End to end through the shipped merge.
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

  // A genuinely newer edit must still win - the fix must not freeze records.
  const tieGenuineEdit = await encryptRecord(
    { id: 'mem-replay', updatedAt: NOW + MINUTE, deleted: false, caption: 'Edited' },
    key
  );
  check(
    'a genuinely newer edit still wins',
    peerSync._incomingWins(tieRealPhoto, tieGenuineEdit) === true
  );

  /* ------------- 11quater. hostile rows must not create or crash ----------- */
  section('11quater. A hostile row cannot insert an invisible delete or abort the import');

  // Both from adversarial probes A4 and A6.
  //
  // A PERFECTLY SEALED tombstone on purpose. This rule is not about forgery: an
  // insert-a-delete at an id nothing holds destroys nothing, so no integrity
  // check has a reason to refuse it. It is refused because such a row is
  // INVISIBLE - every list filters on `deleted` - so the user can neither see
  // nor remove it, and it sits on a primary key that is identical in every
  // vault by construction.
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

  // A huge number as imageBlob used to throw RangeError OUTSIDE the try, which
  // aborted the whole restore; a merely large one allocated first, then failed.
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

  /* ------------- 11e. an envelope may not change tables -------------------- */
  section('11e. An envelope sealed for one table cannot be replayed into another');

  // The envelope binds id, updatedAt, deleted, and (since the digest map) the
  // attached bytes. It did NOT bind WHICH TABLE the row belongs to, and neither
  // import boundary supplied one: planBackupMerge iterates the container's own
  // keys, and _stageIncomingRecords trusts `item.table` off the wire. So a
  // genuine bucketList tombstone - correctly sealed, nothing rewritten, opening
  // perfectly under the vault key - could be moved into the `letters` array of a
  // container and was classified as a delete against a LIVE letter on that id.
  //
  // Only uuid arithmetic stood in the way: the fixed seed ids happen to live in
  // different tables. That is a property of today's seed data, not an invariant
  // anything enforces, which is why it is enforced here now.
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

  // The fix must not break the honest case: the SAME tombstone, in the table it
  // was actually sealed for, still deletes.
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

  // The sync path enforces it at the same point, against the peer's own claim.
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

  // COMPATIBILITY, and its price. An envelope sealed before the binding existed
  // carries none, and is reported `_tableUnverified` rather than tampered - the
  // same shape the binary digest uses, for the same reason: refusing them would
  // make every row already in a live vault unrestorable.
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

  // The gap this section used to document is now CLOSED, and re-sealing rows at
  // unlock was never going to close it - that only touches rows this device
  // HOLDS, while every gate decrypts the row ARRIVING. An envelope harvested
  // before binding existed would have stayed a permanent capability against that
  // id on every device however often either side re-sealed. So an absent binding
  // is its own verdict: `unverified` may CREATE, but never overwrite or delete.
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

  // An unbound row may still CREATE, so an older vault still restores.
  const unboundCreate = await encryptRecord(
    { id: 'let-from-old-vault', updatedAt: NOW, deleted: false, content: 'Old but honest' },
    key
  );
  const createGapPlan = await gapStore.planBackupMerge({ letters: [unboundCreate] }, key);
  check(
    'but an unbound row for an unused id still creates, so old backups restore',
    createGapPlan.totals.added === 1 && createGapPlan.totals.unauthenticated === 0
  );

  // AND IT STAYS THAT WAY, on this device and on the partner's. There is no
  // sweep re-sealing rows behind the user's back any more, so an envelope that
  // predates a binding keeps its create-only standing until the row is genuinely
  // edited - at which point putEncrypted seals it with the table, like every
  // other write.
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

  /* ------- 11quinquies. a HELD envelope is a capability against its id ----- */
  section('11quinquies. An unverified binding may create but never overwrite');

  // The structural point an adversarial reviewer made, and the reason re-sealing
  // rows at unlock was never the fix: a sweep re-seals the rows a device HOLDS,
  // while every gate decrypts the row ARRIVING. An envelope harvested before the
  // photo digest or the table binding existed is a permanent capability against
  // that id however often either side re-seals, so the verdict has to be carried
  // to the gate instead.
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

  // A pre-binding envelope: no table option, no digest map. Newer, so it would
  // win on timestamp alone.
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

  // The same envelope with the photo simply OMITTED erased it just as well.
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

  // But an unverified row must still be able to CREATE, or restoring a backup
  // taken before binding existed would be impossible.
  const qOldCreate = await encryptRecord(
    { id: 'mem-from-old-backup', updatedAt: NOW, deleted: false, caption: 'Honest and old' },
    key
  );
  const qOldCreatePlan = await qSweptStore.planBackupMerge({ memories: [qOldCreate] }, key);
  check(
    'an unverified row for an unused id still creates',
    qOldCreatePlan.totals.added === 1 && qOldCreatePlan.totals.unauthenticated === 0
  );

  // And a fully bound, genuinely newer row must still win, or records freeze.
  // The blob goes THROUGH encryptRecord so it lands in the digest map. Spreading
  // one on afterwards leaves an attached blob the envelope never sealed, which
  // is correctly reported as tampering.
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

  /* -------- 11sexies. the kill chain has no first move any more ----------- */
  section('11sexies. An attacker-authored row cannot be created, so there is nothing to launder');

  // The full kill chain an adversarial reviewer executed end to end, kept here
  // as the record of what the older shape actually cost.
  //
  // Attacker holds a harvested .vault FILE and its FILE passphrase. Never the
  // vault passphrase; they cannot read a single record. Destroy-only.
  //  1. Any row in the file yields a ciphertext/iv pair made under the vault
  //     key. Renamed to <base>Cipher/<base>Iv it satisfied the old payload
  //     check, because the older shape simply decryptText()d it.
  //  2. They aimed such a row at a real id with a chosen updatedAt and garbage
  //     bytes. Every tamper flag was stamped false by construction: there was no
  //     sealed header to disagree with.
  //  3. On a device that LACKS that id - a rescue restore onto a replacement
  //     phone, the app's own advertised flow - the create path accepted it. The
  //     preview read "Added: 1" with no warning anywhere.
  //  4. The unlock-time re-seal sweep then rebuilt it as a fully bound envelope
  //     over the attacker's id, timestamp, delete flag and bytes. THAT was the
  //     escalation, and patching it is the only reason provenance ever existed.
  //  5. It synced to the partner and destroyed the real photo, with no
  //     confirmation UI anywhere on that path.
  //
  // Steps 3 and 4 are both gone, and they are gone structurally rather than by
  // being guarded: nothing unsealed can be created, and no code path re-seals a
  // row behind the user's back.
  const sxDonor = await encryptRecord(
    { id: 'sxDonor', updatedAt: NOW, deleted: false, note: 'any row from the file' },
    key,
    { table: 'letters' }
  );
  // NOT a tombstone: those are refused at create on their own account (see
  // 11quater). This is the variant that mattered - an overwrite, which replaces
  // the letter body (and for a memory, the photo bytes) just as destructively.
  const sxForged = {
    id: 'let-victim',
    updatedAt: NOW + 60 * MINUTE,
    deleted: false,
    v: 1,
    // The decoy: a genuine ciphertext under the vault key, wearing an old name.
    contentCipher: sxDonor.ciphertext,
    contentIv: sxDonor.iv,
  };

  // STEP 2, control: straight at a device that HAS the id.
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

  // STEP 3 IS GONE. This is the assertion the whole deletion buys.
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

  // STEP 4 IS GONE. Guarded structurally so it cannot be reintroduced quietly.
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

  // HOW THE WIRE PATH RUNS IN PLAIN NODE, stated so nobody mistakes it for a
  // mock: _stageIncomingRecords, _verifyRecordIntegrity and _commitStagedRecords
  // below are the SHIPPED methods on the shipped singleton. Only their storage
  // moves - _commitStagedRecords reaches the `db` singleton, so that singleton's
  // `table` and `transaction` are pointed at a FakeVaultStore for the duration
  // and put back afterwards. The gate, the counters and the merge rule are real.
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

  // The victim device is fully swept: its own letter is bound on every
  // dimension. The partner is on the PREVIOUS build, so everything it sends is
  // sealed without a table binding - `unverified`, not tampered.
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

  /** Runs the real staging + commit for one wire record against a fresh store. */
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

  // The distinction has to cut both ways or it is just a rename.
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

  // The whole point of the split is what the user is told. `status.warning` is
  // rendered verbatim by Header.jsx and SyncHubModal.jsx with no allowlist of
  // codes, so emitting one is enough to put it on screen.
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
      // This copy is read by a couple, not an auditor. Guard the tone too, or it
      // drifts back the next time someone edits the message.
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

  /* ---- the tie-break must not be decided by an unauthenticated field ------ */

  // Same bug class as the blob byteLength d00b7c1 removed: a v2 envelope does
  // not seal the leftover `<base>Cipher` fields, so appending one used to hand
  // an attacker the tie-break on a byte-for-byte replay.
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
  // Two genuinely different envelopes at the same id and stamp must still be
  // broken deterministically, and both ways round, or the two devices keep
  // their own copy forever.
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

  // R2: restoring a backup taken before the binding shipped can only add rows.
  // The refusal is right; landing it in one counter labelled "not sealed to the
  // record it targets" told a user restoring their own rescue file nothing.
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

  // R4: applyBackupMerge's in-transaction re-check tested only
  // recordHasAuthenticatedHeader, which passes ANY well-formed v2 envelope -
  // including one sealed for a different table. A hand-built plan wrote a
  // bucketList envelope straight over a live letter.
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

  // The honest path must still work end to end, or this is just a lock on the
  // front door of an empty house.
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

  // R6: the sweep's "already bound on both dimensions, skip" continue used to
  // fire BEFORE its tampering counter, so the one row shape that proves somebody
  // went at the database directly - fully bound, photo bytes swapped underneath
  // - was skipped and counted as nothing at all.
  //
  // There is no sweep to count anything now, so the guarantee has to come from
  // the read itself, which is where it always mattered: all five screens that
  // render records test `_headerTampered` before displaying, and db.getDecrypted
  // is what sets it.
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

  // And no false positive on the clean row, or every photo would read as damaged.
  const snCleanStore = new FakeVaultStore({ memories: [snBound] });
  const snClean = await snCleanStore.getDecrypted('memories', 'mem-sn', key);
  check(
    'the untouched row is not flagged',
    snClean._headerTampered === false &&
      snClean._binaryTampered === false &&
      snClean._binaryUnverified === false
  );

  /* ---- 11nonies. no id can come to hold attacker-authored content --------- */
  section('11nonies. An id never comes to hold content this vault did not author');

  // Four chains an adversarial reviewer executed against the first provenance
  // fix. That fix marked ONE re-encrypt path (the sweep) while five others
  // re-authored freely, so the marker evaporated on the next ordinary write:
  //  A1  SecretCapsule's time-lock seal pass - a useEffect, no user gesture
  //      whatsoever - called putEncrypted and cleared it.
  //  A2  One tap on an unread letter (isOpened: true) did the same.
  //  A4  One checkbox tap on a bucket-list item, likewise.
  //  A3  Worst: a hostile peer creates a junk row, the user sees an
  //      unrecognisable card, taps Delete and confirms - and softDelete minted a
  //      fully AUTHENTICATED tombstone at that id, which replicated and erased
  //      the partner's real photo. The user's own caution was the weapon.
  //
  // Every one of those chains starts with a hostile row being CREATED at an id,
  // and that is what no longer happens. So "what standing does this row have?"
  // stops being a question the app has to carry per id, and the ordinary write
  // paths can author freely again - which is what makes a delete replicate.
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

  // A1/A2/A4: the ordinary write paths, which used to have to inherit a reduced
  // standing from whatever sat at the id.
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

  // A3: and the one that cost the most - a delete the partner actually applies.
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

  /* ------- 11decies. equal-timestamp delete vs edit must still reconcile ---- */
  section('11decies. A same-instant delete is pulled instead of diverging forever');

  // Reported by the project owner. _diffManifest skipped equal timestamps
  // outright to avoid two devices requesting from each other forever - but
  // _incomingWins has a tie-break saying a deletion beats a same-instant edit,
  // and that rule never got the chance to run. Phone A edits an item, phone B
  // deletes it in the same millisecond, neither asks for the other's copy, and
  // the two stay out of step on that record permanently.
  const dmLocal = [{ id: 'x1', updatedAt: NOW, deleted: false }];
  const dmRemoteDeleted = [{ id: 'x1', updatedAt: NOW, deleted: true }];

  // _diffManifest is the SHIPPED method; only the local manifest it reads is
  // supplied here, the same way withFakeDb swaps db.table for the write tests.
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

  // The mirror case must NOT request, or the two devices ping-pong forever.
  const dmNoPull = await dmDiff(
    [{ id: 'x1', updatedAt: NOW, deleted: true }],
    [{ id: 'x1', updatedAt: NOW, deleted: false }]
  );
  check(
    'the reverse case asks for nothing - exactly one side pulls, so no ping-pong',
    dmNoPull.length === 0
  );

  // Two same-instant edits still must not request, for the same reason.
  const dmBothLive = await dmDiff(dmLocal, [{ id: 'x1', updatedAt: NOW, deleted: false }]);
  check('two same-instant edits still do not loop', dmBothLive.length === 0);

  // And genuinely newer still wins, as before.
  const dmNewer = await dmDiff(dmLocal, [{ id: 'x1', updatedAt: NOW + 1000, deleted: false }]);
  check('a genuinely newer remote row is still requested', dmNewer.length === 1);

  /* -------- 11undecies. tombstones must survive a bulk write ---------------- */
  section('11undecies. A tombstone written in bulk keeps its `_del` index mirror');

  // Reported by the project owner. Dexie's `creating`/`updating` hooks keep
  // `_del` in step with `deleted`, but they DO NOT FIRE for bulkPut/bulkAdd -
  // and encryptRecord strips `_del`, because it is local bookkeeping that must
  // never be sealed into an envelope or put on the wire.
  //
  // So every row written in bulk landed with `_del` undefined. getManifest()
  // reads tombstones off `where('_del').equals(1)`, so a restored tombstone was
  // advertised to the partner as deleted:false - and a deleted memory came back
  // from the dead on the next sync.
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

  // End to end through the shipped restore path, which writes with bulkPut.
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

  /* ------- 11duodecies. a rolled-back clock must not poison sync forever --- */
  section('11duodecies. A future clock does not permanently future-date this phone');

  // Reported by the project owner. The sync clock floor is monotonic on purpose,
  // which made a clock change permanent: set the phone's date to next year -
  // exactly what someone does to peek at a time-locked letter - save anything,
  // and the floor is stamped a year ahead. Put the clock back and the floor
  // stays, because it only moves forward. Every record written from then on is
  // dated in the future and the partner refuses all of them until real time
  // catches up.
  const clkKey = 'sweetheart_sync_clock'; // must match SYNC_CLOCK_KEY in peerSync.js
  const clkSavedRemote = peerSync._observedRemoteMax;
  const clkSavedIssued = peerSync._lastIssuedStamp;

  // getSyncSafeTimestamp guards every storage access on
  // `typeof localStorage !== 'undefined'`, so under plain node the floor is
  // always 0 and the branch under test never runs. A minimal shim makes the
  // real code path live; it is removed again in the finally below.
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
    // Simulate the poisoned floor a future-dated save leaves behind.
    localStorage.setItem(clkKey, String(Date.now() + YEAR_MS));
    peerSync._observedRemoteMax = 0;
    // Earlier sections drive the same singleton, so isolate the in-session
    // high-water mark too or their stamps leak into this one.
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

    // A partner with a wild clock must not be able to push us arbitrarily far
    // forward either. It is clamped to the same ceiling the wire enforces
    // (now + 24h), NOT to now: a partner legitimately a few hours ahead should
    // still win a merge, which is the whole point of the high-water mark.
    const DAY_MS = 24 * 60 * 60 * 1000;
    peerSync._observedRemoteMax = Date.now() + YEAR_MS;
    const clkStamp2 = peerSync.getSyncSafeTimestamp();
    check(
      'a far-future remote high-water mark is clamped to the wire ceiling, not obeyed',
      clkStamp2 <= Date.now() + DAY_MS + 1000 && clkStamp2 < Date.now() + 2 * DAY_MS
    );

    // Normal operation is unchanged: still monotonic, still ahead of the last.
    // This used to be flaky roughly one run in five, and the flake was a real
    // bug: after the remote high-water mark pushed a stamp near the ceiling, the
    // next call clamped back to now and issued an EARLIER stamp than the one
    // before it. _lastIssuedStamp is what makes it a guarantee.
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

  /* ------- 11terdecies. reads must check the sealed table binding too ------ */
  section('11terdecies. A cross-table row is spotted on read, not just on write');

  // Reported by the project owner. decryptRecord can flag `_tableTampered`, but
  // only when it is told which table it is reading - and getDecrypted and
  // listDecrypted never passed one. The write gates refuse a cross-table row an
  // overwrite, but the create path is deliberately permissive, so such a row CAN
  // be sitting in a table. Every screen would have rendered it as ordinary
  // content, because a read that does not ask cannot notice.
  const xtRow = await encryptRecord(
    { id: 'xt-1', updatedAt: NOW, deleted: false, content: 'sealed for letters' },
    key,
    { table: 'letters' }
  );
  // Same row, filed under bucketList - what the permissive create path allows.
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

  // A row sealed before the table binding existed must still read cleanly, or
  // every pre-binding record would vanish from the UI.
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

  /* ------- 11quaterdecies. every decryptRecord call must name its table ---- */
  section('11quaterdecies. No read path may skip the sealed-table check');

  // This drifted twice. First getDecrypted/listDecrypted were fixed while the
  // five screens still called decryptRecord directly - and that commit message
  // claimed no component changes were needed, which was wrong, because the
  // screens never go through those helpers at all. A source check is the only
  // thing that actually holds the invariant: `{ table }` is optional in the
  // signature (pre-binding rows legitimately have none), so no type or runtime
  // check can catch a caller that simply forgets it.
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

  /** Strips comments so prose mentions of decryptRecord() are not read as calls. */
  const stripComments = (src) =>
    src.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1 ');

  /** Returns the argument text of every decryptRecord( ... ) call. */
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

  // crypto.js DEFINES decryptRecord, so it has no caller-supplied table to pass
  // on.
  const TABLE_CHECK_SKIP = new Set([join('src', 'services', 'crypto.js')]);

  const offenders = [];
  for (const file of walkSrc('src')) {
    if (TABLE_CHECK_SKIP.has(file)) continue;
    for (const args of callArgs(stripComments(readFileSync(file, 'utf8')))) {
      // Accepts `{ table: x }` and the `{ table }` shorthand alike.
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

  // ImportPreview had branches for 'foreign' and 'no-local-vault' and none for
  // 'unknown', so a file carrying no readable vault identity rendered exactly
  // like the user's own backup: counts, no banner, a live Merge button. These
  // assertions pin the classification that branch keys off, and the reason the
  // branch is a WARNING rather than an extra confirmation gate: identity is a
  // label, the per-row key check is the actual gate.
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

  // The justification for leaving Merge live on an unknown-origin file: a row is
  // written only when it authenticates under THIS vault's key, whatever the
  // file's (missing) vaultMeta says. Mixed file, no identity at all.
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

  /* --------------------------------- 12. merge precedence is peerSync's rule */
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

  // Proof it is not a second rule: swap peerSync's method for a spy and watch
  // the merge call it. A local copy of the comparison would not touch this.
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

  // The rule the plan carries must agree with the sync rule everywhere, not just
  // on the easy "newer wins" case - including both documented tie-breaks.
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

  // Fail closed: no rule, no merge. A home-grown fallback is exactly what would
  // let a merge and a sync disagree about which copy of a letter is newer.
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

  // A live sync landing a newer copy between the preview and the confirmation.
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

  /* ------------------------------------------------ 13. rescue restore */
  section('13. Rescue restore — adopt an identity, unlock with the ORIGINAL passphrase');

  const rescuePassphrase = 'the-passphrase-she-actually-remembers-2026';
  const filePassphrase = 'a-different-file-passphrase-entirely';
  const rescueSalt = generateSalt();
  // Deliberately NOT the fast key every other section uses: this section drives
  // verifyPassphraseAgainstMeta, which derives at the one count there is, so the
  // fixture has to be a vault a real device could have written.
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

  // The whole promise of the rescue file: a cold unlock from the stored row alone.
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

  // The same rescue, from a file whose vaultMeta never recorded a count at all.
  // Nothing this app writes looks like that, but a file is a file: a truncated
  // or hand-edited container must still open rather than reporting a wrong
  // passphrase forever. (The salt and key are section 2's, so this costs no
  // extra PBKDF2 runs.)
  const uncountedRescueRow = {
    id: 'config',
    salt: uncountedSalt,
    // No kdfIterations at all.
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

  /* ------------------------------------------------ 14. import sanitising */
  section('14. Import sanitising — a restored clock artefact must not win forever');

  // The import ceiling (db MAX_BACKUP_CLOCK_SKEW_MS) and the wire ceiling
  // (peerSync MAX_CLOCK_SKEW_MS) must be the SAME number. They were 48h and 24h
  // while a comment claimed they matched, and the gap was not cosmetic - see the
  // +30h case at the end of this section.
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

  /** Plans one record against an empty device and returns just the counters. */
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

  // THE TWO CEILINGS MUST AGREE. At 48h import / 24h wire, a row stamped +30h
  // was accepted by planBackupMerge and then refused by _validateWireRecord as
  // `future_timestamp` - so a row the user had just restored from their own
  // rescue backup sat on their device unable to reach their partner until the
  // clock caught up, with nothing anywhere saying why.
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

  /* ---------------------------------------------- 15. tamper isolation */
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
  // A peer that cannot decrypt can still edit the plaintext header it can see.
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

  /* ------------------------------------------------- 15b. finding a route */
  //
  // A malformed iceServers list does not fail loudly - it just means the two
  // phones never connect, which looks identical to bad luck with the network.
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

  // Half a configuration is worse than none: a relay with the wrong
  // credentials does not complain, it just never connects.
  const iceHalf = ice.resolveTurnConfig({ VITE_TURN_URLS: 'turn:my.relay:3478' });
  check(
    'a half-configured relay is ignored rather than half-applied',
    iceHalf.username === 'openrelayproject'
  );

  /* ------------------------------------------- 16. love bursts, as records */
  //
  // These used to be a fire-and-forget wire message, so one sent to a phone
  // that was not listening simply never happened. They are records now, which
  // is what makes the offline case work at all - and the offline case is the
  // whole point, so it is what most of this section is about.
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

  /* -- sending, with nobody on the other end ------------------------------ */

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

  /* -- and the sender is never told about their own ----------------------- */

  const burstOwn = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('a device never celebrates its own tally', burstOwn.total === 0);

  /* -- the partner side --------------------------------------------------- */

  // The module caches its owner id, so the test drives the partner side by
  // writing her tally straight in rather than pretending to be her device.
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

  // A device looking for the FIRST time at a tally that is already at three:
  // a phone that just restored a backup, or had its storage cleared. Greeting
  // her with "3 love bursts" she has in fact already seen would be a bug
  // wearing a nice hat, so the absence of any memory means start from today.
  burstLocal.delete('sweetheart_burst_seen_v1');
  const burstFirstLook = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'a first look adopts the tally where it stands instead of replaying history',
    burstFirstLook.total === 0
  );

  /* -- THE POINT: bursts sent while he was away ---------------------------- */

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

  /* -- and are not replayed on the next launch ---------------------------- */

  bursts.markBurstsSeen(burstAway.records);
  const burstAgain = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('once shown, the same bursts are not counted again', burstAgain.total === 0);

  await putHerTally(7, burstClock);
  const burstOneMore = await bursts.collectUnseenBursts(key, { store: burstStore });
  check('but the next one still lands', burstOneMore.total === 1);
  bursts.markBurstsSeen(burstOneMore.records);

  /* -- a tally that goes backwards is not a negative burst ---------------- */

  await putHerTally(2, burstClock);
  const burstBackwards = await bursts.collectUnseenBursts(key, { store: burstStore });
  check(
    'a tally that somehow went backwards is ignored, not counted as negative',
    burstBackwards.total === 0
  );

  /* -- a rewritten record is not evidence of anything --------------------- */

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

  /* ============================================================== 17
   * QUICK UNLOCK (fingerprint / face)
   *
   * The real biometricUnlock.js runs here. Only two things are faked, and
   * both are storage-shaped: localStorage, and the authenticator itself.
   *
   * The fake authenticator behaves like a real one where it matters - the
   * same credential and the same salt produce the same 32 bytes, a different
   * credential produces different bytes, and a dismissed prompt throws
   * NotAllowedError. Everything the module does with those bytes is its own.
   */
  section('17. Quick unlock: sealing the vault key behind the phone sensor');

  const bioB64 = (bytes) => Buffer.from(bytes).toString('base64');

  /** Decrypts, or resolves null. A wrong key must fail a check, not crash the run. */
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
      // A provider that says up front it will not do PRF. Believing it saves a
      // second fingerprint prompt that could only ever fail.
      denyPrfAtCreateNext(v) {
        denyPrfAtCreate = v;
      },
      // The Android symptom: the fingerprint check passes, and the passkey
      // store simply does not do PRF.
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
            // Like Chrome: PRF is enabled on create but returns no results,
            // which forces the module down its second-ceremony path.
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
  /** Everything the app has asked the passkey provider to forget. */
  const retired = [];
  const fakeAuth = makeFakeAuthenticator();

  const define = (name, value) =>
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });

  // window must carry the real crypto/btoa/atob: crypto.js reaches for
  // window.* the moment one exists, and every other section still needs it.
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

  /* -- the two new crypto primitives agree with the old derivation ------- */

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

  /* -- enrol, then unlock ------------------------------------------------ */

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

  /* -- a dismissed prompt must NOT destroy the enrolment ------------------ */

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

  /* -- a sealed key is bound to ITS vault --------------------------------- */

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

  /* -- tampering with the sealed blob ------------------------------------- */

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

  /* -- another phone cannot open it --------------------------------------- */

  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });
  // Same stored blob, different authenticator secret: exactly what copying
  // localStorage to another device would look like.
  for (const id of fakeAuth.secrets.keys()) {
    fakeAuth.secrets.set(id, crypto.getRandomValues(new Uint8Array(32)));
  }
  await checkThrows(
    'the sealed key is useless to a different authenticator',
    () => bio.unlockWithBiometric(bioSalt),
    (err) => err.code === 'stale'
  );

  /* -- the normalize flag is honoured, not assumed ------------------------ */

  // A vault keyed on the RAW string, trailing space and all - what a phone
  // keyboard produced before normalizePassphrase existed. Sealing the
  // normalised bits here would unseal perfectly and then decrypt nothing.
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

  /* -- a store that verifies but will not do PRF -------------------------- */

  // This is precisely what a passkey store without PRF looks like from here:
  // the fingerprint check passes, and no key material comes back. It has to be
  // its own answer - 'cancelled' would be a lie, and silence was the bug.
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

  /* -- transports are remembered for the next ceremony -------------------- */

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

  /* -- a provider that declines PRF up front is believed the first time ---- */

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

  /* -- retired ids are base64url, which is what the Signal API reads -------- */

  check(
    'the retired credential id carries no +, / or = padding',
    retired.length === 1 && !/[+/=]/.test(retired[0].credentialId)
  );
  check(
    'and it names the right relying party',
    retired.length === 1 && retired[0].rpId === 'localhost'
  );

  /* -- a half-written record is "not set up", not a permanent failure ------ */

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

  /* -- only an auth-tag failure may destroy a working enrolment ------------ */

  bio.forgetBiometricUnlock();
  await bio.enableBiometricUnlock({
    passphrase: bioPass,
    vaultSalt: bioSalt,
    iterations: bioIters,
    normalize: true,
  });

  // A transient failure that is NOT AES-GCM rejecting the tag. Wiping on this
  // would throw away a perfectly good setup and quietly demote her to typing
  // the passphrase forever.
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

  /* -- re-enrolling for a NEW vault does not orphan the old passkey --------- */

  // Starting a new space mints a new salt, which strands the sealed key. The UI
  // offers "Set it up" in that state and never "Turn off", so if this path could
  // not clear the old record by itself she would have no way through at all.
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

  /* -- turning it off retires the passkey too ------------------------------ */

  retired.length = 0;
  const bioLiveId = JSON.parse(Array.from(bioStore.values())[0]).credentialId;
  bio.forgetBiometricUnlock();
  check(
    'turning quick unlock off retires its passkey rather than orphaning it',
    retired.length === 1 &&
      retired[0].credentialId === bioLiveId.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  );

  /* -- forgetting it ------------------------------------------------------ */

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


  /* =============================================================== 18
   * THE DAILY QUESTION
   *
   * The whole feature rests on one claim: two phones that have not spoken
   * all week still land on the same question. Nothing coordinates that - it
   * falls out of both holding the same key - so it is what most of this
   * section is about.
   */
  section('18. The daily question: same question, both phones, no server');

  const dq = await import('./src/services/dailyQuestion.js');
  const bank = await import('./src/data/dailyQuestions.js');

  /* -- the bank itself ----------------------------------------------------- */

  const dqIds = bank.ALL_QUESTIONS.map((x) => x.id);
  check('every question has a unique id', new Set(dqIds).size === dqIds.length);
  check(
    'and no two questions are the same text',
    new Set(bank.ALL_QUESTIONS.map((x) => x.text)).size === bank.ALL_QUESTIONS.length
  );
  // A handful end in a full stop on purpose - the ones whose tail is an
  // instruction ("and be honest.") read wrong with a question mark on the end.
  check(
    'every question is a real prompt, not a placeholder',
    bank.ALL_QUESTIONS.every(
      (x) => x.text.length > 20 && /[?.]$/.test(x.text.trim()) && !/TODO|FIXME|xxx/i.test(x.text)
    )
  );

  /* -- THE POINT: both phones agree, having never spoken -------------------- */

  // Her phone. Same passphrase and salt, so the same key - derived separately,
  // exactly as it would be on a device that has never connected to his.
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

  /* -- no repeats, which plain modulo could not manage ---------------------- */

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

  /* -- appending a batch does not disturb the one already in progress ------- */

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

  /* -- answers: one record per person per MONTH ----------------------------- */

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

  /* -- THE GATE: her answer is not readable until yours exists -------------- */

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

  /* -- the archive honours the same gate ------------------------------------ */

  // A day only she answered. It must not appear in his archive either, or the
  // gate would just be a different door into the same room.
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

  /* -- a rewritten answer record is not evidence of anything ---------------- */

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


  /* ------------------------------------------------------- verdict */
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
