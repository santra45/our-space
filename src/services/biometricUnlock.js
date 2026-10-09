import {
  bufferToBase64,
  base64ToBuffer,
  isValidBase64,
  deriveVaultKeyBits,
  importVaultKeyFromBits,
} from './crypto.js';

const STORAGE_KEY = 'sweetheart_quick_unlock_v1';

const HKDF_INFO = 'our-space/quick-unlock/v1';

const PRF_SALT_BYTES = 32;
const CHALLENGE_BYTES = 32;
const USER_HANDLE_BYTES = 16;
const KEY_BYTES = 32;
const CEREMONY_TIMEOUT_MS = 60000;

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);
const subtle = () => webCrypto().subtle;
const randomBytes = (n) => {
  const out = new Uint8Array(n);
  webCrypto().getRandomValues(out);
  return out;
};

export class QuickUnlockError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'QuickUnlockError';
    this.code = code;
  }
}

function base64ToBase64Url(value) {
  return value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function retireCredential(credentialId) {
  try {
    if (typeof credentialId !== 'string' || !credentialId) return;
    if (typeof window === 'undefined' || !window.PublicKeyCredential) return;
    const signal = window.PublicKeyCredential.signalUnknownCredential;
    if (typeof signal !== 'function') return;

    const result = window.PublicKeyCredential.signalUnknownCredential({
      rpId: window.location.hostname,
      credentialId: base64ToBase64Url(credentialId),
    });
    if (result && typeof result.catch === 'function') result.catch(() => {});
  } catch {
  }
}

function zero(bytes) {
  if (bytes instanceof Uint8Array) bytes.fill(0);
  else if (bytes instanceof ArrayBuffer) new Uint8Array(bytes).fill(0);
}

function classifyCeremonyError(err) {
  const name = err && err.name;
  if (name === 'NotAllowedError' || name === 'AbortError') {
    return new QuickUnlockError('cancelled', 'The unlock check was dismissed.');
  }
  if (name === 'NotSupportedError' || name === 'SecurityError') {
    return new QuickUnlockError('unsupported', 'This device cannot do quick unlock.');
  }
  if (name === 'InvalidStateError') {
    return new QuickUnlockError('already-registered', 'This device already has one.');
  }
  return new QuickUnlockError('failed', 'The unlock check did not complete.');
}

function readRecord() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    if (!parsed.credentialId || !parsed.prfSalt || !parsed.wrapped || !parsed.wrapIv) return null;
    if (typeof parsed.vaultSalt !== 'string') return null;
    if (!isValidBase64(parsed.prfSalt)) return null;
    if (!isValidBase64(parsed.wrapIv)) return null;
    if (!isValidBase64(parsed.wrapped)) return null;
    if (!isValidBase64(parsed.credentialId)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeRecord(record) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(record));
    return true;
  } catch {
    return false;
  }
}

export function forgetBiometricUnlock(options = {}) {
  try {
    if (options.keepCredential !== true) {
      const record = readRecord();
      if (record) retireCredential(record.credentialId);
    }
  } catch {
  }
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
  }
}

export function isBiometricEnrolled(vaultSalt) {
  const record = readRecord();
  if (!record) return false;
  return typeof vaultSalt === 'string' && record.vaultSalt === vaultSalt;
}

export async function isBiometricAvailable() {
  try {
    if (typeof window === 'undefined') return false;
    if (!window.isSecureContext) return false;
    if (!window.PublicKeyCredential) return false;
    const probe = window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable;
    if (typeof probe !== 'function') return false;
    return await window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
  } catch {
    return false;
  }
}

function readPrfOutput(credential) {
  try {
    const results = credential.getClientExtensionResults();
    const first = results && results.prf && results.prf.results && results.prf.results.first;
    return first ? new Uint8Array(first) : null;
  } catch {
    return null;
  }
}

async function deriveWrappingKey(prfOutput, prfSaltBytes) {
  const material = await subtle().importKey('raw', prfOutput, 'HKDF', false, ['deriveKey']);
  return await subtle().deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: prfSaltBytes,
      info: new TextEncoder().encode(HKDF_INFO),
    },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

function wrapAad(vaultSalt, credentialId) {
  return new TextEncoder().encode(HKDF_INFO + '|' + vaultSalt + '|' + credentialId);
}

async function getPrfViaAssertion(credentialId, prfSaltBytes, transports) {
  let assertion;
  try {
    assertion = await navigator.credentials.get({
      publicKey: {
        challenge: randomBytes(CHALLENGE_BYTES),
        allowCredentials: [
          {
            id: base64ToBuffer(credentialId),
            type: 'public-key',
            ...(Array.isArray(transports) && transports.length ? { transports } : {}),
          },
        ],
        userVerification: 'required',
        timeout: CEREMONY_TIMEOUT_MS,
        extensions: { prf: { eval: { first: prfSaltBytes } } },
      },
    });
  } catch (err) {
    throw classifyCeremonyError(err);
  }
  if (!assertion) throw new QuickUnlockError('cancelled', 'No assertion was returned.');

  const prf = readPrfOutput(assertion);
  if (!prf) {
    throw new QuickUnlockError('no-prf', 'The passkey store returned no PRF output.');
  }
  return prf;
}

export async function enableBiometricUnlock({ passphrase, vaultSalt, iterations, normalize }) {
  if (!(await isBiometricAvailable())) {
    throw new QuickUnlockError('unsupported', 'No platform authenticator on this device.');
  }
  if (typeof vaultSalt !== 'string' || !vaultSalt) {
    throw new QuickUnlockError('failed', 'Missing vault salt.');
  }

  const prfSaltBytes = randomBytes(PRF_SALT_BYTES);

  const previous = readRecord();
  if (previous && previous.vaultSalt !== vaultSalt) {
    retireCredential(previous.credentialId);
    forgetBiometricUnlock({ keepCredential: true });
  }

  let credential;
  try {
    credential = await navigator.credentials.create({
      publicKey: {
        rp: { name: 'Our Space' },
        user: {
          id: randomBytes(USER_HANDLE_BYTES),
          name: 'Our Space',
          displayName: 'Our Space',
        },
        challenge: randomBytes(CHALLENGE_BYTES),
        pubKeyCredParams: [
          { type: 'public-key', alg: -7 },
          { type: 'public-key', alg: -257 },
        ],
        authenticatorSelection: {
          authenticatorAttachment: 'platform',
          userVerification: 'required',
          residentKey: 'required',
          requireResidentKey: true,
        },
        attestation: 'none',
        timeout: CEREMONY_TIMEOUT_MS,
        extensions: { prf: { eval: { first: prfSaltBytes } } },
      },
    });
  } catch (err) {
    throw classifyCeremonyError(err);
  }
  if (!credential) throw new QuickUnlockError('cancelled', 'No credential was created.');

  const credentialId = bufferToBase64(credential.rawId);

  const abandon = (err) => {
    retireCredential(credentialId);
    return err;
  };

  let transports = [];
  try {
    const reported = credential.response && credential.response.getTransports;
    if (typeof reported === 'function') {
      const list = credential.response.getTransports();
      if (Array.isArray(list)) transports = list;
    }
  } catch {
  }

  let prfOutput = readPrfOutput(credential);
  if (!prfOutput) {
    let enabled;
    try {
      const results = credential.getClientExtensionResults();
      enabled = results && results.prf ? results.prf.enabled : undefined;
    } catch {
      enabled = undefined;
    }
    if (enabled === false) {
      throw abandon(
        new QuickUnlockError('no-prf', 'The provider declined PRF at registration.')
      );
    }

    try {
      prfOutput = await getPrfViaAssertion(credentialId, prfSaltBytes, transports);
    } catch (err) {
      throw abandon(err);
    }
  }

  let keyBits = null;
  try {
    const wrappingKey = await deriveWrappingKey(prfOutput, prfSaltBytes);
    keyBits = new Uint8Array(
      await deriveVaultKeyBits(passphrase, vaultSalt, {
        iterations,
        normalize: normalize !== false,
      })
    );

    const wrapIv = randomBytes(12);
    const aad = wrapAad(vaultSalt, credentialId);
    const sealed = await subtle().encrypt(
      { name: 'AES-GCM', iv: wrapIv, additionalData: aad },
      wrappingKey,
      keyBits
    );

    const check = new Uint8Array(
      await subtle().decrypt({ name: 'AES-GCM', iv: wrapIv, additionalData: aad }, wrappingKey, sealed)
    );
    const matches = check.length === keyBits.length && check.every((b, i) => b === keyBits[i]);
    zero(check);
    if (!matches) throw new QuickUnlockError('failed', 'Sealed key did not round-trip.');

    const stored = writeRecord({
      credentialId,
      prfSalt: bufferToBase64(prfSaltBytes),
      wrapIv: bufferToBase64(wrapIv),
      wrapped: bufferToBase64(sealed),
      vaultSalt,
      transports,
      iterations: Number.isFinite(iterations) ? iterations : null,
      createdAt: Date.now(),
    });
    if (!stored) {
      throw new QuickUnlockError('failed', 'This browser would not save the setup.');
    }

    if (previous && previous.credentialId !== credentialId) {
      retireCredential(previous.credentialId);
    }
  } catch (err) {
    forgetBiometricUnlock({ keepCredential: true });
    retireCredential(credentialId);
    if (err instanceof QuickUnlockError) throw err;
    throw new QuickUnlockError('failed', 'Quick unlock could not be set up.');
  } finally {
    zero(keyBits);
    zero(prfOutput);
  }
}

export async function unlockWithBiometric(vaultSalt) {
  const record = readRecord();
  if (!record) {
    throw new QuickUnlockError('stale', 'Quick unlock is not set up here.');
  }
  if (record.vaultSalt !== vaultSalt) {
    forgetBiometricUnlock();
    throw new QuickUnlockError('stale', 'This setup belongs to a different space.');
  }

  const prfSaltBytes = new Uint8Array(base64ToBuffer(record.prfSalt));
  const prfOutput = await getPrfViaAssertion(
    record.credentialId,
    prfSaltBytes,
    record.transports
  );

  let keyBits = null;
  try {
    const wrappingKey = await deriveWrappingKey(prfOutput, prfSaltBytes);
    keyBits = new Uint8Array(
      await subtle().decrypt(
        {
          name: 'AES-GCM',
          iv: base64ToBuffer(record.wrapIv),
          additionalData: wrapAad(record.vaultSalt, record.credentialId),
        },
        wrappingKey,
        base64ToBuffer(record.wrapped)
      )
    );
    if (keyBits.byteLength !== KEY_BYTES) {
      throw new QuickUnlockError('stale', 'Sealed key is the wrong size.');
    }

    const key = await importVaultKeyFromBits(keyBits);
    return { key, iterations: Number.isFinite(record.iterations) ? record.iterations : null };
  } catch (err) {
    if (err instanceof QuickUnlockError) throw err;

    if (err && err.name === 'OperationError') {
      forgetBiometricUnlock();
      throw new QuickUnlockError('stale', 'The saved key could not be opened.');
    }
    throw new QuickUnlockError('failed', 'The saved key could not be read this time.');
  } finally {
    zero(keyBits);
    zero(prfOutput);
  }
}

export default {
  isBiometricAvailable,
  isBiometricEnrolled,
  enableBiometricUnlock,
  unlockWithBiometric,
  forgetBiometricUnlock,
  QuickUnlockError,
};
