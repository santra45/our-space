import { generateUrlSafeNonce } from './crypto.js';

const STORAGE_KEY = 'sweetheart_device_owner_v1';

const LEGACY_KEY = 'sweetheart_burst_owner_v1';

const VALID = /^[A-Za-z0-9_-]{8,64}$/;

let cached = null;

function read(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

export function getDeviceId() {
  if (cached) return cached;

  const current = read(STORAGE_KEY);
  if (typeof current === 'string' && VALID.test(current)) {
    cached = current;
    return cached;
  }

  const legacy = read(LEGACY_KEY);
  if (typeof legacy === 'string' && VALID.test(legacy)) {
    cached = legacy;
    write(STORAGE_KEY, cached);
    return cached;
  }

  cached = generateUrlSafeNonce(12);
  write(STORAGE_KEY, cached);
  return cached;
}

export default { getDeviceId };
