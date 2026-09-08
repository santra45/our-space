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
 *   7. v1 -> v2 migration    round-trip of the exact reshaping db does
 *   8. Time locks            seal/unseal, and that the date is BOUND, not checked
 *   9. Backups               v2 containers, and v1 containers still opening
 *  10. Invites               a stranger's link cannot choose our PBKDF2 salt
 *  11. Foreign backups       a stranger's file cannot overwrite a colliding id
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
 *  - Dexie's own `version(2).upgrade()` callback and the `blocked` event that
 *    drives isUpgradeBlocked()/subscribeUpgradeBlocked(). Both need a real
 *    IndexedDB with two live connections. Section 7 covers the record reshaping
 *    `db.migrateLegacyRecords()` performs - the part that can lose data - but
 *    not the schema upgrade around it.
 *  - The `_del` tombstone hooks, which are Dexie CRUD hooks.
 *  - Every React gate: LockScreen's restore mode and unreadable panel,
 *    SyncHubModal's ImportPreview, VaultContext's guardDestructiveWrite,
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
  const survivingRoulette = await decryptRecord(
    await liveStore.table('dateIdeas').get('roulette-current'),
    key
  );
  check('the live roulette-current is untouched', survivingRoulette.idea === 'Pizza and a bad film');

  /* --------------------------------- 12. merge precedence is peerSync's rule */
  section("12. An older backup does not revert newer local work (peerSync's own rule)");

  const liveLetterA = await encryptRecord(
    { id: 'let-merge-a', updatedAt: NOW, deleted: false, title: 'Newer local edit' },
    key
  );
  const liveLetterB = await encryptRecord(
    { id: 'let-merge-b', updatedAt: NOW - 30 * MINUTE, deleted: false, title: 'Older local copy' },
    key
  );
  const backupLetterA = await encryptRecord(
    { id: 'let-merge-a', updatedAt: NOW - 60 * MINUTE, deleted: false, title: 'Stale backup copy' },
    key
  );
  const backupLetterB = await encryptRecord(
    { id: 'let-merge-b', updatedAt: NOW - 5 * MINUTE, deleted: false, title: 'Newer backup copy' },
    key
  );
  const backupLetterC = await encryptRecord(
    { id: 'let-merge-c', updatedAt: NOW - 90 * MINUTE, deleted: false, title: 'Only in the backup' },
    key
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
    key
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
    tamperPlan.totals.undecryptable === 2 && tamperPlan.totals.invalid === 0
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
