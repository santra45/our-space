/**
 * src/services/biometricUnlock.js
 * Quick unlock: open the vault with this phone's fingerprint or face instead of
 * retyping the shared passphrase.
 *
 * WHY THIS EXISTS
 * The master key is held in memory and nowhere else, so every page reload asks
 * for the passphrase again. On a phone that is brutal: the browser evicts
 * backgrounded tabs constantly, so a passphrase long enough to be worth having
 * gets retyped several times a day. The realistic failure mode for this app was
 * never a clever attacker - it was someone quietly giving up on it.
 *
 * HOW IT WORKS
 * WebAuthn's PRF extension turns the phone's own authenticator into a keyed
 * function: give it the same salt twice and it returns the same 32 bytes, but
 * only after a successful fingerprint or face check, and only on this device.
 * Those bytes are stretched with HKDF into a wrapping key, and the vault key's
 * raw bits are sealed under it with AES-GCM.
 *
 *   enrol:  passphrase -> PBKDF2 -> key bits -> sealed under PRF -> stored
 *   unlock: fingerprint -> PRF -> unseal -> import NON-EXTRACTABLE -> in memory
 *
 * WHAT IS STORED, AND WHY IT IS SAFE TO STORE
 * Only ciphertext, a credential id, and two salts. The sealed blob is inert on
 * its own: reproducing the wrapping key needs the authenticator, which will not
 * act without a live user-verification check. Copying localStorage to another
 * device gets you nothing on its own. The passphrase itself is never written
 * down, in any form - that was the original sin this codebase already removed.
 *
 * ONE HONEST CAVEAT ABOUT "THIS DEVICE"
 * Where the passkey lands is the platform's call, not ours. Google Password
 * Manager and iCloud Keychain both SYNC passkeys across an account, so the PRF
 * secret is not necessarily device-bound - a second phone signed into the same
 * account could reproduce the same bytes. What stays local is the sealed blob
 * itself, which lives in this origin's localStorage and syncs nowhere. Opening
 * the vault needs both halves, so the trade still holds; it is just an account
 * boundary rather than a hardware one.
 *
 * WHAT THIS DELIBERATELY GIVES UP
 * Anyone who can unlock the phone can open the vault. That is the entire trade,
 * it is the user's to make, and the UI says so in plain words before enrolling.
 * The passphrase always remains a working way in, so losing the device's
 * biometric never locks anyone out of their own memories.
 */

import {
  bufferToBase64,
  base64ToBuffer,
  isValidBase64,
  deriveVaultKeyBits,
  importVaultKeyFromBits,
} from './crypto.js';

/** Bump this if the sealed-blob shape ever changes; old records are discarded. */
const STORAGE_KEY = 'sweetheart_quick_unlock_v1';

/** Domain separation for the HKDF step, so PRF output is never used raw. */
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

/**
 * A failure the UI can react to differently. `code` is for us; the screens
 * write their own warm copy off the back of it and never show `message`.
 */
export class QuickUnlockError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'QuickUnlockError';
    /** @type {'unsupported'|'cancelled'|'stale'|'failed'|'no-prf'|'already-registered'} */
    this.code = code;
  }
}

/**
 * The Signal API speaks base64url; everything else here speaks plain base64.
 */
function base64ToBase64Url(value) {
  return value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Tells the passkey provider that a credential we made is dead to us.
 *
 * WHY THIS MATTERS MORE THAN IT LOOKS
 * Every enrolment mints a passkey, and the provider - Google Password Manager,
 * iCloud Keychain - keeps it forever unless someone says otherwise. Without
 * this, turning quick unlock off, or an enrolment that fell over halfway,
 * silently left an "Our Space" entry in the password manager that the user had
 * to hunt down and delete by hand. Retiring it is the only tidy-up we can do.
 *
 * Best effort by design: the Signal API is recent, and a provider that does not
 * have it is no worse off than before. Never awaited, never throws.
 *
 * @param {string} credentialId - base64, as stored.
 */
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
    // Fire and forget. A provider that refuses is not an error we can act on.
    if (result && typeof result.catch === 'function') result.catch(() => {});
  } catch {
    // Unsupported, or blocked. Nothing to do and nothing worth saying.
  }
}

/** Overwrites key material we are done with. Cheap, and keeps the heap tidy. */
function zero(bytes) {
  if (bytes instanceof Uint8Array) bytes.fill(0);
  else if (bytes instanceof ArrayBuffer) new Uint8Array(bytes).fill(0);
}

/**
 * A dismissed ceremony is the normal case - she tapped away, or the finger did
 * not read - and must never be dressed up as a failure. Everything else is.
 */
function classifyCeremonyError(err) {
  const name = err && err.name;
  if (name === 'NotAllowedError' || name === 'AbortError') {
    return new QuickUnlockError('cancelled', 'The unlock check was dismissed.');
  }
  if (name === 'NotSupportedError' || name === 'SecurityError') {
    return new QuickUnlockError('unsupported', 'This device cannot do quick unlock.');
  }
  if (name === 'InvalidStateError') {
    // excludeCredentials did its job: this authenticator already holds the
    // passkey we were about to make a second copy of.
    return new QuickUnlockError('already-registered', 'This device already has one.');
  }
  return new QuickUnlockError('failed', 'The unlock check did not complete.');
}

/* ------------------------------------------------------------------ storage */

function readRecord() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    if (!parsed.credentialId || !parsed.prfSalt || !parsed.wrapped || !parsed.wrapIv) return null;
    if (typeof parsed.vaultSalt !== 'string') return null;
    // Shape is not enough - the fields have to be decodable. A record that is
    // malformed rather than merely wrong is treated as "never set up", which
    // puts the setup button back instead of failing every unlock forever.
    if (!isValidBase64(parsed.prfSalt)) return null;
    if (!isValidBase64(parsed.wrapIv)) return null;
    if (!isValidBase64(parsed.wrapped)) return null;
    if (!isValidBase64(parsed.credentialId)) return null;
    return parsed;
  } catch {
    // Storage blocked, or a half-written record. Either way: not enrolled.
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

/**
 * Removes the enrolment, and asks the passkey provider to drop the credential
 * that went with it. Idempotent, and safe when storage is blocked.
 *
 * @param {{ keepCredential?: boolean }} [options] - Set when the credential is
 *   being retired by the caller instead, so it is not signalled twice.
 */
export function forgetBiometricUnlock(options = {}) {
  try {
    if (options.keepCredential !== true) {
      const record = readRecord();
      if (record) retireCredential(record.credentialId);
    }
  } catch {
    // A record we cannot read is a credential we cannot name. Carry on.
  }
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Nothing we can do, and nothing that needs saying out loud.
  }
}

/**
 * Is quick unlock set up on THIS device for THIS vault?
 *
 * The vault salt is part of the answer on purpose. Starting a new space or
 * restoring a backup mints a fresh salt, which strands the old sealed blob - it
 * would unseal to bits that decrypt nothing. Checking the salt turns that into
 * a clean "not set up" instead of a confusing failed unlock later on.
 *
 * @param {string} vaultSalt - The live vault's salt, from vaultMeta.
 * @returns {boolean}
 */
export function isBiometricEnrolled(vaultSalt) {
  const record = readRecord();
  if (!record) return false;
  return typeof vaultSalt === 'string' && record.vaultSalt === vaultSalt;
}

/**
 * Can this device do it at all? Requires a platform authenticator - the phone's
 * own sensor - not a roaming security key someone could walk off with.
 *
 * @returns {Promise<boolean>}
 */
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

/* -------------------------------------------------------------- prf plumbing */

function readPrfOutput(credential) {
  try {
    const results = credential.getClientExtensionResults();
    const first = results && results.prf && results.prf.results && results.prf.results.first;
    return first ? new Uint8Array(first) : null;
  } catch {
    return null;
  }
}

/**
 * Stretches raw PRF output into an AES-GCM wrapping key.
 *
 * The PRF bytes are never used as a key directly. HKDF with a fixed info string
 * keeps this use of the authenticator separate from any other use it might be
 * put to later, so two features could share one credential without ever sharing
 * a key.
 */
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

/**
 * Binds the sealed blob to the vault and the credential that sealed it. A blob
 * moved between vaults, or replayed against a different credential, fails its
 * auth tag rather than quietly unsealing into the wrong key.
 */
function wrapAad(vaultSalt, credentialId) {
  return new TextEncoder().encode(HKDF_INFO + '|' + vaultSalt + '|' + credentialId);
}

/**
 * Runs a get() ceremony and returns the PRF bytes.
 * @param {string} credentialId - base64
 * @param {Uint8Array} prfSaltBytes
 * @param {string[]} [transports] - What the credential said it speaks. Passing
 *   it back helps the browser go straight to the right authenticator instead
 *   of offering a chooser.
 * @returns {Promise<Uint8Array>}
 */
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
    // The check itself passed, so the sensor is fine. This passkey store just
    // will not do PRF, which is a different problem with a different answer.
    throw new QuickUnlockError('no-prf', 'The passkey store returned no PRF output.');
  }
  return prf;
}

/* ------------------------------------------------------------------ enrolment */

/**
 * Sets quick unlock up on this device.
 *
 * Needs the passphrase because that is the only way to reach the key's raw
 * bits - the unlocked in-memory key is non-extractable by design and cannot be
 * asked for them. Asking again also means enrolling is a deliberate act by
 * someone who knows the secret, rather than something a borrowed unlocked phone
 * can quietly do for itself.
 *
 * @param {{ passphrase: string, vaultSalt: string, iterations: number,
 *   normalize?: boolean }} args - `normalize` must be the flag the vault's own
 *   verification returned, not a guess.
 * @returns {Promise<void>}
 * @throws {QuickUnlockError}
 */
export async function enableBiometricUnlock({ passphrase, vaultSalt, iterations, normalize }) {
  if (!(await isBiometricAvailable())) {
    throw new QuickUnlockError('unsupported', 'No platform authenticator on this device.');
  }
  if (typeof vaultSalt !== 'string' || !vaultSalt) {
    throw new QuickUnlockError('failed', 'Missing vault salt.');
  }

  const prfSaltBytes = randomBytes(PRF_SALT_BYTES);

  // Anything left here from before has to go, and its passkey with it.
  //
  // excludeCredentials looked like the tidier answer and is a trap: a stale
  // record belongs to a vault that no longer exists, the UI offers "Set it up"
  // rather than "Turn off" in that state, and InvalidStateError would strand
  // her with no way forward at all. Retiring it up front reaches the same end -
  // no duplicate passkey - and always leaves a path through.
  //
  // Only stale records are cleared here. One matching this vault is not
  // reachable from the UI, and if it ever became reachable it must not be
  // thrown away before its replacement exists.
  const previous = readRecord();
  if (previous && previous.vaultSalt !== vaultSalt) {
    retireCredential(previous.credentialId);
    forgetBiometricUnlock({ keepCredential: true });
  }

  let credential;
  try {
    credential = await navigator.credentials.create({
      publicKey: {
        // rp.id is deliberately omitted: it then defaults to this origin, which
        // keeps localhost and the deployed domain each working on their own
        // terms instead of one of them silently mismatching.
        rp: { name: 'Our Space' },
        // Nothing identifying goes in here - this shows up in the phone's own
        // passkey list, which is readable by anyone holding the phone.
        user: {
          id: randomBytes(USER_HANDLE_BYTES),
          name: 'Our Space',
          displayName: 'Our Space',
        },
        challenge: randomBytes(CHALLENGE_BYTES),
        pubKeyCredParams: [
          { type: 'public-key', alg: -7 }, // ES256
          { type: 'public-key', alg: -257 }, // RS256
        ],
        authenticatorSelection: {
          authenticatorAttachment: 'platform',
          userVerification: 'required',
          // Google Password Manager and iCloud Keychain both store passkeys as
          // DISCOVERABLE credentials, and PRF rides along on the passkey. Asking
          // for 'discouraged' - which is what we did first - asks for the one
          // shape neither of them really implements.
          residentKey: 'required',
          requireResidentKey: true,
        },
        // We have no server and verify nothing, so attestation would be a
        // privacy leak we could not even make use of.
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

  // FROM HERE ON A PASSKEY EXISTS. Every path out of this function that is not
  // a stored, working enrolment has to retire it, or it becomes another dead
  // "Our Space" entry in the user's password manager for them to clean up.
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
    // Optional everywhere. Its absence costs us nothing but a chooser.
  }

  // Some browsers hand back PRF output on create(), others only on get(). Take
  // it if it is there, and run one more ceremony if it is not - that second
  // prompt is the browser being awkward, not us asking twice for fun.
  let prfOutput = readPrfOutput(credential);
  if (!prfOutput) {
    // An explicit `enabled: false` is the provider saying it will not do PRF at
    // all. Believe it the first time: prompting again would spend a second
    // fingerprint check to be told the same thing.
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
    // normalize must match whatever the vault actually verified under. A vault
    // created before normalizePassphrase existed can be keyed on the raw string
    // with a stray trailing space in it; sealing the normalised bits instead
    // would produce a key that unseals perfectly and then decrypts nothing.
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

    // Prove the seal round-trips before promising her it worked. The PRF bytes
    // are already in hand, so this costs nothing and needs no second prompt.
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

    // The replacement is on disk, so the one it replaced is safe to retire.
    // Order matters: doing this any earlier would risk retiring the only
    // working credential on a setup that then failed.
    if (previous && previous.credentialId !== credentialId) {
      retireCredential(previous.credentialId);
    }
  } catch (err) {
    // keepCredential: this one is retired by abandon(), not by the record - the
    // record may never have been written, and signalling twice is noise.
    forgetBiometricUnlock({ keepCredential: true });
    retireCredential(credentialId);
    if (err instanceof QuickUnlockError) throw err;
    throw new QuickUnlockError('failed', 'Quick unlock could not be set up.');
  } finally {
    zero(keyBits);
    zero(prfOutput);
  }
}

/* -------------------------------------------------------------------- unlock */

/**
 * Opens the vault with the phone's own unlock check.
 *
 * The key that comes back is NOT trusted yet. The caller must still prove it
 * against the vault canary before adopting it - a sealed blob that unseals
 * cleanly but predates a change to the vault would otherwise be adopted as a
 * working key and then fail on every record it touched.
 *
 * @param {string} vaultSalt - The live vault's salt.
 * @returns {Promise<{ key: CryptoKey, iterations: number|null }>}
 * @throws {QuickUnlockError}
 */
export async function unlockWithBiometric(vaultSalt) {
  const record = readRecord();
  if (!record) {
    throw new QuickUnlockError('stale', 'Quick unlock is not set up here.');
  }
  if (record.vaultSalt !== vaultSalt) {
    // A different space lives here now. The old blob can never be useful again.
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

    // ONLY an auth-tag failure proves the blob is permanently dead - AES-GCM
    // reports that as OperationError. Wiping on *any* exception was too eager:
    // a transient import failure would throw away a perfectly good enrolment
    // and quietly demote her to typing the passphrase forever.
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
