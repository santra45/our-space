let vaultKey = null;

let keyInfo = { salt: null, iterations: null, unlockedAt: 0 };

const listeners = new Set();

function notify() {
  const unlocked = vaultKey !== null;
  for (const listener of Array.from(listeners)) {
    try {
      listener(unlocked);
    } catch {
    }
  }
}

export function setVaultKey(key, info = {}) {
  if (typeof key === 'string') {
    throw new Error('setVaultKey: refusing to store a string. Pass a CryptoKey, never a passphrase.');
  }
  if (!key || typeof key !== 'object' || key.type !== 'secret') {
    throw new Error('setVaultKey: expected a secret CryptoKey');
  }
  if (key.extractable === true) {
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

export function getVaultKey() {
  return vaultKey;
}

export function requireVaultKey() {
  if (!vaultKey) {
    throw new Error('Vault is locked. The passphrase must be entered again.');
  }
  return vaultKey;
}

export function hasVaultKey() {
  return vaultKey !== null;
}

export function getVaultKeyInfo() {
  return { ...keyInfo, unlocked: vaultKey !== null };
}

export function clearVaultKey() {
  const wasUnlocked = vaultKey !== null;
  vaultKey = null;
  keyInfo = { salt: null, iterations: null, unlockedAt: 0 };
  if (wasUnlocked) notify();
}

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
