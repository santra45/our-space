export const PBKDF2_ITERATIONS_CURRENT = 600000;

export const PBKDF2_ITERATIONS = PBKDF2_ITERATIONS_CURRENT;

const AES_KEY_LENGTH = 256;
const IV_LENGTH_BYTES = 12;
const SALT_LENGTH_BYTES = 16;
export const MIN_PASSPHRASE_LENGTH = 16;

export const VAULT_CANARY_TOKEN = 'SWEETHEART_CANARY_VALIDATION_TOKEN';

export const RECORD_SCHEMA_VERSION = 2;

export const PLAINTEXT_RECORD_FIELDS = Object.freeze(['id', 'updatedAt', 'deleted']);

const INTERNAL_RECORD_FIELDS = new Set([
  'v',
  'ciphertext',
  'iv',
  '_del',
  '_schemaVersion',
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

export function generateSecureNonce(byteLength = 16) {
  const bytes = new Uint8Array(byteLength);
  getCrypto().getRandomValues(bytes);
  return bufferToBase64(bytes);
}

export function generateUrlSafeNonce(byteLength = 16) {
  return generateSecureNonce(byteLength).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

const B64_CHUNK_BYTES = 0x8000;

export function bufferToBase64(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';
  for (let offset = 0; offset < bytes.byteLength; offset += B64_CHUNK_BYTES) {
    const chunk = bytes.subarray(offset, Math.min(offset + B64_CHUNK_BYTES, bytes.byteLength));
    binary += String.fromCharCode.apply(null, chunk);
  }
  return getBtoa(binary);
}

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

export function isValidSalt(value) {
  return isValidBase64(value, SALT_LENGTH_BYTES);
}

export function generateSalt() {
  const salt = new Uint8Array(SALT_LENGTH_BYTES);
  getCrypto().getRandomValues(salt);
  return bufferToBase64(salt);
}

export function normalizePassphrase(passphrase) {
  if (typeof passphrase !== 'string') return '';
  return passphrase.normalize('NFKC').trim();
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
    false,
    ['encrypt', 'decrypt']
  );
}

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

export async function deriveVaultKeyBits(passphrase, saltBase64, options) {
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

  const passphraseKey = await getCrypto().subtle.importKey(
    'raw',
    new TextEncoder().encode(effective),
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  return await getCrypto().subtle.deriveBits(
    { name: 'PBKDF2', salt: base64ToBuffer(saltBase64), iterations, hash: 'SHA-256' },
    passphraseKey,
    AES_KEY_LENGTH
  );
}

export async function importVaultKeyFromBits(rawBits) {
  const bytes = rawBits instanceof Uint8Array ? rawBits : new Uint8Array(rawBits);
  if (bytes.byteLength !== AES_KEY_LENGTH / 8) {
    throw new Error('importVaultKeyFromBits: expected 32 bytes of key material');
  }
  return await getCrypto().subtle.importKey(
    'raw',
    bytes,
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    false,
    ['encrypt', 'decrypt']
  );
}

export async function deriveKeyWithVerification(passphrase, saltBase64, verify, options = {}) {
  if (!isValidBase64(saltBase64)) {
    throw new Error('Invalid vault salt');
  }

  const normalized = normalizePassphrase(passphrase);
  const raw = typeof passphrase === 'string' ? passphrase : '';

  const iterationCandidates = [];
  if (Number.isFinite(options.iterations)) iterationCandidates.push(Math.floor(options.iterations));
  iterationCandidates.push(PBKDF2_ITERATIONS_CURRENT);

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
      }
    }
  }

  throw new Error('Incorrect passphrase');
}

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

export async function verifyPassphraseAgainstMeta(passphrase, meta) {
  if (!meta || typeof meta.salt !== 'string') return false;
  try {
    await deriveKeyWithVerification(
      passphrase,
      meta.salt,
      async (key) => (await readCanary(key, meta)) !== null,
      { iterations: Number.isFinite(meta.kdfIterations) ? meta.kdfIterations : PBKDF2_ITERATIONS_CURRENT }
    );
    return true;
  } catch {
    return false;
  }
}

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

export async function encryptJSON(data, key) {
  const jsonString = JSON.stringify(data);
  return await encryptText(jsonString, key);
}

export async function decryptJSON(ciphertextBase64, ivBase64, key) {
  const decryptedText = await decryptText(ciphertextBase64, ivBase64, key);
  return JSON.parse(decryptedText);
}

function isBinaryValue(value) {
  return (
    value instanceof Uint8Array ||
    value instanceof ArrayBuffer ||
    (typeof Blob !== 'undefined' && value instanceof Blob)
  );
}

const BINARY_DIGEST_FIELD = '_bin';

const TABLE_BINDING_FIELD = '_tbl';

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

  const digests = {};
  for (const [field, value] of Object.entries(binary)) {
    digests[field] = await digestBinaryValue(value);
  }
  payload[BINARY_DIGEST_FIELD] = digests;

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

export async function decryptRecord(record, key, options = {}) {
  if (!record || typeof record !== 'object') {
    throw new Error('decryptRecord: expected a record object');
  }

  const isEnvelope =
    record.v === RECORD_SCHEMA_VERSION &&
    typeof record.ciphertext === 'string' &&
    typeof record.iv === 'string';

  if (!isEnvelope) {
    throw new Error('decryptRecord: not a sealed record');
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

  const sealedTable =
    typeof payload[TABLE_BINDING_FIELD] === 'string' && payload[TABLE_BINDING_FIELD].length > 0
      ? payload[TABLE_BINDING_FIELD]
      : null;
  const expectedTable =
    typeof options.table === 'string' && options.table.length > 0 ? options.table : null;

  out._schemaVersion = RECORD_SCHEMA_VERSION;
  out._binaryTampered = binaryCheck.tampered;
  out._binaryUnverified = binaryCheck.unverified;
  out._tableUnverified = sealedTable === null;
  out._tableTampered =
    expectedTable !== null && sealedTable !== null && sealedTable !== expectedTable;
  out._headerTampered =
    (typeof payload.id === 'string' && payload.id !== record.id) ||
    (innerUpdatedAt !== null && innerUpdatedAt !== record.updatedAt) ||
    (innerDeleted !== null && innerDeleted !== (record.deleted === true)) ||
    binaryCheck.tampered ||
    out._tableTampered;

  return out;
}

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

export function blobToUrl(blob) {
  return URL.createObjectURL(blob);
}

const TIME_LOCK_VERSION = 1;
const TIME_LOCK_CONTEXT = 'our-space/time-lock/v1';
const TIME_LOCK_SALT_BYTES = 16;

export class TimeLockedError extends Error {
  constructor(unlockDate, unlocksAt) {
    super('This letter is still time-locked');
    this.name = 'TimeLockedError';
    this.unlockDate = unlockDate;
    this.unlocksAt = unlocksAt;
  }
}

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

async function deriveTimeLockKey(vaultKey, { lockSalt, lockIv, unlockDate, context }) {
  const encoder = new TextEncoder();
  const binding = timeLockBinding(unlockDate, context);
  const subtle = getCrypto().subtle;

  const materialBuffer = await subtle.encrypt(
    { name: 'AES-GCM', iv: base64ToBuffer(lockIv) },
    vaultKey,
    encoder.encode(binding)
  );

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
    true,
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

const BACKUP_MAGIC = 'OUR_SPACE_ENCRYPTED_VAULT_V1';
const BACKUP_CONTAINER_VERSION = 2;

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
    : PBKDF2_ITERATIONS_CURRENT;

  let decryptedJson = null;
  try {
    const { key } = await deriveKeyWithVerification(
      passphrase,
      container.salt,
      async (candidate) => {
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
