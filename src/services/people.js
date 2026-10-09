import db from '../db/index.js';
import { getDeviceId } from './deviceId.js';

export const PEOPLE_TABLE = 'people';

const SLOT_CONTEXTS = ['our-space/people/slot/a/v1', 'our-space/people/slot/b/v1'];

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

const STORAGE_KEY = 'sweetheart_person_id_v1';

export const MAX_NAME_LENGTH = 40;

const MAX_DEVICE_TAGS = 8;

const TAG_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

const PRONOUN_SETS = Object.freeze({
  she: { subject: 'she', object: 'her', possessive: 'her', independent: 'hers', has: 'has', is: 'is' },
  he: { subject: 'he', object: 'him', possessive: 'his', independent: 'his', has: 'has', is: 'is' },
  they: {
    subject: 'they',
    object: 'them',
    possessive: 'their',
    independent: 'theirs',
    has: 'have',
    is: 'are',
  },
});

export const PRONOUNS = Object.freeze(Object.keys(PRONOUN_SETS));

export const DEFAULT_PRONOUN = 'they';

export async function derivePersonSlots(cryptoKey) {
  if (!cryptoKey) throw new Error('derivePersonSlots: vault is locked');
  const encoder = new TextEncoder();
  const out = [];

  for (const context of SLOT_CONTEXTS) {
    const sealed = await webCrypto().subtle.encrypt(
      { name: 'AES-GCM', iv: new Uint8Array(12) },
      cryptoKey,
      encoder.encode(context)
    );
    const digest = new Uint8Array(await webCrypto().subtle.digest('SHA-256', sealed));
    out.push(
      Array.from(digest.slice(0, 12))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')
    );
  }

  return out;
}

export function personRecordId(personId) {
  return `person-${personId}`;
}

export function presenceRecordId(personId) {
  return `presence-${personId}`;
}

export function sanitizeName(value) {
  if (typeof value !== 'string') return '';
  return value.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH).trim();
}

export function sanitizePronoun(value) {
  return typeof value === 'string' && PRONOUN_SETS[value] ? value : DEFAULT_PRONOUN;
}

function sanitizeDeviceIds(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const tag of value) {
    if (typeof tag !== 'string' || !TAG_PATTERN.test(tag)) continue;
    if (out.includes(tag)) continue;
    out.push(tag);
    if (out.length >= MAX_DEVICE_TAGS) break;
  }
  return out;
}

export function toPerson(row) {
  if (!row || typeof row !== 'object') return null;
  if (row._headerTampered === true || row._tableTampered === true) return null;
  if (typeof row.personId !== 'string' || !TAG_PATTERN.test(row.personId)) return null;
  if (row.id !== personRecordId(row.personId)) return null;

  return {
    personId: row.personId,
    name: sanitizeName(row.name),
    pronoun: sanitizePronoun(row.pronoun),
    deviceIds: sanitizeDeviceIds(row.deviceIds),
    lastActiveAt: Number.isFinite(row.lastActiveAt) ? row.lastActiveAt : null,
    createdAt: Number.isFinite(row.createdAt) ? row.createdAt : 0,
    updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0,
  };
}

export function toPresence(row) {
  if (!row || typeof row !== 'object') return null;
  if (row._headerTampered === true || row._tableTampered === true) return null;
  if (typeof row.personId !== 'string' || !TAG_PATTERN.test(row.personId)) return null;
  if (row.id !== presenceRecordId(row.personId)) return null;
  if (!Number.isFinite(row.lastActiveAt)) return null;
  return { personId: row.personId, lastActiveAt: row.lastActiveAt };
}

export function nameOf(person, fallback = 'your partner') {
  const name = person && sanitizeName(person.name);
  return name || fallback;
}

export function grammarOf(person) {
  return PRONOUN_SETS[sanitizePronoun(person && person.pronoun)];
}

export function possessiveOf(person, fallback = 'your partner') {
  const name = nameOf(person, fallback);
  return /s$/i.test(name) ? `${name}'` : `${name}'s`;
}

let cachedPersonId = null;

function readStored() {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function getLocalPersonId() {
  if (cachedPersonId) return cachedPersonId;
  const stored = readStored();
  if (typeof stored === 'string' && TAG_PATTERN.test(stored)) {
    cachedPersonId = stored;
    return cachedPersonId;
  }
  return null;
}

export function setLocalPersonId(personId) {
  if (typeof personId !== 'string' || !TAG_PATTERN.test(personId)) return false;
  cachedPersonId = personId;
  try {
    localStorage.setItem(STORAGE_KEY, personId);
    return true;
  } catch {
    return false;
  }
}

export function clearLocalPersonId() {
  cachedPersonId = null;
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
  }
}

export async function listPeople(args) {
  const { cryptoKey } = args || {};
  if (!cryptoKey) return [];
  const store = (args && args.store) || db;

  let rows;
  try {
    rows = await store.listDecrypted(PEOPLE_TABLE, cryptoKey);
  } catch {
    return [];
  }

  const people = [];
  const presence = new Map();
  for (const row of rows || []) {
    const person = toPerson(row);
    if (person) {
      people.push(person);
      continue;
    }
    const seen = toPresence(row);
    if (seen) presence.set(seen.personId, seen.lastActiveAt);
  }

  for (const person of people) {
    const latest = Math.max(presence.get(person.personId) || 0, person.lastActiveAt || 0);
    person.lastActiveAt = latest || null;
  }

  people.sort((a, b) => a.createdAt - b.createdAt || (a.personId < b.personId ? -1 : 1));
  return people;
}

export function ownerIdsFor(person) {
  const ids = new Set();
  if (!person) return ids;
  if (typeof person.personId === 'string') ids.add(person.personId);
  for (const tag of person.deviceIds || []) ids.add(tag);
  return ids;
}

export async function resolveIdentity(args) {
  const { cryptoKey } = args || {};
  const store = (args && args.store) || db;
  const deviceId = (args && args.deviceId) || getDeviceId();

  const people = await listPeople({ cryptoKey, store });
  if (people.length === 0) {
    return { status: 'empty', people, me: null, partner: null };
  }

  const hinted = getLocalPersonId();
  let me = hinted ? people.find((p) => p.personId === hinted) || null : null;
  const listing = people.filter((p) => (p.deviceIds || []).includes(deviceId));

  if (!me) {
    me = listing[0] || null;
    if (me) setLocalPersonId(me.personId);
  }

  if (
    me &&
    listing.length === 1 &&
    listing[0].personId !== me.personId &&
    (me.deviceIds || []).length > 0 &&
    !(me.deviceIds || []).includes(deviceId)
  ) {
    me = listing[0];
    setLocalPersonId(me.personId);
  }

  if (!me) {
    return { status: 'unclaimed', people, me: null, partner: null };
  }

  const partner = people.find((p) => p.personId !== me.personId) || null;
  return { status: 'ready', people, me, partner };
}

async function stampFrom(args) {
  const fn = args && args.timestamp;
  if (typeof fn !== 'function') return Date.now();
  return await fn();
}

export async function savePerson(args) {
  const { cryptoKey, personId } = args || {};
  if (!cryptoKey) throw new Error('savePerson: vault is locked');
  if (typeof personId !== 'string' || !TAG_PATTERN.test(personId)) {
    throw new Error('savePerson: bad person id');
  }

  const store = args.store || db;
  const id = personRecordId(personId);

  let existing = null;
  try {
    existing = toPerson(await store.getDecrypted(PEOPLE_TABLE, id, cryptoKey));
  } catch {
    existing = null;
  }

  const deviceIds = sanitizeDeviceIds([
    ...(existing ? existing.deviceIds : []),
    ...(args.addDeviceId ? [args.addDeviceId] : []),
  ]);

  const name =
    args.name !== undefined ? sanitizeName(args.name) : existing ? existing.name : '';
  const pronoun =
    args.pronoun !== undefined
      ? sanitizePronoun(args.pronoun)
      : existing
        ? existing.pronoun
        : DEFAULT_PRONOUN;

  return await store.putEncrypted(
    PEOPLE_TABLE,
    {
      id,
      personId,
      name,
      pronoun,
      deviceIds,
      createdAt: existing && existing.createdAt ? existing.createdAt : Date.now(),
      updatedAt: await stampFrom(args),
    },
    cryptoKey
  );
}

async function writePresence(args) {
  const { cryptoKey, store, personId } = args;
  return await store.putEncrypted(
    PEOPLE_TABLE,
    {
      id: presenceRecordId(personId),
      personId,
      lastActiveAt: Date.now(),
      updatedAt: await stampFrom(args),
    },
    cryptoKey
  );
}

export async function touchPersonActive(args) {
  const { cryptoKey, personId } = args || {};
  if (!cryptoKey || typeof personId !== 'string' || !TAG_PATTERN.test(personId)) return null;
  const store = args.store || db;
  const minIntervalMs = args.minIntervalMs !== undefined ? args.minIntervalMs : 5 * 60 * 1000;

  let existing = null;
  try {
    existing = toPresence(
      await store.getDecrypted(PEOPLE_TABLE, presenceRecordId(personId), cryptoKey)
    );
  } catch {
    existing = null;
  }

  if (existing && Date.now() - existing.lastActiveAt < minIntervalMs) {
    return null;
  }

  return await writePresence({ cryptoKey, store, personId, timestamp: args.timestamp });
}

export async function createCouple(args) {
  const { cryptoKey, mine, theirs } = args || {};
  if (!cryptoKey) throw new Error('createCouple: vault is locked');

  const store = args.store || db;
  const deviceId = args.deviceId || getDeviceId();

  const [minePersonId, theirsPersonId] = await derivePersonSlots(cryptoKey);

  const mineRow = await savePerson({
    cryptoKey,
    store,
    personId: minePersonId,
    name: (mine && mine.name) || '',
    pronoun: mine && mine.pronoun,
    addDeviceId: deviceId,
    timestamp: args.timestamp,
  });

  const theirsRow = await savePerson({
    cryptoKey,
    store,
    personId: theirsPersonId,
    name: (theirs && theirs.name) || '',
    pronoun: theirs && theirs.pronoun,
    timestamp: args.timestamp,
  });

  const presenceRow = await writePresence({
    cryptoKey,
    store,
    personId: minePersonId,
    timestamp: args.timestamp,
  });

  setLocalPersonId(minePersonId);

  const { me, partner } = await resolveIdentity({ cryptoKey, store, deviceId });
  return { me, partner, rows: [mineRow, theirsRow, presenceRow] };
}

async function releaseDeviceFromOthers(args) {
  const { cryptoKey, store, deviceId, keepPersonId } = args;
  const people = await listPeople({ cryptoKey, store });
  const rows = [];

  for (const person of people) {
    if (person.personId === keepPersonId) continue;
    if (!(person.deviceIds || []).includes(deviceId)) continue;

    const remaining = person.deviceIds.filter((tag) => tag !== deviceId);
    rows.push(
      await store.putEncrypted(
        PEOPLE_TABLE,
        {
          id: personRecordId(person.personId),
          personId: person.personId,
          name: person.name,
          pronoun: person.pronoun,
          deviceIds: remaining,
          createdAt: person.createdAt || Date.now(),
          updatedAt: await stampFrom(args),
        },
        cryptoKey
      )
    );
  }

  return rows;
}

export async function claimPerson(args) {
  const { cryptoKey, personId } = args || {};
  const store = (args && args.store) || db;
  const deviceId = (args && args.deviceId) || getDeviceId();
  const timestamp = args && args.timestamp;

  const released = await releaseDeviceFromOthers({
    cryptoKey,
    store,
    deviceId,
    keepPersonId: personId,
    timestamp,
  });

  const row = await savePerson({
    cryptoKey,
    store,
    personId,
    addDeviceId: deviceId,
    timestamp,
  });

  const presenceRow = await writePresence({ cryptoKey, store, personId, timestamp });

  setLocalPersonId(personId);
  return [...released, row, presenceRow];
}

export async function ensureDeviceClaimed(args) {
  const { cryptoKey } = args || {};
  if (!cryptoKey) return null;

  const store = args.store || db;
  const deviceId = args.deviceId || getDeviceId();

  const { status, me } = await resolveIdentity({ cryptoKey, store, deviceId });
  if (status !== 'ready' || !me) return null;
  if ((me.deviceIds || []).includes(deviceId)) return null;

  return await savePerson({
    cryptoKey,
    store,
    personId: me.personId,
    addDeviceId: deviceId,
    timestamp: args.timestamp,
  });
}

export default {
  PEOPLE_TABLE,
  PRONOUNS,
  DEFAULT_PRONOUN,
  MAX_NAME_LENGTH,
  derivePersonSlots,
  personRecordId,
  presenceRecordId,
  sanitizeName,
  sanitizePronoun,
  toPerson,
  toPresence,
  nameOf,
  grammarOf,
  possessiveOf,
  getLocalPersonId,
  setLocalPersonId,
  clearLocalPersonId,
  listPeople,
  ownerIdsFor,
  resolveIdentity,
  savePerson,
  touchPersonActive,
  createCouple,
  claimPerson,
  ensureDeviceClaimed,
};
