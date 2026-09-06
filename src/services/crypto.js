/**
 * src/services/crypto.js
 * Zero-Knowledge Web Crypto API Engine
 * - Algorithm: AES-GCM 256-bit
 * - Key Derivation: PBKDF2 with HMAC-SHA-256 (250,000 iterations)
 * - Unique 96-bit (12-byte) IV for every encryption operation
 */

const PBKDF2_ITERATIONS = 250000;
const AES_KEY_LENGTH = 256;
const IV_LENGTH_BYTES = 12; // 96 bits recommended for AES-GCM
const SALT_LENGTH_BYTES = 16;
export const MIN_PASSPHRASE_LENGTH = 16;

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
 * Utility: Convert ArrayBuffer to Base64 string
 */
export function bufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return getBtoa(binary);
}

/**
 * Utility: Convert Base64 string to Uint8Array
 */
export function base64ToBuffer(base64) {
  const binary = getAtob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
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
 * Derives an AES-GCM 256-bit CryptoKey from a user passphrase and salt using PBKDF2.
 * Enforces a strict minimum passphrase length of 16 characters.
 * @param {string} passphrase - The shared secret passphrase
 * @param {string} saltBase64 - The base64-encoded salt
 * @returns {Promise<CryptoKey>} - AES-GCM CryptoKey ready for encryption/decryption
 */
export async function deriveKeyFromPassphrase(passphrase, saltBase64) {
  if (typeof passphrase !== 'string' || passphrase.length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long`);
  }

  const encoder = new TextEncoder();
  const passphraseKey = await getCrypto().subtle.importKey(
    'raw',
    encoder.encode(passphrase),
    { name: 'PBKDF2' },
    false,
    ['deriveKey']
  );

  const saltBuffer = base64ToBuffer(saltBase64);

  return await getCrypto().subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBuffer,
      iterations: PBKDF2_ITERATIONS,
      hash: 'SHA-256',
    },
    passphraseKey,
    { name: 'AES-GCM', length: AES_KEY_LENGTH },
    false, // Master key is non-extractable from browser memory
    ['encrypt', 'decrypt']
  );
}

/**
 * Encrypts a plaintext UTF-8 string with AES-GCM 256.
 * @param {string} plainText 
 * @param {CryptoKey} key 
 * @returns {Promise<{ ciphertext: string, iv: string }>}
 */
export async function encryptText(plainText, key) {
  const encoder = new TextEncoder();
  const iv = getCrypto().getRandomValues(new Uint8Array(IV_LENGTH_BYTES));
  const encodedData = encoder.encode(plainText);

  const cipherBuffer = await getCrypto().subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    encodedData
  );

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
 * @returns {Promise<string>} Plaintext UTF-8 string
 */
export async function decryptText(ciphertextBase64, ivBase64, key) {
  const decoder = new TextDecoder();
  const iv = base64ToBuffer(ivBase64);
  const cipherBuffer = base64ToBuffer(ciphertextBase64);

  const decryptedBuffer = await getCrypto().subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    cipherBuffer
  );

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
 * @param {string} mimeType - e.g. "image/webp"
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

const BACKUP_MAGIC = 'OUR_SPACE_ENCRYPTED_VAULT_V1';

/**
 * Packs database export into a single AES-GCM 256 encrypted container with fresh salt and IV.
 * @param {Object} rawVaultData
 * @param {string} passphrase
 * @returns {Promise<Object>}
 */
export async function createEncryptedBackup(rawVaultData, passphrase) {
  if (typeof passphrase !== 'string' || passphrase.length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long`);
  }

  const salt = generateSalt();
  const backupKey = await deriveKeyFromPassphrase(passphrase, salt);
  const jsonPayload = JSON.stringify(rawVaultData);
  const encrypted = await encryptText(jsonPayload, backupKey);

  return {
    magic: BACKUP_MAGIC,
    version: 1,
    salt,
    iv: encrypted.iv,
    ciphertext: encrypted.ciphertext,
    exportedAt: new Date().toISOString(),
  };
}

/**
 * Decrypts and verifies a single AES-GCM 256 encrypted backup container.
 * Completely fails if tampered, corrupted, or if passphrase is incorrect.
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

  const backupKey = await deriveKeyFromPassphrase(passphrase, container.salt);
  // AES-GCM 256 decryption verifies the 128-bit authentication tag
  const decryptedJson = await decryptText(container.ciphertext, container.iv, backupKey);
  
  const parsed = JSON.parse(decryptedJson);
  if (!parsed || typeof parsed !== 'object' || !parsed.tables) {
    throw new Error('Invalid backup: malformed payload inside container');
  }

  return parsed;
}
