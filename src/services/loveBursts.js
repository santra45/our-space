/**
 * src/services/loveBursts.js
 * Love bursts that survive being sent to a phone that is not listening.
 *
 * WHY THIS IS NOT ONE RECORD PER BURST
 * The obvious shape - append a row every time someone taps the button - is a
 * trap in a peer-to-peer app. Sync compares whole manifests, so every burst
 * ever sent would be listed on every reconnection for the rest of the
 * relationship. A few taps a day is a few thousand manifest entries a year, and
 * pruning them does not help: a deletion here is a tombstone, which is another
 * row in the same manifest.
 *
 * So each device keeps ONE record with a running count. Sending increments your
 * own; your partner notices the number went up by three while she was away.
 * Exactly two rows exist however long you use it, and the replication rules
 * already in the app carry them without knowing they are special:
 *
 *   - Only the owner writes its own record, so last-write-wins never has a real
 *     conflict to resolve.
 *   - A count only ever goes up, so a stale copy loses on its timestamp and the
 *     newer one carries the whole backlog with it.
 *   - Delivery when both phones are open is the ordinary live-record broadcast;
 *     delivery after a gap is the ordinary manifest diff. There is no second
 *     code path for the offline case, which is why the offline case works.
 *
 * WHAT IS LOCAL, AND WHY
 * How many of your partner's bursts you have already been shown is this
 * device's business and nobody else's. Writing it into the synced record would
 * push a "seen" flag back across the wire, invent a write conflict on a record
 * with a single owner, and tell her when you opened the app. It lives in
 * localStorage instead, and losing it is harmless - see the first-run note on
 * readSeenCounts().
 */

import db from '../db/index.js';
import { generateUrlSafeNonce } from './crypto.js';

/** The table these live in. Declared in db/index.js version 3. */
export const LOVE_BURST_TABLE = 'loveBursts';

/** This device's tag, so it can recognise its own tally and skip it. */
const OWNER_KEY = 'sweetheart_burst_owner_v1';

/** `{ counts: { [recordId]: number } }` - how far we had counted last time. */
const SEEN_KEY = 'sweetheart_burst_seen_v1';

/** Above this we stop counting and just say "lots". */
export const MANY_BURSTS = 99;

function readStored(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStored(key, value) {
  try {
    localStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

let ownerIdCache = null;

/**
 * A stable random tag for this device, minted once.
 *
 * Deliberately NOT the peer id. That one is allowed to change - it is
 * regenerated on a broker collision - and a device whose tag moved would start
 * a second tally beside its own, which reads to the partner as a brand new
 * person arriving with a backlog.
 *
 * @returns {string}
 */
export function getBurstOwnerId() {
  if (ownerIdCache) return ownerIdCache;

  const stored = readStored(OWNER_KEY);
  if (typeof stored === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(stored)) {
    ownerIdCache = stored;
    return ownerIdCache;
  }

  const minted = generateUrlSafeNonce(12);
  writeStored(OWNER_KEY, minted);
  ownerIdCache = minted;
  return ownerIdCache;
}

/** @returns {string} The record id this device writes its own tally into. */
export function ownBurstRecordId() {
  return `burst-${getBurstOwnerId()}`;
}

/**
 * @returns {Object|null} The per-record counts we have already celebrated, or
 *   null when this device has never looked before.
 *
 * The null is load-bearing. A phone that has just restored a backup, or has had
 * its storage cleared, pulls down a tally that may already be in the hundreds.
 * Treating "no memory of counting" as "counted zero" would greet her with
 * "247 love bursts", which is not a nice surprise, it is a bug wearing one.
 * collectUnseenBursts() takes the null as a cue to start from today instead.
 */
function readSeenCounts() {
  try {
    const raw = readStored(SEEN_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    if (!parsed.counts || typeof parsed.counts !== 'object') return null;
    return parsed.counts;
  } catch {
    return null;
  }
}

function writeSeenCounts(counts) {
  writeStored(SEEN_KEY, JSON.stringify({ counts }));
}

/**
 * Records that these tallies have been shown, so they are not shown again.
 *
 * Takes the maximum rather than assigning, so that two callers racing on the
 * same records cannot walk the mark backwards and replay a burst.
 *
 * @param {Array<{ id: string, count: number }>} records
 */
export function markBurstsSeen(records) {
  const counts = readSeenCounts() || {};
  for (const record of records || []) {
    if (!record || typeof record.id !== 'string') continue;
    if (!Number.isFinite(record.count)) continue;
    const previous = Number.isFinite(counts[record.id]) ? counts[record.id] : 0;
    counts[record.id] = Math.max(previous, record.count);
  }
  writeSeenCounts(counts);
}

/** Monotonic write stamp, matching what every other write path in the app uses. */
async function defaultTimestamp() {
  try {
    const { default: peerSync } = await import('./peerSync.js');
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

/**
 * Adds one to this device's tally and writes it back sealed.
 *
 * Works whether or not the partner is reachable - that is the entire point.
 * Broadcasting the returned row is the caller's job, and is only an
 * optimisation: a row that never gets broadcast is picked up by the next
 * manifest diff exactly the same way.
 *
 * @param {CryptoKey} cryptoKey
 * @param {{ store?: Object, timestamp?: () => number|Promise<number> }} [options]
 * @returns {Promise<Object>} The sealed row, ready to broadcast.
 */
export async function sendLoveBurst(cryptoKey, options = {}) {
  if (!cryptoKey) throw new Error('sendLoveBurst: vault is locked');

  const store = options.store || db;
  const stamp = options.timestamp || defaultTimestamp;
  const id = ownBurstRecordId();

  let current = 0;
  try {
    const existing = await store.getDecrypted(LOVE_BURST_TABLE, id, cryptoKey);
    if (existing && Number.isFinite(existing.count) && existing.count > 0) {
      current = Math.floor(existing.count);
    }
  } catch {
    // Unreadable or absent. Starting again from one loses history we cannot
    // read anyway, and is far better than refusing to send.
    current = 0;
  }

  return await store.putEncrypted(
    LOVE_BURST_TABLE,
    {
      id,
      count: current + 1,
      lastSentAt: Date.now(),
      updatedAt: await stamp(),
    },
    cryptoKey
  );
}

/**
 * How many bursts have arrived that this device has not shown her yet.
 *
 * @param {CryptoKey} cryptoKey
 * @param {{ store?: Object }} [options]
 * @returns {Promise<{ total: number, lastSentAt: number,
 *   records: Array<{ id: string, count: number }> }>}
 */
export async function collectUnseenBursts(cryptoKey, options = {}) {
  const empty = { total: 0, lastSentAt: 0, records: [] };
  if (!cryptoKey) return empty;

  const store = options.store || db;
  const mine = ownBurstRecordId();

  let rows;
  try {
    rows = await store.listDecrypted(LOVE_BURST_TABLE, cryptoKey);
  } catch {
    return empty;
  }

  const theirs = (rows || []).filter(
    (row) =>
      row &&
      typeof row.id === 'string' &&
      row.id !== mine &&
      Number.isFinite(row.count) &&
      row.count > 0 &&
      // A record whose header or table binding was rewritten is not evidence of
      // anything. Everything else in the app refuses those; so does this.
      row._headerTampered !== true &&
      row._tableTampered !== true
  );

  const seen = readSeenCounts();

  // First look on this device: adopt where the tallies already stand, so the
  // count starts from today rather than from the beginning of the relationship.
  if (seen === null) {
    writeSeenCounts(
      Object.fromEntries(theirs.map((row) => [row.id, Math.floor(row.count)]))
    );
    return empty;
  }

  let total = 0;
  let lastSentAt = 0;
  const records = [];

  for (const row of theirs) {
    const before = Number.isFinite(seen[row.id]) ? seen[row.id] : 0;
    const delta = Math.floor(row.count) - before;
    records.push({ id: row.id, count: Math.floor(row.count) });
    if (delta <= 0) continue;
    total += delta;
    if (Number.isFinite(row.lastSentAt)) {
      lastSentAt = Math.max(lastSentAt, row.lastSentAt);
    }
  }

  return { total, lastSentAt, records };
}

/**
 * The sentence she reads. Kept here beside the counting so the two cannot drift.
 *
 * @param {number} total
 * @param {boolean} wasConnected - Whether the partner was reachable at the time,
 *   which is the difference between "just now" and "while you were away".
 * @returns {string}
 */
export function describeBursts(total, wasConnected) {
  if (total <= 0) return '';
  if (total === 1) {
    return wasConnected
      ? 'Your partner sent you a love burst! 💕'
      : 'Your partner sent you a love burst while you were away 💕';
  }
  const many = total > MANY_BURSTS ? `${MANY_BURSTS}+` : String(total);
  return wasConnected
    ? `Your partner sent you ${many} love bursts! 💕`
    : `Your partner sent you ${many} love bursts while you were away 💕`;
}

export default {
  LOVE_BURST_TABLE,
  getBurstOwnerId,
  ownBurstRecordId,
  sendLoveBurst,
  collectUnseenBursts,
  markBurstsSeen,
  describeBursts,
};
