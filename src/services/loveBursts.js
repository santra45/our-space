import db from '../db/index.js';
import { getDeviceId } from './deviceId.js';

export const LOVE_BURST_TABLE = 'loveBursts';


const SEEN_KEY = 'sweetheart_burst_seen_v1';

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

export function getBurstOwnerId() {
  return getDeviceId();
}

export function ownBurstRecordId() {
  return `burst-${getBurstOwnerId()}`;
}

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

async function defaultTimestamp() {
  try {
    const { default: peerSync } = await import('./peerSync.js');
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

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
      row._headerTampered !== true &&
      row._tableTampered !== true
  );

  const seen = readSeenCounts();

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

export function describeBursts(total, wasConnected, name) {
  if (total <= 0) return '';

  const who = typeof name === 'string' && name.trim() ? name.trim() : 'Your partner';
  const many = total > MANY_BURSTS ? `${MANY_BURSTS}+` : String(total);
  const what = total === 1 ? 'a love burst' : `${many} love bursts`;

  return wasConnected
    ? `${who} sent you ${what}! 💕`
    : `${who} sent you ${what} while you were away 💕`;
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
