/**
 * src/services/deviceId.js
 * A stable tag for this device, so a record can say which of the two of you
 * wrote it.
 *
 * WHY NOT THE PEER ID
 * That one is allowed to change - it is regenerated whenever the signalling
 * broker reports a collision. A device whose tag moved would start a second
 * tally beside its own and read to the other person as a stranger arriving with
 * a backlog. This one is minted once and never rotates.
 *
 * WHY THIS IS NOT AN IDENTITY
 * It says "the device that wrote this", not "who". Two devices belonging to the
 * same person would look like two people, which is a real limitation and an
 * acceptable one: this vault is built for exactly two devices, and both
 * features that use the tag degrade gently rather than corrupt anything if that
 * ever stops being true.
 *
 * It never leaves the device in the clear - it lives in localStorage and inside
 * sealed record bodies, and nowhere else.
 */

import { generateUrlSafeNonce } from './crypto.js';

const STORAGE_KEY = 'sweetheart_device_owner_v1';

/** Older key, from when love bursts owned this concept alone. Adopted if present. */
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

/**
 * This device's tag, minted on first use.
 *
 * Cached in memory as well as stored, so a device whose storage is blocked
 * still keeps ONE consistent tag for the life of the page rather than inventing
 * a new one on every call and littering the vault with phantom authors.
 *
 * @returns {string}
 */
export function getDeviceId() {
  if (cached) return cached;

  const current = read(STORAGE_KEY);
  if (typeof current === 'string' && VALID.test(current)) {
    cached = current;
    return cached;
  }

  // Adopt the love-burst tag if this device already had one, so an existing
  // tally keeps belonging to the device that made it.
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
