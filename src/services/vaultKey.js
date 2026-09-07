/**
 * src/services/vaultKey.js
 * In-memory holder for the unlocked vault key.
 *
 * WHY THIS MODULE EXISTS
 * Auto-unlock used to work by writing the user's PLAINTEXT passphrase into
 * sessionStorage. Any XSS on the origin could read it and reconstruct the
 * master key. This module replaces that entirely: the derived, NON-EXTRACTABLE
 * CryptoKey lives in a module-scoped variable and nowhere else.
 *
 * GUARANTEES
 *  - Nothing here touches localStorage, sessionStorage, IndexedDB, cookies or
 *    the URL. The key exists only in the JS heap of this page.
 *  - The key is a non-extractable CryptoKey, so even code that reaches this
 *    module cannot export raw key bytes; it can only use the key for
 *    encrypt/decrypt while the page lives.
 *  - Module state survives SPA route changes (same JS realm) so the vault stays
 *    unlocked while the user navigates.
 *  - Module state does NOT survive a page reload, a new tab, or a browser
 *    restart. Those require re-entering the passphrase. That is intentional.
 *
 * WHAT IT DOES NOT PROTECT AGAINST
 *  - Script running in the page while the vault is unlocked. An XSS payload can
 *    call getVaultKey() and use the key for as long as the page is open. It
 *    cannot exfiltrate the key material itself or reuse it after a reload,
 *    which is strictly better than handing over the passphrase, but it is not
 *    immunity.
 */

/** @type {CryptoKey|null} */
let vaultKey = null;

/** @type {{ salt: string|null, iterations: number|null, unlockedAt: number }} */
let keyInfo = { salt: null, iterations: null, unlockedAt: 0 };

/** @type {Set<(unlocked: boolean) => void>} */
const listeners = new Set();

function notify() {
  const unlocked = vaultKey !== null;
  for (const listener of Array.from(listeners)) {
    try {
      listener(unlocked);
    } catch {
      // A broken subscriber must not stop the others.
    }
  }
}

/**
 * Stores the unlocked vault key for the lifetime of this page session.
 *
 * @param {CryptoKey} key - Non-extractable AES-GCM key from deriveKeyFromPassphrase.
 * @param {{ salt?: string, iterations?: number }} [info] - Non-secret metadata about
 *   how the key was derived. NEVER pass a passphrase here.
 * @returns {CryptoKey} The stored key.
 */
export function setVaultKey(key, info = {}) {
  if (typeof key === 'string') {
    throw new Error('setVaultKey: refusing to store a string. Pass a CryptoKey, never a passphrase.');
  }
  if (!key || typeof key !== 'object' || key.type !== 'secret') {
    throw new Error('setVaultKey: expected a secret CryptoKey');
  }
  if (key.extractable === true) {
    // Loud in dev, tolerated at runtime: an extractable master key defeats the
    // point of holding it here instead of holding the passphrase.
    console.warn('[vaultKey] Stored key is extractable. Derive it with extractable=false.');
  }

  vaultKey = key;
  keyInfo = {
    salt: typeof info.salt === 'string' ? info.salt : null,
    iterations: Number.isFinite(info.iterations) ? info.iterations : null,
    unlockedAt: Date.now(),
  };
  notify();
  return vaultKey;
}

/**
 * @returns {CryptoKey|null} The unlocked key, or null when locked.
 */
export function getVaultKey() {
  return vaultKey;
}

/**
 * @returns {CryptoKey} The unlocked key.
 * @throws {Error} When the vault is locked. Use this on paths that cannot
 *   meaningfully continue without a key, so the failure is loud instead of a
 *   silent no-op.
 */
export function requireVaultKey() {
  if (!vaultKey) {
    throw new Error('Vault is locked. The passphrase must be entered again.');
  }
  return vaultKey;
}

/**
 * @returns {boolean} True while a key is held in memory.
 */
export function hasVaultKey() {
  return vaultKey !== null;
}

/**
 * Non-secret details about the current key derivation. Safe to log.
 * @returns {{ salt: string|null, iterations: number|null, unlockedAt: number, unlocked: boolean }}
 */
export function getVaultKeyInfo() {
  return { ...keyInfo, unlocked: vaultKey !== null };
}

/**
 * Drops the key. Call on lock, on sign-out, and on any hard auth failure.
 * Idempotent.
 */
export function clearVaultKey() {
  const wasUnlocked = vaultKey !== null;
  vaultKey = null;
  keyInfo = { salt: null, iterations: null, unlockedAt: 0 };
  if (wasUnlocked) notify();
}

/**
 * Subscribes to lock/unlock transitions.
 * @param {(unlocked: boolean) => void} listener
 * @returns {() => void} Unsubscribe function.
 */
export function subscribeVaultKey(listener) {
  if (typeof listener !== 'function') return () => {};
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export default {
  setVaultKey,
  getVaultKey,
  requireVaultKey,
  hasVaultKey,
  getVaultKeyInfo,
  clearVaultKey,
  subscribeVaultKey,
};
