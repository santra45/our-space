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
 *   2. KDF versioning        600k for new vaults, 250k retained for old ones
 *   3. Passphrase handling   NFKC normalisation, trimming, verified derivation
 *   4. Canary                passphrase proof used by unlock, pairing and backup
 *   5. AEAD                  associated data actually binds
 *   6. Record envelopes      schema v2, metadata genuinely encrypted at rest
 *  6b. Bound photo bytes    a swapped blob under a valid envelope is detected,
 *                           and a pre-digest row still opens
 *   7. v1 -> v2 migration    round-trip of the exact reshaping db does
 *   8. Time locks            seal/unseal, and that the date is BOUND, not checked
 *   9. Backups               v2 containers, and v1 containers still opening
 *  10. Invites               a stranger's link cannot choose our PBKDF2 salt
 *  11. Foreign backups       a stranger's file cannot overwrite a colliding id
 * 11d. Photo-swap forgery   a kept envelope plus swapped bytes is refused on
 *                           both the import and the sync gate
 * 11e. Table binding       an envelope sealed for one table cannot be replayed
 *                           into another, and the pre-binding carve-out drains
 *  12. Merge precedence      an older backup does not revert newer local work
 *  13. Rescue restore        adopt an identity, unlock with the ORIGINAL phrase
 *  14. Import sanitising     a restored clock artefact cannot win forever
 *  15. Tamper isolation      one bad record does not poison the whole restore
 *
 * HOW SECTIONS 11-15 REACH db/index.js WITHOUT A BROWSER
 * `planBackupMerge`, `applyBackupMerge`, `restoreVaultIdentity`,
 * `readVaultIdentity`, `exportRawDataForBackup` and `migrateLegacyRecords` are
 * methods on a Dexie subclass, but the only Dexie surface they touch is
 * `table(name)` with get/put/toArray/bulkGet/bulkPut/toCollection().primaryKeys(),
 * `transaction()` and `vaultMeta`. So
 * `FakeVaultStore` below supplies exactly that in memory and the SHIPPED methods
 * are then borrowed onto it verbatim. The storage underneath is fake; none of
 * the logic on top of it is. The precedence rule really is fetched out of
 * peerSync at call time - section 12 proves that with a spy rather than assuming
 * it.
 *
 * WHAT THIS SUITE CANNOT COVER (nothing below is stubbed to look covered)
 *  - Dexie's own `version(2).upgrade()` callback and the `blocked` event that
 *    drives isUpgradeBlocked()/subscribeUpgradeBlocked(). Both need a real
 *    IndexedDB with two live connections. Section 7 covers the record reshaping
 *    `db.migrateLegacyRecords()` performs and section 11e runs the shipped
 *    method itself against the in-memory store - the parts that can lose data -
 *    but not the schema upgrade around them.
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
 *  - peerSync's transport half: admission control, per-peer backoff, the flood
 *    breaker and _emitFatal closing the connection. Those need PeerJS/WebRTC.
 *    Only the pure merge rule (_incomingWins/_fingerprint) is exercised here.
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
  normalizePassphrase,
  resolveKdfIterations,
  PBKDF2_ITERATIONS_CURRENT,
  PBKDF2_ITERATIONS_LEGACY,
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
  isLegacyRecord,
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
  recordCarriesAuthenticatedPayload,
  recordHasAuthenticatedHeader,
} from './src/services/crypto.js';
import { buildInviteUrl, parseInvite } from './src/utils/invite.js';
import {
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
      // The only Collection surface migrateLegacyRecords() touches.
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
  'migrateLegacyRecords',
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

  /* ----------------------------------------------- 2. KDF versioning */
  section('2. KDF versioning (X8)');

  check('new vaults derive at 600,000 iterations', PBKDF2_ITERATIONS_CURRENT === 600000);
  check('legacy vaults are pinned at 250,000', PBKDF2_ITERATIONS_LEGACY === 250000);
  check(
    'a vaultMeta row with no kdfIterations means 250,000',
    resolveKdfIterations({ salt }) === PBKDF2_ITERATIONS_LEGACY
  );
  check(
    'a recorded count is honoured',
    resolveKdfIterations({ kdfIterations: 600000 }) === 600000
  );
  check(
    'an absurd recorded count falls back rather than being trusted',
    resolveKdfIterations({ kdfIterations: 3 }) === PBKDF2_ITERATIONS_LEGACY
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

  // A vault created by an old build: 250k iterations, no kdfIterations recorded.
  const legacySalt = generateSalt();
  const legacyKey = await deriveKeyFromPassphrase(passphrase, legacySalt, {
    iterations: PBKDF2_ITERATIONS_LEGACY,
  });
  const legacyMeta = {
    salt: legacySalt,
    ...(await createCanary(legacyKey, { coupleNames: 'Us', startDate: '2021-06-14' })),
  };

  const opened = await deriveKeyWithVerification(
    passphrase,
    legacySalt,
    async (candidate) => (await readCanary(candidate, legacyMeta)) !== null,
    { iterations: resolveKdfIterations(legacyMeta) }
  );
  check(
    'a 250,000-iteration vault still unlocks after the bump to 600,000',
    opened.iterations === PBKDF2_ITERATIONS_LEGACY
  );

  // The bug the whole mechanism exists to prevent.
  await checkThrows(
    'a bare 2-arg derive against a legacy vault produces the WRONG key',
    async () => {
      const wrong = await deriveKeyFromPassphrase(passphrase, legacySalt);
      const canary = await readCanary(wrong, legacyMeta);
      if (canary === null) throw new Error('wrong key, as expected');
      return canary;
    },
    (err) => err.message.includes('as expected')
  );

  const spaced = await deriveKeyWithVerification(
    `  ${passphrase}  `,
    legacySalt,
    async (candidate) => (await readCanary(candidate, legacyMeta)) !== null,
    { iterations: PBKDF2_ITERATIONS_LEGACY }
  );
  check('a pasted passphrase with stray whitespace still opens the vault', spaced.normalized === true);

  await checkThrows(
    'a genuinely wrong passphrase is refused after every candidate',
    async () =>
      deriveKeyWithVerification(
        'definitely-not-the-right-passphrase',
        legacySalt,
        async (candidate) => (await readCanary(candidate, legacyMeta)) !== null,
        { iterations: PBKDF2_ITERATIONS_LEGACY }
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
  check(
    'verifyPassphraseAgainstMeta accepts the real passphrase',
    (await verifyPassphraseAgainstMeta(passphrase, meta)) === true
  );
  check(
    'verifyPassphraseAgainstMeta rejects a typo (this is what stops an unopenable backup)',
    (await verifyPassphraseAgainstMeta(passphrase + 'x', meta)) === false
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
  check('a v2 row does not ask to be re-encrypted', back._needsReencrypt === false);
  check('an untouched row is not flagged as tampered', back._headerTampered === false);
  check('isLegacyRecord is false for a v2 row', isLegacyRecord(row) === false);

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
  // something entirely different (see the legacy case below).
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

  // v1 has nowhere to put a digest, exactly as it has nowhere to put a bound
  // header. Both tamper flags are false because nothing is knowable, which is
  // why v1 rows may only ever CREATE (see 11bis).
  const v1WithPhoto = await decryptRecord(
    { id: 'mem-v1-photo', updatedAt: 1690000000000, deleted: false, v: 1, imageBlob: blobBytes },
    key
  );
  check('a v1 photo is reported unverified, never verified', v1WithPhoto._binaryUnverified === true);
  check('and never falsely flagged as tampered', v1WithPhoto._binaryTampered === false);

  /* -------------------------------------- 7. v1 -> v2 migration path */
  section('7. v1 → v2 migration round-trip (DECISION 2)');

  // A genuine pre-migration `letters` row: metadata in PLAINTEXT and indexed,
  // each text field in its own `<name>Cipher` / `<name>Iv` pair. This is exactly
  // the shape Dexie's version(2).upgrade() leaves behind for the keyed sweep.
  const v1Title = await encryptText('Read me on our anniversary', key);
  const v1Content = await encryptText('You still make me laugh every single day.', key);
  const v1Row = {
    id: 'let-legacy-001',
    updatedAt: 1700000000000,
    deleted: false,
    unlockDate: '2027-06-14',
    isOpened: false,
    titleCipher: v1Title.ciphertext,
    titleIv: v1Title.iv,
    contentCipher: v1Content.ciphertext,
    contentIv: v1Content.iv,
    v: 1,
    needsReencrypt: 1,
    _del: 0,
  };

  check('isLegacyRecord identifies a v1 row', isLegacyRecord(v1Row) === true);
  check('v1 leaked its metadata in plaintext', v1Row.unlockDate === '2027-06-14');

  // Step 1: read it with the key, exactly as db.migrateLegacyRecords does.
  const v1Decrypted = await decryptRecord(v1Row, key);
  check('v1 titleCipher decrypts to `title`', v1Decrypted.title === 'Read me on our anniversary');
  check(
    'v1 contentCipher decrypts to `content`',
    v1Decrypted.content === 'You still make me laugh every single day.'
  );
  check('v1 plaintext metadata survives the read', v1Decrypted.unlockDate === '2027-06-14');
  check('v1 rows are reported as schema 1', v1Decrypted._schemaVersion === 1);
  check('v1 rows are flagged for re-encryption', v1Decrypted._needsReencrypt === true);
  check(
    'the raw *Cipher/*Iv pairs are consumed, not carried through',
    v1Decrypted.titleCipher === undefined && v1Decrypted.titleIv === undefined
  );
  check(
    'envelope bookkeeping never leaks into the logical record',
    v1Decrypted.v === undefined && v1Decrypted.needsReencrypt === undefined && v1Decrypted._del === undefined
  );

  // Step 2: re-seal, preserving identity and ordering (a migration is not an edit).
  const forRewrite = { ...v1Decrypted };
  delete forRewrite._schemaVersion;
  delete forRewrite._needsReencrypt;
  delete forRewrite._headerTampered;
  const v2Row = await encryptRecord(forRewrite, key);

  check('the migrated row is v2', v2Row.v === RECORD_SCHEMA_VERSION);
  check('the id is preserved (sync addresses records by id)', v2Row.id === v1Row.id);
  check(
    'updatedAt is preserved, so no peer sees a spurious update',
    v2Row.updatedAt === v1Row.updatedAt
  );
  check('the tombstone flag is preserved', v2Row.deleted === false);
  check('MIGRATED: unlockDate is no longer readable at rest', v2Row.unlockDate === undefined);
  check('MIGRATED: isOpened is no longer readable at rest', v2Row.isOpened === undefined);
  check(
    'MIGRATED: the old *Cipher fields are gone from the row',
    v2Row.titleCipher === undefined && v2Row.contentCipher === undefined
  );

  // Step 3: everything is still readable afterwards. This is the data-loss test.
  const v2Decrypted = await decryptRecord(v2Row, key);
  check('MIGRATED: title survived', v2Decrypted.title === 'Read me on our anniversary');
  check(
    'MIGRATED: content survived',
    v2Decrypted.content === 'You still make me laugh every single day.'
  );
  check('MIGRATED: unlockDate survived inside the envelope', v2Decrypted.unlockDate === '2027-06-14');
  check('MIGRATED: isOpened survived inside the envelope', v2Decrypted.isOpened === false);
  check('MIGRATED: the row no longer asks to be re-encrypted', v2Decrypted._needsReencrypt === false);

  // Idempotence: the sweep runs on every unlock and must be a no-op the second time.
  check('re-running the sweep is a no-op (isLegacyRecord false)', isLegacyRecord(v2Row) === false);

  // A v1 row that will not decrypt must be LEFT ALONE, never rewritten empty.
  await checkThrows('a v1 row under the wrong key throws rather than migrating to nothing', async () =>
    decryptRecord(v1Row, wrongKey)
  );

  // Memories carried a binary blob through the same migration.
  const v1Caption = await encryptText('Bali, 2019', key);
  const v1Memory = {
    id: 'mem-legacy-002',
    updatedAt: 1690000000000,
    deleted: false,
    date: '2019-08-02',
    captionCipher: v1Caption.ciphertext,
    captionIv: v1Caption.iv,
    imageBlob: blobBytes,
    v: 1,
  };
  const migratedMemory = await decryptRecord(v1Memory, key);
  const rewrittenMemory = await encryptRecord(
    (({ _schemaVersion, _needsReencrypt, _headerTampered, ...rest }) => rest)(migratedMemory),
    key
  );
  const finalMemory = await decryptRecord(rewrittenMemory, key);
  check('MIGRATED: a photo caption survived', finalMemory.caption === 'Bali, 2019');
  check('MIGRATED: the photo date moved into the envelope', rewrittenMemory.date === undefined);
  check(
    'MIGRATED: the encrypted image bytes are untouched',
    eq(Array.from(finalMemory.imageBlob), Array.from(blobBytes))
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

  // A .vault written by an older build: genuinely encrypted at 250,000, and
  // with no kdfIterations field to say so. Raising the constant must not have
  // turned every backup anyone already holds into a brick.
  const oldSalt = generateSalt();
  const oldKey = await deriveKeyFromPassphrase(backupPassphrase, oldSalt, {
    iterations: PBKDF2_ITERATIONS_LEGACY,
  });
  const oldBody = await encryptText(JSON.stringify(rawVault), oldKey);
  const v1Container = {
    magic: container.magic,
    version: 1,
    salt: oldSalt,
    iv: oldBody.iv,
    ciphertext: oldBody.ciphertext,
    exportedAt: '2024-01-01T00:00:00.000Z',
  };
  check(
    'a v1 backup (250,000, no kdfIterations recorded) still opens',
    eq(await decryptBackupContainer(v1Container, backupPassphrase), rawVault)
  );
  await checkThrows(
    'a v1 backup still refuses the wrong passphrase',
    async () => decryptBackupContainer(v1Container, 'not-the-backup-passphrase'),
    (err) => /Incorrect backup passphrase/.test(err.message)
  );
  await checkThrows(
    'a container with a foreign magic header is rejected outright',
    async () => decryptBackupContainer({ ...v1Container, magic: 'SOMETHING_ELSE' }, backupPassphrase),
    (err) => /unrecognized container header/.test(err.message)
  );

  /* --------------------------------------------------- 10. invites */
  section('10. Invite parsing (a stranger must not choose our PBKDF2 salt)');

  // Exactly what SyncHubModal builds: peer id, salt, KDF count, display config.
  const inviteUrl = buildInviteUrl('love-A1B2C3D4E5F6G7H8', salt, {
    baseUrl: 'https://our-space.example/',
    startDate: '2021-06-14',
    coupleNames: 'Alex & Sam',
    kdfIterations: 2000,
  });
  const invite = parseInvite(inviteUrl);

  check('an invite round-trips its peer id', invite.partnerPeerId === 'love-A1B2C3D4E5F6G7H8');
  check('an invite round-trips the salt EXACTLY as stored', invite.salt === salt);
  check('an invite round-trips the anniversary', invite.startDate === '2021-06-14');
  check(
    'an invite carries the KDF count (required to pair into a 250,000 vault)',
    invite.kdfIterations === 2000
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
  check(
    'a trailing-garbage iteration count is rejected, not parseInt-ed',
    parseInvite('#connect=love-abcdefgh&kdf=600000xyz').kdfIterations === null
  );
  check(
    'an exponent-notation iteration count is rejected (parseInt would make it 1)',
    parseInvite('#connect=love-abcdefgh&kdf=1e9').kdfIterations === null
  );
  check(
    'an out-of-range iteration count is rejected',
    parseInvite('#connect=love-abcdefgh&kdf=12').kdfIterations === null
  );
  check(
    'a normal iteration count survives',
    parseInvite('#connect=love-abcdefgh&kdf=250000').kdfIterations === 250000
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
  section('11b. A row carrying NO ciphertext cannot overwrite a live record');

  // The adversarial review's finding, locked in as a regression guard.
  //
  // Section 11 only proves that a row encrypted under a DIFFERENT key is
  // refused - AES-GCM does that on its own. The hole was narrower and worse: a
  // row with no encrypted fields at all never exercises the key. decryptRecord
  // falls through to the legacy path, which decrypts only `<base>Cipher` fields
  // (there are none), stamps `_headerTampered: false` unconditionally, and
  // resolves. The old gate read that as "decrypted fine under our key".
  //
  // Nobody needs a key to build one of these, and the ids collide by design, so
  // this was a hand-writable overwrite of live photos and letters.
  const bareTombstone = {
    id: 'bkt-default-1',
    updatedAt: NOW + MINUTE, // newer, so precedence alone would let it win
    deleted: true,
    v: 1,
  };

  check(
    'a row with no ciphertext is not an authenticated payload',
    recordCarriesAuthenticatedPayload(bareTombstone) === false
  );
  check(
    'claiming v:2 without an envelope does not make it authenticated',
    recordCarriesAuthenticatedPayload({ ...bareTombstone, v: 2 }) === false
  );
  check(
    'an empty-string envelope is not authenticated either',
    recordCarriesAuthenticatedPayload({ id: 'x', v: 2, ciphertext: '', iv: '' }) === false
  );
  check(
    'a genuine v2 envelope IS authenticated',
    recordCarriesAuthenticatedPayload(liveBucket) === true
  );
  check(
    'a genuine v1 row with a Cipher/Iv pair IS authenticated',
    recordCarriesAuthenticatedPayload({
      id: 'let-1',
      updatedAt: NOW,
      deleted: false,
      contentCipher: 'abc',
      contentIv: 'def',
    }) === true
  );
  check(
    'a Cipher without its matching Iv does not count',
    recordCarriesAuthenticatedPayload({ id: 'let-1', contentCipher: 'abc' }) === false
  );

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

  const survivingRoulette = await decryptRecord(
    await liveStore.table('dateIdeas').get('roulette-current'),
    key
  );
  check('the live roulette-current is untouched', survivingRoulette.idea === 'Pizza and a bad film');

  /* ------------- 11c. unknown-origin files (the SyncHubModal preview branch) - */
  /* ---------------- 11bis. decoy-ciphertext forgery (the v1 header hole) ---- */
  section('11bis. A v1 row with a DECOY cipher pair cannot destroy a live record');

  // The bypass an adversarial reviewer built against the first version of this
  // guard, kept as a permanent regression test.
  //
  // recordCarriesAuthenticatedPayload only asks whether SOME ciphertext is
  // present. decryptLegacyRecord then decrypts each <base>Cipher field on its
  // own and stamps _headerTampered:false unconditionally, because v1 has no
  // authenticated copy of the header to compare against. So ONE ciphertext made
  // under the vault key - and every backup ships one, its own vaultMeta canary -
  // can be pasted into a hand-built row as a decoy pair. The row decrypts, looks
  // untampered, and carries whatever id and `deleted:true` the forger chose.
  //
  // The attacker needs the backup FILE passphrase and never the vault
  // passphrase. It is destroy-only - they still cannot read anything.
  // The photo is sealed INTO the envelope (its digest is inside the payload),
  // exactly as db.putEncrypted writes it. Attaching the bytes to the row after
  // the fact would build a fixture the integrity check now correctly rejects.
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
    'the decoy pair does satisfy the weaker payload check (this is why it worked)',
    recordCarriesAuthenticatedPayload(forgedTombstone) === true
  );
  check(
    'but it has NO authenticated header',
    recordHasAuthenticatedHeader(forgedTombstone) === false
  );
  check(
    'and a genuine v2 envelope does',
    recordHasAuthenticatedHeader(liveMemory) === true
  );

  const forgedPlan = await liveStore.planBackupMerge({ memories: [forgedTombstone] }, key);
  check(
    'the forgery is refused as unauthenticated, not counted as an update',
    forgedPlan.totals.unauthenticated === 1 && forgedPlan.totals.updated === 0
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
    incomingWins: (existing, row) => true,
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

  // The wire path enforces the same invariant in _commitStagedRecords, which
  // talks to real Dexie and so cannot run here (no IndexedDB in plain node).
  // What IS testable is the predicate that gate depends on, asserted above.
  // The guard itself is peerSync.js: `if (existing && !recordHasAuthenticatedHeader(row))`.
  check(
    'the wire gate keys off the same predicate this suite pins down',
    recordHasAuthenticatedHeader(forgedTombstone) === false &&
      recordHasAuthenticatedHeader(liveMemory) === true
  );

  // An honest v1 row is still allowed to CREATE something new - refusing those
  // outright would break a partner who has not finished the v2 sweep.
  const legacyNew = {
    id: 'mem-legacy-new',
    updatedAt: NOW,
    deleted: false,
    v: 1,
    captionCipher: decoy.ciphertext,
    captionIv: decoy.iv,
  };
  const createPlan = await liveStore.planBackupMerge({ memories: [legacyNew] }, key);
  check(
    'a v1 row for an id we do not have is still allowed to create',
    createPlan.totals.added === 1 && createPlan.totals.unauthenticated === 0
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
  const forgedNewTombstone = {
    id: 'bkt-default-3',
    updatedAt: NOW,
    deleted: true,
    v: 1,
    textCipher: decoy.ciphertext,
    textIv: decoy.iv,
  };
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

  // The gap this section used to document is now CLOSED, and the fix is not the
  // re-seal sweep - that only re-seals rows this device HOLDS, while every gate
  // decrypts the row ARRIVING. An envelope harvested before binding existed
  // would otherwise have stayed a permanent capability against that id on every
  // device, no matter how often either side swept. So an absent binding is now
  // its own verdict: `unverified` may CREATE, but never overwrite or delete.
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


  // ...which is why the sweep drains it. migrateLegacyRecords re-seals any row
  // whose envelope lacks the binding, under the same id and updatedAt.
  const drainStore = new FakeVaultStore({ bucketList: [unboundRow] });
  const drainStats = await drainStore.migrateLegacyRecords(key);
  check(
    'the sweep re-seals the unbound row (and reports it migrated)',
    drainStats.migrated === 1 && drainStats.failed === 0 && drainStats.tampered === 0
  );
  const drained = await drainStore.table('bucketList').get('pre-binding-1');
  check(
    'a re-seal is not an edit: same id, same updatedAt, same tombstone state',
    drained.updatedAt === unboundRow.updatedAt &&
      drained.id === unboundRow.id &&
      drained.deleted === false
  );
  const drainedHome = await decryptRecord(drained, key, { table: 'bucketList' });
  check(
    'it is now bound, and still readable in its own table',
    drainedHome._tableUnverified === false &&
      drainedHome._tableTampered === false &&
      drainedHome.text === 'Sealed before the binding'
  );
  const drainedAway = await decryptRecord(drained, key, { table: 'letters' });
  check(
    'and after the sweep the very same row IS refused in another table',
    drainedAway._tableTampered === true && drainedAway._headerTampered === true
  );

  // The sweep must never re-seal a row that reports tampering: re-sealing
  // rebuilds the envelope around the row's CURRENT header, which would
  // authenticate the tampering and launder it past every downstream gate.
  const launderBase = await encryptRecord(
    { id: 'launder-1', updatedAt: NOW - MINUTE, deleted: false, text: 'Header rewritten' },
    key
  );
  const laundered = { ...launderBase, updatedAt: launderBase.updatedAt + 5000 };
  const launderStore = new FakeVaultStore({ bucketList: [laundered] });
  const launderStats = await launderStore.migrateLegacyRecords(key);
  check(
    'the sweep refuses to re-seal a header-tampered row',
    launderStats.tampered === 1 && launderStats.migrated === 0 && launderStats.failed === 0
  );
  const stillTampered = await launderStore.table('bucketList').get('launder-1');
  check(
    'so it stays exactly as it was, and stays refused by the gates',
    stillTampered.ciphertext === launderBase.ciphertext &&
      (await decryptRecord(stillTampered, key))._headerTampered === true
  );

  /* ------- 11quinquies. the sweep does not protect against a HELD envelope -- */
  section('11quinquies. An unverified binding may create but never overwrite');

  // The structural point an adversarial reviewer made, and the reason the
  // re-seal sweep was never the fix: migrateLegacyRecords re-seals rows this
  // device HOLDS, while every gate decrypts the row ARRIVING. So an envelope
  // harvested before the photo digest or the table binding existed stayed a
  // permanent capability against that id - on a fully swept device, forever.
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

  /* -------- 11sexies. the re-seal sweep must not launder a forged row ------ */
  section('11sexies. The sweep cannot upgrade an attacker-authored row into an authenticated one');

  // The full kill chain an adversarial reviewer executed end to end, and the
  // control run that isolated the escalation step.
  //
  // Attacker holds a harvested .vault FILE and its FILE passphrase. Never the
  // vault passphrase; they cannot read a single record. Destroy-only.
  //  1. Any v2 row in the file yields a ciphertext/iv pair made under the vault
  //     key. Renamed to <base>Cipher/<base>Iv it satisfies the payload check,
  //     because decryptLegacyRecord simply decryptText()s it.
  //  2. They aim a v1 row at a real id with a chosen updatedAt and garbage
  //     bytes. decryptLegacyRecord stamps _headerTampered AND _binaryTampered
  //     false by construction - v1 has no sealed header to disagree with.
  //  3. On a device that LACKS that id - a rescue restore onto a replacement
  //     phone, the app's own advertised flow - the create path accepts it. The
  //     preview reads "Added: 1" with no warning.
  //  4. The sweep then re-sealed it into a fully bound v2 envelope over the
  //     attacker's id, timestamp, delete flag and bytes. That is the escalation.
  //  5. It synced to the partner and destroyed the real photo, with no
  //     confirmation UI anywhere on that path.
  //
  // The transport gate was never the weakness - the control below proves a v1
  // row is refused an overwrite directly. Only the sweep made it authentic.
  const sxDonor = await encryptRecord(
    { id: 'sxDonor', updatedAt: NOW, deleted: false, note: 'any row from the file' },
    key,
    { table: 'letters' }
  );
  // NOT a tombstone: ab842f6 already refuses those at create. This is the
  // variant that mattered - an overwrite, which replaces the letter body (and
  // for a memory, the photo bytes) just as destructively.
  const sxForged = {
    id: 'let-victim',
    updatedAt: NOW + 60 * MINUTE,
    deleted: false,
    v: 1,
    // The decoy: a genuine ciphertext under the vault key, wearing a v1 name.
    contentCipher: sxDonor.ciphertext,
    contentIv: sxDonor.iv,
  };

  // Control: straight at a device that HAS the id, with no sweep in between.
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
    'CONTROL: a v1 forgery is refused an overwrite directly',
    sxDirectPlan.totals.updated === 0 && sxDirectPlan.totals.unauthenticated === 1
  );

  // The chain: create it on a device that lacks the id, then sweep.
  const sxLaunderStore = new FakeVaultStore({});
  const sxCreatedPlan = await sxLaunderStore.planBackupMerge({ letters: [sxForged] }, key);
  check('the forgery is still CREATED on a device that lacks the id', sxCreatedPlan.totals.added === 1);
  await sxLaunderStore.applyBackupMerge(sxCreatedPlan);

  const sxSweepStats = await sxLaunderStore.migrateLegacyRecords(key);
  check('the sweep does re-seal it into a v2 envelope', sxSweepStats.migrated === 1);

  const sxLaundered = await sxLaunderStore.table('letters').get('let-victim');
  check('and the re-sealed row IS a v2 envelope', sxLaundered.v === 2);

  const sxLaunderedPlain = await decryptRecord(sxLaundered, key, { table: 'letters' });
  check(
    'but it is marked as content this vault never authenticated',
    sxLaunderedPlain._headerUnverified === true
  );

  // The whole point: the sxLaundered row still cannot destroy anything.
  const sxAsWire = { ...sxLaundered };
  const sxChainPlan = await sxVictimStore.planBackupMerge({ letters: [sxAsWire] }, key);
  check(
    'THE POINT: the laundered row still cannot overwrite the real letter',
    sxChainPlan.totals.deleted === 0 && sxChainPlan.totals.unauthenticated === 1
  );
  await sxVictimStore.applyBackupMerge(sxChainPlan);
  const sxVictimSurvivor = await sxVictimStore.table('letters').get('let-victim');
  const sxVictimPlain = await decryptRecord(sxVictimSurvivor, key, { table: 'letters' });
  check(
    'the real letter body survived the full chain',
    sxVictimPlain.content === 'The real letter'
  );

  // A genuinely local v1 row must still migrate and still be usable.
  const sxHonestLegacy = {
    id: 'let-mine-from-v1',
    updatedAt: NOW,
    deleted: false,
    v: 1,
    contentCipher: sxDonor.ciphertext,
    contentIv: sxDonor.iv,
  };
  const sxHonestStore = new FakeVaultStore({ letters: [sxHonestLegacy] });
  const sxHonestStats = await sxHonestStore.migrateLegacyRecords(key);
  check('an honest local v1 row still migrates', sxHonestStats.migrated === 1);
  const sxHonestAfter = await sxHonestStore.table('letters').get('let-mine-from-v1');
  check('and is still readable afterwards', sxHonestAfter.v === 2);

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
  const rescueKey = await fastKey(rescuePassphrase, rescueSalt);
  const rescueMeta = {
    id: 'config',
    salt: rescueSalt,
    kdfIterations: 2000,
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
      rescueIdentity.kdfIterations === 2000
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
  check('the adopted row records the count that actually worked', adopted.kdfIterations === 2000);

  // The whole promise of the rescue file: a cold unlock from the stored row alone.
  const coldUnlock = await deriveKeyWithVerification(
    rescuePassphrase,
    adopted.salt,
    async (candidate) => (await readCanary(candidate, adopted)) !== null,
    { iterations: resolveKdfIterations(adopted) }
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
        { iterations: resolveKdfIterations(adopted) }
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

  // The same rescue, from a vault created before the 600,000 bump. If the count
  // is not carried out of the file, the passphrase is "wrong" forever.
  const legacyRescueSalt = generateSalt();
  const legacyRescueKey = await deriveKeyFromPassphrase(rescuePassphrase, legacyRescueSalt, {
    iterations: PBKDF2_ITERATIONS_LEGACY,
  });
  const legacyRescueRow = {
    id: 'config',
    salt: legacyRescueSalt,
    // No kdfIterations: an old build never wrote one.
    ...(await createCanary(legacyRescueKey, { coupleNames: 'Old Build', startDate: '2019-05-05' })),
  };
  const legacyIdentity = readBackupVaultIdentity({ vaultMeta: [legacyRescueRow] });
  check(
    'a backup with no kdfIterations is read as a 250,000-iteration vault',
    legacyIdentity.kdfIterations === PBKDF2_ITERATIONS_LEGACY
  );
  const legacyDerived = await deriveKeyWithVerification(
    rescuePassphrase,
    legacyIdentity.salt,
    async (candidate) => (await readCanary(candidate, legacyIdentity)) !== null,
    { iterations: legacyIdentity.kdfIterations }
  );
  const legacyDevice = new FakeVaultStore();
  await legacyDevice.restoreVaultIdentity({ ...legacyIdentity, kdfIterations: legacyDerived.iterations });
  const legacyAdopted = (await legacyDevice.readVaultIdentity()).meta;
  check(
    'the rescued legacy row PINS 250,000 rather than inheriting the new default',
    legacyAdopted.kdfIterations === PBKDF2_ITERATIONS_LEGACY &&
      resolveKdfIterations(legacyAdopted) === PBKDF2_ITERATIONS_LEGACY
  );
  const legacyCold = await deriveKeyFromPassphrase(rescuePassphrase, legacyAdopted.salt, {
    iterations: resolveKdfIterations(legacyAdopted),
  });
  check(
    'the original passphrase opens the rescued legacy vault',
    (await readCanary(legacyCold, legacyAdopted)) !== null
  );
  const legacyAtCurrent = await deriveKeyFromPassphrase(rescuePassphrase, legacyAdopted.salt, {
    iterations: PBKDF2_ITERATIONS_CURRENT,
  });
  check(
    'WHY THE COUNT MUST BE CARRIED: at 600,000 the same passphrase does not open it',
    (await readCanary(legacyAtCurrent, legacyAdopted)) === null
  );

  /* ------------------------------------------------ 14. import sanitising */
  section('14. Import sanitising — a restored clock artefact must not win forever');

  const SKEW_LIMIT = 48 * 60 * 60 * 1000;
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
    'an updatedAt more than 48h ahead is refused at the STRUCTURE gate',
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
  console.log('Sections 11-15 run the SHIPPED db/index.js methods against an in-memory');
  console.log('table store; only the storage is fake, and the precedence rule is proved');
  console.log("to be peerSync's own by spying on it.");
}

run().catch((err) => {
  console.error('\nSUITE CRASHED:', err);
  process.exitCode = 1;
});
