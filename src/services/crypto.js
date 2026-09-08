/**
 * src/services/crypto.js
 * Zero-Knowledge Web Crypto API Engine
 * - Algorithm: AES-GCM 256-bit
 * - Key Derivation: PBKDF2 with HMAC-SHA-256
 *     * New vaults:      600,000 iterations (current OWASP floor)
 *     * Legacy vaults:   250,000 iterations (kept readable forever, see below)
 * - Unique 96-bit (12-byte) IV for every encryption operation
 *
 * KDF VERSIONING
 * The iteration count is a property of a vault, not of this file. It is stored
 * on the `vaultMeta.config` row as `kdfIterations`. A vault created before that
 * field existed has no value there, which by definition means 250,000. Raising
 * the constant therefore does NOT brick existing vaults: they keep deriving at
 * their recorded count. Only vaults created from now on use 600,000.
 *
 * An existing vault cannot be silently upgraded to 600,000, because a different
 * iteration count means a different key, which would require re-encrypting
 * every record and every photo. We do not do that behind the user's back.
 */

/** Iteration count used for every vault created from now on. */
export const PBKDF2_ITERATIONS_CURRENT = 600000;

/** Iteration count used by vaults created before `kdfIterations` was recorded. */
export const PBKDF2_ITERATIONS_LEGACY = 250000;

/** @deprecated Use PBKDF2_ITERATIONS_CURRENT. Kept so old imports do not break. */
export const PBKDF2_ITERATIONS = PBKDF2_ITERATIONS_CURRENT;

const AES_KEY_LENGTH = 256;
const IV_LENGTH_BYTES = 12; // 96 bits recommended for AES-GCM
const SALT_LENGTH_BYTES = 16;
export const MIN_PASSPHRASE_LENGTH = 16;

/** Canary plaintext stored (encrypted) on vaultMeta to verify a passphrase. */
export const VAULT_CANARY_TOKEN = 'SWEETHEART_CANARY_VALIDATION_TOKEN';

/** Version stamped on every record written with encryptRecord(). */
export const RECORD_SCHEMA_VERSION = 2;

/** Top-level fields that stay in plaintext on a v2 record (sync needs them). */
export const PLAINTEXT_RECORD_FIELDS = Object.freeze(['id', 'updatedAt', 'deleted']);

/** Envelope bookkeeping fields that must never leak back into a payload. */
const INTERNAL_RECORD_FIELDS = new Set([
  'v',
  'ciphertext',
  'iv',
  '_del',
  'needsReencrypt',
  '_schemaVersion',
  '_needsReencrypt',
  '_headerTampered',
  '_binaryTampered',
  '_binaryUnverified',
  '_tableTampered',
  '_tableUnverified',
  '_bin',
  '_tbl',
]);

const getCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);
const getBtoa = (str) => (typeof window !== 'undefined' ? window.btoa(str) : globalThis.btoa(str));
const getAtob = (str) => (typeof window !== 'undefined' ? window.atob(str) : globalThis.atob(str));

/**
 * Generates a cryptographically secure random nonce string (base64)
 */
export function generateSecureNonce(byteLength = 16) {
  const bytes = new Uint8Array(byteLength);
  getCrypto().getRandomValues(bytes);
  return bufferToBase64(bytes);
}

/**
 * Generates a cryptographically secure random nonce using the URL-safe base64
 * alphabet, with padding stripped. Every bit of entropy survives, and the
 * result is safe in a URL fragment, a QR code and a PeerJS id.
 * @param {number} byteLength
 * @returns {string}
 */
export function generateUrlSafeNonce(byteLength = 16) {
  return generateSecureNonce(byteLength).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// 32KB at a time: large enough to be fast, small enough to stay under the
// argument-count limit of Function.prototype.apply in every engine we target.
const B64_CHUNK_BYTES = 0x8000;

/**
 * Utility: Convert ArrayBuffer / TypedArray to Base64 string.
 * Chunked rather than per-byte: a multi-megabyte photo used to build the
 * intermediate binary string one character at a time, which froze the UI.
 */
export function bufferToBase64(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';
  for (let offset = 0; offset < bytes.byteLength; offset += B64_CHUNK_BYTES) {
    const chunk = bytes.subarray(offset, Math.min(offset + B64_CHUNK_BYTES, bytes.byteLength));
    binary += String.fromCharCode.apply(null, chunk);
  }
  return getBtoa(binary);
}

/**
 * Utility: Convert Base64 string to Uint8Array.
 * Accepts both standard and URL-safe base64, with or without padding.
 */
export function base64ToBuffer(base64) {
  if (typeof base64 !== 'string') {
    throw new Error('base64ToBuffer: expected a string');
  }
  let normalized = base64.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  if (remainder === 1) {
    throw new Error('base64ToBuffer: malformed base64 input');
  }
  if (remainder > 0) {
    normalized += '='.repeat(4 - remainder);
  }
  const binary = getAtob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * True when `value` looks like base64 of exactly `byteLength` bytes.
 * Used to reject attacker-supplied salts before they reach PBKDF2.
 * @param {unknown} value
 * @param {number} [byteLength] - Omit to accept any length.
 * @returns {boolean}
 */
export function isValidBase64(value, byteLength) {
  if (typeof value !== 'string' || value.length === 0) return false;
  if (!/^[A-Za-z0-9+/\-_]+={0,2}$/.test(value)) return false;
  try {
    const bytes = base64ToBuffer(value);
    if (byteLength !== undefined && bytes.byteLength !== byteLength) return false;
    return true;
  } catch {
    return false;
  }
}

/**
 * True when `value` is a well-formed vault salt (base64 of 16 bytes).
 * Invite-parsing code should gate on this before deriving anything.
 */
export function isValidSalt(value) {
  return isValidBase64(value, SALT_LENGTH_BYTES);
}

/**
 * Generates a cryptographically secure random salt for the shared vault.
 */
export function generateSalt() {
  const salt = new Uint8Array(SALT_LENGTH_BYTES);
  getCrypto().getRandomValues(salt);
  return bufferToBase64(salt);
}

/**
 * Canonicalises a passphrase before it reaches PBKDF2.
 *
 * Two devices must derive the same key from what the user believes is the same
 * phrase. Without this, an accented or emoji character composed as NFD on one
 * platform and NFC on another produces two different keys and an unhelpful
 * "incorrect passphrase". Trailing whitespace from mobile autocorrect or a
 * paste does the same.
 *
 * @param {string} passphrase
 * @returns {string}
 */
export function normalizePassphrase(passphrase) {
  if (typeof passphrase !== 'string') return '';
  return passphrase.normalize('NFKC').trim();
}

/**
 * Reads the KDF iteration count a vault was created with.
 * A vaultMeta row without the field predates it and is therefore 250,000.
 * @param {{ kdfIterations?: number }|null|undefined} meta
 * @returns {number}
 */
export function resolveKdfIterations(meta) {
  const value = meta && meta.kdfIterations;
  if (Number.isFinite(value) && value >= 1000 && value <= 10000000) {
    return Math.floor(value);
  }
  return PBKDF2_ITERATIONS_LEGACY;
}

async function importPassphraseKey(passphrase) {
  const encoder = new TextEncoder();
  return await getCrypto().subtle.importKey(
    'raw',
    encoder.encode(passphrase),
    { name: 'PBKDF2' },
    false,
    ['deriveKey']
  );
}

async function deriveUnchecked(passphrase, saltBase64, iterations) {
  const passphraseKey = await importPassphraseKey(passphrase);
  const saltBuffer = base64ToBuffer(saltBase64);

  return await getCrypto().subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBuffer,
      iterations,
      hash: 'SHA-256',
    },
    passphraseKey,
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    false, // Master key is non-extractable from browser memory
    ['encrypt', 'decrypt']
  );
}

/**
 * Derives an AES-GCM 256-bit CryptoKey from a user passphrase and salt using PBKDF2.
 * Enforces a strict minimum passphrase length of 16 characters.
 *
 * @param {string} passphrase - The shared secret passphrase
 * @param {string} saltBase64 - The base64-encoded salt
 * @param {number|{ iterations?: number, normalize?: boolean }} [options] - Iteration
 *   count, or an options object. DEFAULTS TO 600,000. When unlocking an EXISTING
 *   vault you must pass that vault's recorded count (see resolveKdfIterations)
 *   or, better, use deriveKeyWithVerification().
 * @returns {Promise<CryptoKey>} - AES-GCM CryptoKey ready for encryption/decryption
 */
export async function deriveKeyFromPassphrase(passphrase, saltBase64, options) {
  const opts = typeof options === 'number' ? { iterations: options } : options || {};
  const iterations = Number.isFinite(opts.iterations)
    ? Math.floor(opts.iterations)
    : PBKDF2_ITERATIONS_CURRENT;
  const shouldNormalize = opts.normalize !== false;
  const effective = shouldNormalize ? normalizePassphrase(passphrase) : passphrase;

  if (typeof effective !== 'string' || effective.length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long`);
  }
  if (!isValidBase64(saltBase64)) {
    throw new Error('Invalid vault salt');
  }

  return await deriveUnchecked(effective, saltBase64, iterations);
}

/**
 * Derives the vault key by trying every plausible derivation until one verifies.
 *
 * This is the function unlock paths should call. It transparently handles:
 *  - vaults created at 250,000 iterations before the OWASP bump,
 *  - vaults whose passphrase was stored un-normalised (e.g. with a stray
 *    trailing space typed on a phone) before normalizePassphrase existed.
 *
 * Cost: one PBKDF2 run on the happy path, at most four when the passphrase is
 * simply wrong. That extra second on a wrong guess is a feature, not a bug.
 *
 * @param {string} passphrase
 * @param {string} saltBase64
 * @param {(key: CryptoKey) => Promise<boolean>|boolean} verify - Returns true when the
 *   key is correct (normally: the canary decrypts). Throwing counts as false.
 * @param {{ iterations?: number }} [options] - The vault's recorded iteration count,
 *   tried first.
 * @returns {Promise<{ key: CryptoKey, iterations: number, normalized: boolean }>}
 * @throws {Error} When no candidate verifies.
 */
export async function deriveKeyWithVerification(passphrase, saltBase64, verify, options = {}) {
  if (!isValidBase64(saltBase64)) {
    throw new Error('Invalid vault salt');
  }

  const normalized = normalizePassphrase(passphrase);
  const raw = typeof passphrase === 'string' ? passphrase : '';

  const iterationCandidates = [];
  if (Number.isFinite(options.iterations)) iterationCandidates.push(Math.floor(options.iterations));
  iterationCandidates.push(PBKDF2_ITERATIONS_CURRENT, PBKDF2_ITERATIONS_LEGACY);

  const passphraseCandidates = raw === normalized ? [normalized] : [normalized, raw];

  const seen = new Set();
  for (let variant = 0; variant < passphraseCandidates.length; variant++) {
    const candidate = passphraseCandidates[variant];
    if (candidate.length < MIN_PASSPHRASE_LENGTH) continue;
    for (const iterations of iterationCandidates) {
      const fingerprint = `${variant}:${iterations}`;
      if (seen.has(fingerprint)) continue;
      seen.add(fingerprint);

      let key;
      try {
        key = await deriveUnchecked(candidate, saltBase64, iterations);
      } catch {
        continue;
      }
      try {
        if (await verify(key)) {
          return { key, iterations, normalized: candidate === normalized };
        }
      } catch {
        // Wrong key: the canary failed its auth tag. Try the next candidate.
      }
    }
  }

  throw new Error('Incorrect passphrase');
}

/**
 * Builds the encrypted canary payload stored on vaultMeta.
 * @param {CryptoKey} key
 * @param {{ coupleNames?: string, startDate?: string, updatedAt?: number, createdAt?: number }} config
 * @returns {Promise<{ canary: string, canaryIv: string }>}
 */
export async function createCanary(key, config = {}) {
  const encrypted = await encryptJSON(
    {
      token: VAULT_CANARY_TOKEN,
      coupleNames: config.coupleNames || 'Us',
      startDate: config.startDate || '',
      createdAt: Number.isFinite(config.createdAt) ? config.createdAt : Date.now(),
      updatedAt: Number.isFinite(config.updatedAt) ? config.updatedAt : 0,
    },
    key
  );
  return { canary: encrypted.ciphertext, canaryIv: encrypted.iv };
}

/**
 * Verifies a key against a vaultMeta canary and returns the config it carries.
 * @param {CryptoKey} key
 * @param {{ canary?: string, canaryIv?: string }} meta
 * @returns {Promise<Object|null>} The decrypted canary payload, or null when the key is wrong.
 */
export async function readCanary(key, meta) {
  if (!meta || typeof meta.canary !== 'string' || typeof meta.canaryIv !== 'string') return null;
  try {
    const payload = await decryptJSON(meta.canary, meta.canaryIv, key);
    if (!payload || payload.token !== VAULT_CANARY_TOKEN) return null;
    return payload;
  } catch {
    return null;
  }
}

/**
 * Checks a typed passphrase against an existing vaultMeta row.
 * Use this before creating an encrypted backup so a typo cannot produce a
 * .vault file nobody can ever open.
 *
 * @param {string} passphrase
 * @param {{ salt: string, canary: string, canaryIv: string, kdfIterations?: number }} meta
 * @returns {Promise<boolean>}
 */
export async function verifyPassphraseAgainstMeta(passphrase, meta) {
  if (!meta || typeof meta.salt !== 'string') return false;
  try {
    await deriveKeyWithVerification(
      passphrase,
      meta.salt,
      async (key) => (await readCanary(key, meta)) !== null,
      { iterations: resolveKdfIterations(meta) }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Encrypts a plaintext UTF-8 string with AES-GCM 256.
 * @param {string} plainText
 * @param {CryptoKey} key
 * @param {Uint8Array|string} [additionalData] - Optional AEAD associated data. Not
 *   encrypted, but authenticated: decryption fails unless the exact same value
 *   is supplied again.
 * @returns {Promise<{ ciphertext: string, iv: string }>}
 */
export async function encryptText(plainText, key, additionalData) {
  const encoder = new TextEncoder();
  const iv = getCrypto().getRandomValues(new Uint8Array(IV_LENGTH_BYTES));
  const encodedData = encoder.encode(plainText);

  const params = { name: 'AES-GCM', iv };
  if (additionalData !== undefined) {
    params.additionalData =
      typeof additionalData === 'string' ? encoder.encode(additionalData) : additionalData;
  }

  const cipherBuffer = await getCrypto().subtle.encrypt(params, key, encodedData);

  return {
    ciphertext: bufferToBase64(cipherBuffer),
    iv: bufferToBase64(iv),
  };
}

/**
 * Decrypts an AES-GCM 256 ciphertext string.
 * @param {string} ciphertextBase64
 * @param {string} ivBase64
 * @param {CryptoKey} key
 * @param {Uint8Array|string} [additionalData] - Must match what was passed to encryptText.
 * @returns {Promise<string>} Plaintext UTF-8 string
 */
export async function decryptText(ciphertextBase64, ivBase64, key, additionalData) {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  const iv = base64ToBuffer(ivBase64);
  const cipherBuffer = base64ToBuffer(ciphertextBase64);

  const params = { name: 'AES-GCM', iv };
  if (additionalData !== undefined) {
    params.additionalData =
      typeof additionalData === 'string' ? encoder.encode(additionalData) : additionalData;
  }

  const decryptedBuffer = await getCrypto().subtle.decrypt(params, key, cipherBuffer);

  return decoder.decode(decryptedBuffer);
}

/**
 * Encrypts an arbitrary JSON serializable object.
 */
export async function encryptJSON(data, key) {
  const jsonString = JSON.stringify(data);
  return await encryptText(jsonString, key);
}

/**
 * Decrypts an encrypted JSON payload.
 */
export async function decryptJSON(ciphertextBase64, ivBase64, key) {
  const decryptedText = await decryptText(ciphertextBase64, ivBase64, key);
  return JSON.parse(decryptedText);
}

/* ------------------------------------------------------------------------- *
 * Record envelopes (schema v2): all metadata is encrypted
 * ------------------------------------------------------------------------- */

function isBinaryValue(value) {
  return (
    value instanceof Uint8Array ||
    value instanceof ArrayBuffer ||
    (typeof Blob !== 'undefined' && value instanceof Blob)
  );
}

/**
 * Payload key holding SHA-256 digests of the row's top-level binary fields.
 *
 * WHY THIS EXISTS
 * A v2 envelope authenticates its JSON payload and nothing else. The photo does
 * not travel inside that payload: `imageBlob` is separately AES-GCM sealed by
 * encryptBlob() and rides at the TOP LEVEL so IndexedDB stores real bytes
 * instead of a base64 string inflated through JSON. That made the bytes
 * unauthenticated *as part of this record*. Anyone holding one valid envelope
 * for a memory id - a stale backup file whose own file passphrase they know, or
 * a paired partner - could keep the envelope and swap the blob for garbage. The
 * row still decrypted, still reported an untampered header, passed every gate,
 * and the photo was gone for good. Binding the header in commit 0fa7116 did not
 * touch this, because nothing about the header changes when only the bytes do.
 *
 * The fix is deliberately the cheapest one that closes it: hash the bytes and
 * carry the digest INSIDE the encrypted payload. The digest is therefore
 * covered by the same AES-GCM tag as everything else, so it cannot be edited,
 * stripped or recomputed without the vault key - only replayed wholesale, and a
 * replayed envelope carries the digest of the photo it was sealed with.
 *
 * Rejected alternatives, and why:
 *  - AAD (pass the blob digest as additionalData to the envelope). Same strength,
 *    but a pre-digest row then fails to DECRYPT rather than failing a check, so
 *    there is no way to distinguish "old row" from "forged row" and every photo
 *    written before this commit becomes unreadable. Unacceptable.
 *  - Hashing the plaintext image instead of the sealed bytes. Requires the key
 *    and a full blob decrypt on every read, for no extra guarantee: the bytes we
 *    hash are the bytes we store, and swapping them is exactly the attack.
 *  - Encrypting the blob into the payload. Correct, and enormous - it would
 *    base64-inflate every photo into the JSON envelope and rewrite every row.
 */
const BINARY_DIGEST_FIELD = '_bin';

/**
 * Payload key naming the TABLE a record was sealed for.
 *
 * WHY THIS EXISTS
 * An envelope binds `id`, `updatedAt` and `deleted` - and, since the digest map,
 * the attached bytes. It did NOT bind which table the row belongs to, and
 * neither import boundary supplied one: db.planBackupMerge iterates
 * `Object.entries(tables)` and peerSync._stageIncomingRecords reads `item.table`
 * straight off the wire. So an envelope sealed as a bucketList tombstone could
 * be moved, byte for byte, into the `letters` array of a backup container (or
 * into a `{ table: 'letters' }` wire item) and it authenticated perfectly: same
 * key, same bound header, nothing rewritten. planBackupMerge then classified it
 * as a delete against a LIVE letter carrying that id.
 *
 * Nothing stopped that except arithmetic. Record ids are uuids, and the two
 * families of fixed ids this build ships (bkt-default-1..6 in bucketList,
 * roulette-current in dateIdeas) happen to live in different tables, so no id is
 * currently reachable from two tables at once. That is a property of the seed
 * data, not an enforced invariant: one new seeded row sharing an id across
 * tables, or one id scheme that is not a uuid, and the replay lands.
 *
 * COMPATIBILITY SHAPE - deliberately identical to BINARY_DIGEST_FIELD's:
 *   - binding ABSENT  -> `_tableUnverified`. Old, not forged. Accepted.
 *   - binding PRESENT and disagreeing -> `_tableTampered`, folded into
 *     `_headerTampered`, refused by every gate that already reads that flag.
 * Every row written before this commit has no binding, and treating those as
 * hostile would refuse to restore or sync a vault's entire history. They are
 * re-sealed WITH a binding by db.migrateLegacyRecords()'s sweep at unlock, so
 * the carve-out drains per device instead of being permanent.
 *
 * Rejected alternative: enforcing the table at the two sanitize boundaries
 * instead, without touching the envelope. Cheaper, and it needs no drain - but
 * the only thing those boundaries could compare against is the row's id, so the
 * check reduces to "refuse an id that also exists in another table". That leans
 * on exactly the id-uniqueness accident described above rather than replacing
 * it, and it cannot see an id the local device has never held. A binding inside
 * the AES-GCM tag is checkable with no local state at all.
 */
const TABLE_BINDING_FIELD = '_tbl';

/**
 * SHA-256 of a binary field's bytes, base64. Accepts the three shapes
 * isBinaryValue() admits. A Uint8Array VIEW hashes only its own window, which is
 * what we want: that window is what gets stored.
 * @param {Uint8Array|ArrayBuffer|Blob} value
 * @returns {Promise<string>}
 */
async function digestBinaryValue(value) {
  let bytes;
  if (typeof Blob !== 'undefined' && value instanceof Blob) {
    bytes = await value.arrayBuffer();
  } else {
    bytes = value;
  }
  const hash = await getCrypto().subtle.digest('SHA-256', bytes);
  return bufferToBase64(hash);
}

/**
 * Compares a row's attached binary against the digests its envelope carries.
 *
 * Returns `unverified` (NOT `tampered`) when there is no digest map at all. That
 * is the backward-compatibility decision, and it is deliberate: every v2 row
 * written before this commit has no map, and treating those as hostile would
 * hide - and, on the import path, refuse to restore - photos that are perfectly
 * genuine. A missing map is old, not forged; a WRONG map is forged.
 *
 * Both directions are checked, because both are attacks:
 *  - an attached blob whose digest disagrees (the photo was swapped),
 *  - an attached blob the map does not mention at all (a blob bolted onto an
 *    envelope sealed without one, e.g. onto a tombstone),
 *  - a blob the map DOES mention that is no longer attached (the photo was
 *    stripped in transit). No honest path does this: oversized rows are skipped
 *    whole by peerSync, and both the backup export and the wire form carry the
 *    bytes across as base64 and rebuild them.
 *
 * @param {Object} record - The raw row (binary lives at its top level).
 * @param {unknown} digestMap - `payload[BINARY_DIGEST_FIELD]`, whatever it is.
 * @returns {Promise<{ tampered: boolean, unverified: boolean }>}
 */
async function verifyBinaryDigests(record, digestMap) {
  const attached = [];
  for (const [field, value] of Object.entries(record)) {
    if (isBinaryValue(value)) attached.push(field);
  }

  const hasMap = Boolean(digestMap) && typeof digestMap === 'object' && !Array.isArray(digestMap);
  if (!hasMap) {
    return { tampered: false, unverified: attached.length > 0 };
  }

  for (const field of attached) {
    const expected = digestMap[field];
    if (typeof expected !== 'string' || expected.length === 0) {
      return { tampered: true, unverified: false };
    }
    if ((await digestBinaryValue(record[field])) !== expected) {
      return { tampered: true, unverified: false };
    }
  }
  for (const field of Object.keys(digestMap)) {
    if (!attached.includes(field)) return { tampered: true, unverified: false };
  }

  return { tampered: false, unverified: false };
}

/**
 * Packs an entire record into a single encrypted envelope.
 *
 * Everything the caller passes is encrypted, EXCEPT:
 *  - `id`, `updatedAt` and `deleted`, which are also copied to the top level in
 *    plaintext because the sync protocol compares them without a key. They are
 *    additionally kept INSIDE the envelope, so AES-GCM authenticates them and a
 *    peer cannot rewrite a plaintext header without detection (see decryptRecord's
 *    `_headerTampered`).
 *  - binary fields (Uint8Array / ArrayBuffer / Blob, e.g. `imageBlob`), which are
 *    already independently AES-GCM encrypted by encryptBlob() and are passed
 *    through at the top level so IndexedDB stores them as binary rather than
 *    inflating them through JSON. Their BYTES are not in the envelope, but a
 *    SHA-256 of each of them is (see BINARY_DIGEST_FIELD), so swapping a photo
 *    under an otherwise valid envelope is detectable: decryptRecord reports
 *    `_binaryTampered`.
 *
 * Fields that used to sit in plaintext and be indexed (`date`, `category`,
 * `unlockDate`, `completed`, `completedAt`, `isOpened`) now live inside the
 * envelope. Filtering and sorting on them is in-memory, after decryption.
 *
 * @param {Object} plainFields - The full logical record. Must include `id`.
 * @param {CryptoKey} key
 * @param {{ table?: string }} [options] - `table` seals the name of the table
 *   this row belongs to into the envelope (see TABLE_BINDING_FIELD), so a row
 *   cannot be replayed into a different table under a valid envelope. Omitting
 *   it produces the pre-binding shape, which decryptRecord reports as
 *   `_tableUnverified` rather than refusing.
 * @returns {Promise<Object>} `{ id, updatedAt, deleted, v, ciphertext, iv, ...binary }`
 */
export async function encryptRecord(plainFields, key, options = {}) {
  if (!plainFields || typeof plainFields !== 'object') {
    throw new Error('encryptRecord: plainFields must be an object');
  }
  if (typeof plainFields.id !== 'string' || plainFields.id.length === 0) {
    throw new Error('encryptRecord: a string `id` is required');
  }

  const id = plainFields.id;
  const updatedAt = Number.isFinite(plainFields.updatedAt) ? plainFields.updatedAt : Date.now();
  const deleted = plainFields.deleted === true;

  const binary = {};
  const payload = {};

  for (const [field, value] of Object.entries(plainFields)) {
    if (value === undefined) continue;
    if (INTERNAL_RECORD_FIELDS.has(field)) continue;
    if (isBinaryValue(value)) {
      binary[field] = value;
      continue;
    }
    payload[field] = value;
  }

  payload.id = id;
  payload.updatedAt = updatedAt;
  payload.deleted = deleted;

  // Always written, even when it is empty. Emptiness is meaningful: it says
  // "this record was sealed with no binary attached", which is what makes a blob
  // bolted onto a tombstone detectable. An ABSENT map means something else
  // entirely - a row sealed before this field existed - and only the absent case
  // is treated as unverified. `_bin` is in INTERNAL_RECORD_FIELDS, so a caller
  // cannot supply its own.
  const digests = {};
  for (const [field, value] of Object.entries(binary)) {
    digests[field] = await digestBinaryValue(value);
  }
  payload[BINARY_DIGEST_FIELD] = digests;

  // Written only when the caller names a table. Unlike the digest map, absence
  // cannot be made meaningful here: a caller that does not know its table is
  // indistinguishable from an old build, and there is no honest value to invent.
  // `_tbl` is in INTERNAL_RECORD_FIELDS, so a caller cannot smuggle its own
  // through `plainFields`.
  if (typeof options.table === 'string' && options.table.length > 0) {
    payload[TABLE_BINDING_FIELD] = options.table;
  }

  const { ciphertext, iv } = await encryptJSON(payload, key);

  return {
    id,
    updatedAt,
    deleted,
    v: RECORD_SCHEMA_VERSION,
    ciphertext,
    iv,
    ...binary,
  };
}

async function decryptLegacyRecord(record, key) {
  const out = {};

  for (const [field, value] of Object.entries(record)) {
    if (INTERNAL_RECORD_FIELDS.has(field)) continue;
    if (field.endsWith('Cipher')) continue;
    if (field.endsWith('Iv') && typeof record[`${field.slice(0, -2)}Cipher`] === 'string') continue;
    out[field] = value;
  }

  for (const field of Object.keys(record)) {
    if (!field.endsWith('Cipher')) continue;
    const base = field.slice(0, -'Cipher'.length);
    const ciphertext = record[field];
    const iv = record[`${base}Iv`];
    if (typeof ciphertext !== 'string' || typeof iv !== 'string') continue;
    out[base] = await decryptText(ciphertext, iv, key);
  }

  out.deleted = record.deleted === true;
  out.updatedAt = Number.isFinite(record.updatedAt) ? record.updatedAt : 0;
  out._schemaVersion = 1;
  out._needsReencrypt = true;
  out._headerTampered = false;
  out._binaryTampered = false;
  // v1 has nowhere to put a digest, exactly as it has nowhere to put a bound
  // header. So a v1 photo is unverified by construction, and the callers'
  // answer is the same one they already give a v1 header: a v1 row may create,
  // never overwrite (see recordHasAuthenticatedHeader).
  out._binaryUnverified = Object.values(record).some(isBinaryValue);
  // A v1 row has nowhere to put a table binding either, so the table it is
  // presented as is unprovable. Same answer as the header and the photo: it may
  // create, never overwrite (recordHasAuthenticatedHeader gates that), so a
  // misfiled v1 row cannot destroy anything that already exists.
  out._tableTampered = false;
  out._tableUnverified = true;
  return out;
}

/**
 * Unpacks a stored record into a flat plain object, whichever schema it uses.
 *
 * v2 rows are decrypted from their envelope. v1 rows left behind by the schema
 * migration are decrypted field-by-field from their `<name>Cipher`/`<name>Iv`
 * pairs, so the app keeps working before (or if) the lazy re-encryption sweep
 * runs. The returned shape is identical either way.
 *
 * @param {Object} record - A raw row from IndexedDB or from a sync message.
 * @param {CryptoKey} key
 * @param {{ table?: string }} [options] - `table` is the table the row is being
 *   PRESENTED as. Supply it on every untrusted path; without it the table
 *   dimension is simply not checked (`_tableTampered` stays false), because
 *   there is nothing to compare the sealed name against.
 * @returns {Promise<Object>} The logical record, plus:
 *   `_schemaVersion` (1 or 2), `_needsReencrypt` (true for v1 rows),
 *   `_headerTampered` (true when some unauthenticated part of the row disagrees
 *   with the authenticated envelope: the plaintext id/updatedAt/deleted, the
 *   attached binary, or the table it is presented as - treat as hostile),
 *   `_binaryTampered` (the binary half of the above, on its own),
 *   `_binaryUnverified` (the row carries binary but its envelope predates
 *   digest binding, or is v1: nothing is wrong, nothing is proven),
 *   `_tableTampered` (the envelope names a different table than `options.table`),
 *   `_tableUnverified` (the envelope predates table binding, or is v1: same
 *   "nothing wrong, nothing proven" verdict, and what the re-seal sweep drains).
 *
 *   `_headerTampered` is meaningful ONLY for v2 rows. A v1 row has no
 *   authenticated header and no digest map to compare anything against, so
 *   decryptLegacyRecord() stamps both tamper flags false unconditionally.
 *   Callers handling untrusted rows must therefore gate on
 *   recordHasAuthenticatedHeader() as well - a false flag on a v1 row means
 *   "unknowable", not "clean".
 * @throws {Error} When the payload does not decrypt with this key.
 */
/**
 * True when `record` actually carries a payload that AES-GCM will authenticate.
 *
 * This is the load-bearing half of every integrity gate, and it exists because
 * decryptRecord() succeeding is NOT evidence that a key was ever exercised.
 * decryptLegacyRecord() only decrypts fields named `<base>Cipher`; a row with
 * none - `{ id, updatedAt, deleted, v }` - walks straight through it, gets
 * `_headerTampered: false` stamped on unconditionally, and resolves. Under the
 * old gates that counted as "decrypted successfully under our key", so a
 * hand-built or foreign row passed the check without holding any key at all.
 *
 * That matters because ids are guessable by construction: the seeded defaults
 * use fixed ids (bkt-default-1, roulette-current) that collide across EVERY
 * vault. An unauthenticated row on a colliding id could therefore overwrite a
 * live encrypted one on both the backup-import and the peer-sync path.
 *
 * So callers handling untrusted rows must require this BEFORE trusting a
 * successful decrypt. A row that carries no ciphertext cannot have come from
 * someone holding the vault key, and is refused rather than merged.
 *
 * @param {unknown} record
 * @returns {boolean}
 */
/**
 * True only when `record` is a v2 envelope, i.e. its plaintext header is
 * cryptographically bound to its contents.
 *
 * THIS IS THE STRONGER CHECK, and the distinction matters more than the names
 * suggest. recordCarriesAuthenticatedPayload() asks whether SOME ciphertext is
 * present. That is not the same as asking whether the id / updatedAt / deleted
 * header can be trusted, and for a v1 row it never can be:
 * decryptLegacyRecord() decrypts each `<base>Cipher` field independently and
 * has no authenticated copy of the header to compare against, so it stamps
 * `_headerTampered: false` unconditionally. It is not a bug there - v1 simply
 * has nowhere to put a bound header.
 *
 * The consequence is a forgery. One ciphertext produced under the vault key -
 * any content at all, and every backup file ships one in its own vaultMeta
 * canary - can be pasted into a hand-built row as a decoy `<base>Cipher` /
 * `<base>Iv` pair. That row then decrypts "successfully", reports no header
 * tampering, and carries whatever id, updatedAt and `deleted: true` the forger
 * chose. Pointed at a live photo it destroys the imageBlob; the attacker never
 * needed the vault passphrase, only the backup file's own passphrase.
 *
 * So untrusted input paths must require THIS, not merely a payload, before
 * letting a row overwrite or delete something that already exists.
 *
 * @param {unknown} record
 * @returns {boolean}
 */
export function recordHasAuthenticatedHeader(record) {
  return Boolean(
    record &&
      typeof record === 'object' &&
      record.v === RECORD_SCHEMA_VERSION &&
      typeof record.ciphertext === 'string' &&
      record.ciphertext.length > 0 &&
      typeof record.iv === 'string' &&
      record.iv.length > 0
  );
}

export function recordCarriesAuthenticatedPayload(record) {
  if (!record || typeof record !== 'object') return false;

  // v2: the whole payload lives in one authenticated envelope.
  if (
    record.v === RECORD_SCHEMA_VERSION &&
    typeof record.ciphertext === 'string' &&
    record.ciphertext.length > 0 &&
    typeof record.iv === 'string' &&
    record.iv.length > 0
  ) {
    return true;
  }

  // v1: at least one complete <base>Cipher / <base>Iv pair must be present.
  for (const field of Object.keys(record)) {
    if (!field.endsWith('Cipher')) continue;
    const base = field.slice(0, -'Cipher'.length);
    if (
      typeof record[field] === 'string' &&
      record[field].length > 0 &&
      typeof record[`${base}Iv`] === 'string' &&
      record[`${base}Iv`].length > 0
    ) {
      return true;
    }
  }

  return false;
}

export async function decryptRecord(record, key, options = {}) {
  if (!record || typeof record !== 'object') {
    throw new Error('decryptRecord: expected a record object');
  }

  const isEnvelope =
    record.v === RECORD_SCHEMA_VERSION &&
    typeof record.ciphertext === 'string' &&
    typeof record.iv === 'string';

  if (!isEnvelope) {
    return await decryptLegacyRecord(record, key);
  }

  const payload = await decryptJSON(record.ciphertext, record.iv, key);
  if (!payload || typeof payload !== 'object') {
    throw new Error('decryptRecord: envelope payload is not an object');
  }

  const out = {};
  for (const [field, value] of Object.entries(payload)) {
    if (INTERNAL_RECORD_FIELDS.has(field)) continue;
    out[field] = value;
  }
  for (const [field, value] of Object.entries(record)) {
    if (isBinaryValue(value)) out[field] = value;
  }

  const innerUpdatedAt = Number.isFinite(payload.updatedAt) ? payload.updatedAt : null;
  const innerDeleted = typeof payload.deleted === 'boolean' ? payload.deleted : null;

  out.id = typeof payload.id === 'string' ? payload.id : record.id;
  out.updatedAt = innerUpdatedAt !== null ? innerUpdatedAt : record.updatedAt;
  out.deleted = innerDeleted !== null ? innerDeleted : record.deleted === true;

  const binaryCheck = await verifyBinaryDigests(record, payload[BINARY_DIGEST_FIELD]);

  // The table the envelope was sealed for, when it carries one. An absent
  // binding is an old row, not a forged one - see TABLE_BINDING_FIELD.
  const sealedTable =
    typeof payload[TABLE_BINDING_FIELD] === 'string' && payload[TABLE_BINDING_FIELD].length > 0
      ? payload[TABLE_BINDING_FIELD]
      : null;
  const expectedTable =
    typeof options.table === 'string' && options.table.length > 0 ? options.table : null;

  out._schemaVersion = RECORD_SCHEMA_VERSION;
  out._needsReencrypt = false;
  out._binaryTampered = binaryCheck.tampered;
  out._binaryUnverified = binaryCheck.unverified;
  out._tableUnverified = sealedTable === null;
  out._tableTampered =
    expectedTable !== null && sealedTable !== null && sealedTable !== expectedTable;
  // `_headerTampered` is the single flag every consumer already gates on, so a
  // swapped photo or a cross-table replay is folded into it rather than needing
  // five UI components to learn a new field. Read it as "some unauthenticated
  // part of this row disagrees with the authenticated envelope";
  // `_binaryTampered` / `_tableTampered` say which.
  out._headerTampered =
    (typeof payload.id === 'string' && payload.id !== record.id) ||
    (innerUpdatedAt !== null && innerUpdatedAt !== record.updatedAt) ||
    (innerDeleted !== null && innerDeleted !== (record.deleted === true)) ||
    binaryCheck.tampered ||
    out._tableTampered;

  return out;
}

/**
 * True when a stored row still uses the pre-migration plaintext-metadata shape.
 * @param {Object} record
 * @returns {boolean}
 */
export function isLegacyRecord(record) {
  if (!record || typeof record !== 'object') return false;
  return !(
    record.v === RECORD_SCHEMA_VERSION &&
    typeof record.ciphertext === 'string' &&
    typeof record.iv === 'string'
  );
}

/* ------------------------------------------------------------------------- *
 * Binary blobs
 * ------------------------------------------------------------------------- */

/**
 * Encrypts a binary image Blob or ArrayBuffer.
 * Packed structure: [12 bytes IV] + [AES-GCM Ciphertext + 16 bytes Auth Tag]
 * @param {Blob|ArrayBuffer} imageBlob
 * @param {CryptoKey} key
 * @returns {Promise<Uint8Array>} Packed binary ready for IndexedDB or P2P transfer
 */
export async function encryptBlob(imageBlob, key) {
  let arrayBuffer;
  if (imageBlob instanceof Blob) {
    arrayBuffer = await imageBlob.arrayBuffer();
  } else {
    arrayBuffer = imageBlob;
  }

  const iv = getCrypto().getRandomValues(new Uint8Array(IV_LENGTH_BYTES));

  const cipherBuffer = await getCrypto().subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    arrayBuffer
  );

  const cipherBytes = new Uint8Array(cipherBuffer);
  const packed = new Uint8Array(IV_LENGTH_BYTES + cipherBytes.byteLength);
  packed.set(iv, 0);
  packed.set(cipherBytes, IV_LENGTH_BYTES);

  return packed;
}

/**
 * Decrypts a binary packed image back into a usable browser Blob.
 * @param {Uint8Array|ArrayBuffer} packedData
 * @param {CryptoKey} key
 * @param {string} mimeType - e.g. "image/webp". Store the real mime on the record
 *   rather than assuming; a compression fallback can leave a JPEG or PNG here.
 * @returns {Promise<Blob>} Decrypted Blob
 */
export async function decryptBlob(packedData, key, mimeType = 'image/webp') {
  const bytes = packedData instanceof Uint8Array ? packedData : new Uint8Array(packedData);

  if (bytes.byteLength < IV_LENGTH_BYTES + 16) {
    throw new Error('Invalid encrypted blob: buffer too small');
  }

  const iv = bytes.slice(0, IV_LENGTH_BYTES);
  const cipherBytes = bytes.slice(IV_LENGTH_BYTES);

  const decryptedBuffer = await getCrypto().subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    cipherBytes
  );

  return new Blob([decryptedBuffer], { type: mimeType });
}

/**
 * Helper: Converts a decrypted image Blob into a memory ObjectURL
 */
export function blobToUrl(blob) {
  return URL.createObjectURL(blob);
}

/* ------------------------------------------------------------------------- *
 * Time-locked letters
 * ------------------------------------------------------------------------- */

const TIME_LOCK_VERSION = 1;
const TIME_LOCK_CONTEXT = 'our-space/time-lock/v1';
const TIME_LOCK_SALT_BYTES = 16;

/**
 * Thrown by unsealTimeLocked when the unlock date has not arrived.
 */
export class TimeLockedError extends Error {
  constructor(unlockDate, unlocksAt) {
    super('This letter is still time-locked');
    this.name = 'TimeLockedError';
    this.unlockDate = unlockDate;
    this.unlocksAt = unlocksAt;
  }
}

/**
 * Resolves an unlock date string to a local-time epoch boundary.
 * A bare 'YYYY-MM-DD' is LOCAL midnight, not UTC midnight - storing local dates
 * and reading them as UTC is what made anniversaries land a day early.
 * @param {string} unlockDate
 * @returns {number|null} Epoch milliseconds, or null when unparseable.
 */
export function getTimeLockBoundary(unlockDate) {
  if (typeof unlockDate !== 'string' || unlockDate.length === 0) return null;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(unlockDate);
  if (dateOnly) {
    return new Date(
      Number(dateOnly[1]),
      Number(dateOnly[2]) - 1,
      Number(dateOnly[3]),
      0,
      0,
      0,
      0
    ).getTime();
  }
  const parsed = new Date(unlockDate).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * @param {Object|string|null} sealedOrDate - A sealed envelope, an unlock date string, or null.
 * @param {number} [now]
 * @returns {boolean} True when the content may be unsealed. An absent or
 *   unparseable date means "not locked".
 */
export function isTimeLockOpen(sealedOrDate, now = Date.now()) {
  const unlockDate =
    typeof sealedOrDate === 'string' ? sealedOrDate : sealedOrDate && sealedOrDate.unlockDate;
  if (!unlockDate) return true;
  const boundary = getTimeLockBoundary(unlockDate);
  if (boundary === null) return true;
  return now >= boundary;
}

function timeLockBinding(unlockDate, context) {
  return `${TIME_LOCK_CONTEXT}|${unlockDate}|${context || ''}`;
}

/**
 * Re-derives the wrapping key for a sealed letter.
 * Deterministic given (vaultKey, lockSalt, lockIv, unlockDate, context).
 */
async function deriveTimeLockKey(vaultKey, { lockSalt, lockIv, unlockDate, context }) {
  const encoder = new TextEncoder();
  const binding = timeLockBinding(unlockDate, context);
  const subtle = getCrypto().subtle;

  // Step 1: squeeze extractable key material out of the non-extractable vault
  // key. AES-GCM over a fixed, date-bound plaintext with a stored per-letter IV
  // gives a value that only the vault key can reproduce, and that changes
  // completely if the unlock date changes.
  const materialBuffer = await subtle.encrypt(
    { name: 'AES-GCM', iv: base64ToBuffer(lockIv) },
    vaultKey,
    encoder.encode(binding)
  );

  // Step 2: run that material through HKDF-SHA256 so the wrapping key is a
  // proper 256-bit uniformly-distributed key rather than raw ciphertext.
  const hkdfKey = await subtle.importKey('raw', materialBuffer, 'HKDF', false, ['deriveKey']);

  return await subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: base64ToBuffer(lockSalt),
      info: encoder.encode(binding),
    },
    hkdfKey,
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    false,
    ['encrypt', 'decrypt']
  );
}

/**
 * Seals letter content behind a real key-wrapping time lock.
 *
 * CONSTRUCTION
 *   contentKey  = random AES-GCM-256
 *   ciphertext  = AES-GCM(contentKey, iv, plaintext, AAD = binding)
 *   binding     = "our-space/time-lock/v1|<unlockDate>|<context>"
 *   material    = AES-GCM(vaultKey, lockIv, binding)
 *   lockKey     = HKDF-SHA256(material, salt = lockSalt, info = binding)
 *   wrappedKey  = AES-GCM(lockKey, wrapIv, rawContentKey, AAD = binding)
 * Only `wrappedKey`, `ciphertext` and the public parameters are stored. The
 * content key itself is never persisted.
 *
 * WHAT THIS ACTUALLY PROTECTS AGAINST
 *  - Editing the stored unlock date to open a letter early. The date feeds both
 *    the key derivation and the AEAD associated data, so a changed date yields a
 *    different wrapping key and decryption FAILS. It is not a check that can be
 *    skipped, patched out of the UI, or bypassed by a bug in a clock comparison.
 *  - Moving a sealed payload onto a different record, when `context` is the
 *    record id. Same mechanism.
 *  - Accidental exposure through ordinary code paths. The body is not present in
 *    the record envelope at all; reaching it requires calling unsealTimeLocked,
 *    which enforces the date.
 *  - Anyone without the vault passphrase, exactly as strongly as every other
 *    record: AES-GCM-256.
 *
 * WHAT THIS DOES **NOT** PROTECT AGAINST - state this plainly, do not oversell it
 *  - The vault owner, or anyone holding the vault passphrase, opening the letter
 *    before the date. Every input needed to re-derive the wrapping key is on the
 *    device from the moment the letter is written. Moving the system clock
 *    forward, or calling this module directly from a console, opens it
 *    immediately. There is no client-side construction that prevents this.
 *  - The partner's device. Both devices share one vault key, so both can do the
 *    above.
 *  - Malware, a malicious extension, or XSS while the vault is unlocked.
 * A genuine time lock needs something this app deliberately does not have: a
 * trusted third party that withholds the key until the date, or a verifiable
 * delay function whose cost is tuned to the wait. Sequential-work schemes were
 * considered and rejected - they punish the honest reader exactly as much as the
 * impatient one, and buy nothing against faster hardware.
 * In short: this makes the lock real against tampering with the data, and honest
 * about being unenforceable against the person who owns the vault.
 *
 * @param {string} plainText - Letter body.
 * @param {string} unlockDate - 'YYYY-MM-DD' (local midnight) or a full ISO string.
 *   Stored verbatim and cryptographically bound.
 * @param {CryptoKey} vaultKey
 * @param {{ context?: string }} [options] - `context` is bound into the key. Pass the
 *   record id, and pass the SAME value to unsealTimeLocked. Omit it in both places
 *   or in neither.
 * @returns {Promise<Object>} Sealed envelope, safe to store and to sync as-is.
 */
export async function sealTimeLocked(plainText, unlockDate, vaultKey, options = {}) {
  if (typeof plainText !== 'string') {
    throw new Error('sealTimeLocked: plainText must be a string');
  }
  if (typeof unlockDate !== 'string' || unlockDate.length === 0) {
    throw new Error('sealTimeLocked: unlockDate is required');
  }
  if (getTimeLockBoundary(unlockDate) === null) {
    throw new Error('sealTimeLocked: unlockDate is not a parseable date');
  }

  const subtle = getCrypto().subtle;
  const context = options.context || '';
  const binding = timeLockBinding(unlockDate, context);

  const lockSalt = generateSecureNonce(TIME_LOCK_SALT_BYTES);
  const lockIv = generateSecureNonce(IV_LENGTH_BYTES);

  const contentKey = await subtle.generateKey(
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    true, // must be extractable so it can be wrapped, then discarded
    ['encrypt', 'decrypt']
  );

  const { ciphertext, iv } = await encryptText(plainText, contentKey, binding);

  const rawContentKey = await subtle.exportKey('raw', contentKey);
  const lockKey = await deriveTimeLockKey(vaultKey, { lockSalt, lockIv, unlockDate, context });
  const wrapIv = getCrypto().getRandomValues(new Uint8Array(IV_LENGTH_BYTES));
  const encoder = new TextEncoder();
  const wrappedBuffer = await subtle.encrypt(
    { name: 'AES-GCM', iv: wrapIv, additionalData: encoder.encode(binding) },
    lockKey,
    rawContentKey
  );

  return {
    lockVersion: TIME_LOCK_VERSION,
    unlockDate,
    lockSalt,
    lockIv,
    wrapIv: bufferToBase64(wrapIv),
    wrappedKey: bufferToBase64(wrappedBuffer),
    ciphertext,
    iv,
  };
}

/**
 * Opens a sealed letter, enforcing the unlock date.
 *
 * @param {Object} sealed - The envelope produced by sealTimeLocked.
 * @param {CryptoKey} vaultKey
 * @param {{ context?: string, now?: number }} [options] - `context` must match the seal.
 * @returns {Promise<string>} The letter body.
 * @throws {TimeLockedError} Before the unlock date.
 * @throws {Error} When the envelope is malformed, the key is wrong, or the stored
 *   unlock date / context has been tampered with.
 */
export async function unsealTimeLocked(sealed, vaultKey, options = {}) {
  if (!sealed || typeof sealed !== 'object') {
    throw new Error('unsealTimeLocked: expected a sealed envelope');
  }
  if (sealed.lockVersion !== TIME_LOCK_VERSION) {
    throw new Error(`unsealTimeLocked: unsupported lock version ${sealed.lockVersion}`);
  }
  const { unlockDate, lockSalt, lockIv, wrapIv, wrappedKey, ciphertext, iv } = sealed;
  if (
    typeof unlockDate !== 'string' ||
    typeof lockSalt !== 'string' ||
    typeof lockIv !== 'string' ||
    typeof wrapIv !== 'string' ||
    typeof wrappedKey !== 'string' ||
    typeof ciphertext !== 'string' ||
    typeof iv !== 'string'
  ) {
    throw new Error('unsealTimeLocked: sealed envelope is missing fields');
  }

  const now = Number.isFinite(options.now) ? options.now : Date.now();
  const boundary = getTimeLockBoundary(unlockDate);
  if (boundary !== null && now < boundary) {
    throw new TimeLockedError(unlockDate, boundary);
  }

  const context = options.context || '';
  const binding = timeLockBinding(unlockDate, context);
  const encoder = new TextEncoder();
  const subtle = getCrypto().subtle;

  const lockKey = await deriveTimeLockKey(vaultKey, { lockSalt, lockIv, unlockDate, context });

  const rawContentKey = await subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: base64ToBuffer(wrapIv),
      additionalData: encoder.encode(binding),
    },
    lockKey,
    base64ToBuffer(wrappedKey)
  );

  const contentKey = await subtle.importKey(
    'raw',
    rawContentKey,
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    false,
    ['decrypt']
  );

  return await decryptText(ciphertext, iv, contentKey, binding);
}

/* ------------------------------------------------------------------------- *
 * Encrypted backup container
 * ------------------------------------------------------------------------- */

const BACKUP_MAGIC = 'OUR_SPACE_ENCRYPTED_VAULT_V1';
const BACKUP_CONTAINER_VERSION = 2;

/**
 * Packs database export into a single AES-GCM 256 encrypted container with fresh salt and IV.
 *
 * The container records its own KDF iteration count, so raising the global
 * constant never makes an older .vault file unreadable.
 *
 * @param {Object} rawVaultData
 * @param {string} passphrase
 * @returns {Promise<Object>} `{ magic, version, salt, kdfIterations, iv, ciphertext, exportedAt }`
 */
export async function createEncryptedBackup(rawVaultData, passphrase) {
  const normalized = normalizePassphrase(passphrase);
  if (normalized.length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long`);
  }

  const salt = generateSalt();
  const backupKey = await deriveKeyFromPassphrase(normalized, salt, {
    iterations: PBKDF2_ITERATIONS_CURRENT,
  });
  const jsonPayload = JSON.stringify(rawVaultData);
  const encrypted = await encryptText(jsonPayload, backupKey);

  return {
    magic: BACKUP_MAGIC,
    version: BACKUP_CONTAINER_VERSION,
    salt,
    kdfIterations: PBKDF2_ITERATIONS_CURRENT,
    iv: encrypted.iv,
    ciphertext: encrypted.ciphertext,
    exportedAt: new Date().toISOString(),
  };
}

/**
 * Decrypts and verifies a single AES-GCM 256 encrypted backup container.
 * Completely fails if tampered, corrupted, or if passphrase is incorrect.
 *
 * Tries the container's recorded iteration count first, then the other known
 * counts, so both v1 (250,000, no field) and v2 (600,000) files open.
 *
 * @param {Object} container
 * @param {string} passphrase
 * @returns {Promise<Object>}
 */
export async function decryptBackupContainer(container, passphrase) {
  if (!container || typeof container !== 'object') {
    throw new Error('Invalid backup: not a valid object');
  }

  if (container.magic !== BACKUP_MAGIC) {
    throw new Error('Invalid backup: unrecognized container header or format');
  }

  if (!container.salt || !container.iv || !container.ciphertext) {
    throw new Error('Invalid backup: missing cryptographic components');
  }

  const iterations = Number.isFinite(container.kdfIterations)
    ? Math.floor(container.kdfIterations)
    : PBKDF2_ITERATIONS_LEGACY;

  let decryptedJson = null;
  try {
    const { key } = await deriveKeyWithVerification(
      passphrase,
      container.salt,
      async (candidate) => {
        // The AES-GCM auth tag is the verifier: it only passes with the right key.
        decryptedJson = await decryptText(container.ciphertext, container.iv, candidate);
        return true;
      },
      { iterations }
    );
    if (!key) throw new Error('Incorrect passphrase');
  } catch {
    throw new Error('Incorrect backup passphrase, or the file has been tampered with.');
  }

  const parsed = JSON.parse(decryptedJson);
  if (!parsed || typeof parsed !== 'object' || !parsed.tables) {
    throw new Error('Invalid backup: malformed payload inside container');
  }

  return parsed;
}
