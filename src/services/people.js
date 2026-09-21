/**
 * src/services/people.js
 * Who the two of you are.
 *
 * WHY THIS EXISTS AT ALL
 * Until this file, the app had no concept of a person. It knew "this device"
 * (services/deviceId.js) and "not this device", and every feature built on top
 * of that inherited two problems it could not solve on its own.
 *
 *   1. Nothing could be said warmly. With no person there is no name and no
 *      pronoun, so every sentence about the other half of the couple had to
 *      read "your partner" or "they", forever, on both phones.
 *   2. Identity was hostage to localStorage. The device tag is the ONLY thing
 *      that said whose answer an answer was, and Safari discards localStorage
 *      after about seven idle days while Android Chrome evicts it under storage
 *      pressure. On the day that happened the daily-question archive emptied,
 *      the person's own past answers were re-attributed to their partner, and a
 *      second month bucket quietly opened beside the first.
 *
 * A person record fixes both, because it lives in the vault and syncs. The
 * device tag becomes a HINT about which person is holding this phone, not the
 * identity itself - and a hint can be lost and re-established with one tap.
 *
 * THERE ARE EXACTLY TWO PEOPLE
 * That is a real assumption and it is load-bearing: "mine" is decided by
 * matching, and everything not mine is theirs. It is also the whole premise of
 * the app, so the alternative is not a more general model, it is a different
 * product. Nothing here corrupts if a third record ever appears - the extra
 * person simply reads as the partner - but nothing here is designed for it.
 *
 * WHY A PERSON OWNS A LIST OF DEVICE TAGS
 * Two reasons, and the second is the one that matters.
 *   - Migration. Records written before this file carry a device tag in
 *     `ownerId`. Keeping the tags on the person record means those rows still
 *     resolve to the right human without rewriting a single one.
 *   - One person, two devices. A phone and a laptop are two tags and one
 *     person. Without the list they read as two different people, and the
 *     laptop shows its owner's own answers as their partner's.
 *
 * NAMES ARE NOT SECRET, BUT THEY ARE PRIVATE
 * A person record is an ordinary sealed envelope in a synced table, so a name
 * never leaves the device in the clear and never appears in a sync manifest.
 * It is not a login, it carries no authority, and claiming one proves nothing -
 * anyone holding the passphrase is already inside. It exists to make the app
 * speak like a person rather than a form.
 */

import db from '../db/index.js';
import { getDeviceId } from './deviceId.js';

/** The synced table these live in. */
export const PEOPLE_TABLE = 'people';

/**
 * Domain separation for the slot derivation below. One label per slot, so the
 * two ids in a vault are unrelated to each other and to every other use of the
 * key.
 */
const SLOT_CONTEXTS = ['our-space/people/slot/a/v1', 'our-space/people/slot/b/v1'];

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

/** Which of the two people is holding THIS device. A hint, not an identity. */
const STORAGE_KEY = 'sweetheart_person_id_v1';

/** Long enough for a real name or a pet name, short enough to bound a record. */
export const MAX_NAME_LENGTH = 40;

/**
 * Cap on how many device tags one person accumulates.
 *
 * Not a security boundary - it is a bound on a field that only ever grows. Two
 * people with a phone and a laptop each will never come close; a person who
 * reinstalls their browser every week would, and the oldest tags are the ones
 * least likely to still matter.
 */
const MAX_DEVICE_TAGS = 8;

const TAG_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * Grammar, so no screen has to hardcode a pronoun.
 *
 * `has` and `is` are here because they are where neutral copy actually breaks:
 * "they has answered" is the bug every they/them string in an app eventually
 * ships with. Asking this table rather than writing the verb inline means a
 * sentence cannot be correct for one person and wrong for the other.
 */
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

/** The pronoun sets a person may choose between. */
export const PRONOUNS = Object.freeze(Object.keys(PRONOUN_SETS));

/** The default, and the fallback for anything unrecognised. */
export const DEFAULT_PRONOUN = 'they';

/* ------------------------------------------------------------------ slots */

/**
 * The two person ids for this vault, derived from the vault key.
 *
 * WHY DERIVED AND NOT RANDOM
 * Because both phones can reach the setup screen before they have ever synced,
 * and random ids would mean each one minting its own pair. The vault would end
 * up holding FOUR people, two of them phantoms, and nothing in the app could
 * work out which two were real.
 *
 * Deriving them means both devices independently arrive at the same two ids
 * without having spoken. If both do set up, the two writes collide on the same
 * two records and last-write-wins settles the names - which is a wrong name
 * that takes one edit to fix, rather than a structurally broken vault. This is
 * the same trick the daily question uses to agree on an order with no server:
 * the key is the only thing both sides already share.
 *
 * The vault key is non-extractable, so it cannot be hashed directly. It can
 * still encrypt, and AES-GCM over a fixed plaintext with a fixed IV is
 * deterministic. The fixed IV is safe here for the same reason it is there:
 * one use, one constant plaintext, and the output is a name rather than a
 * secret.
 *
 * @param {CryptoKey} cryptoKey
 * @returns {Promise<[string, string]>}
 */
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
    // 12 bytes of the digest, hex-encoded, gives 24 characters - comfortably
    // inside TAG_PATTERN and readable in a debugger without being a secret.
    out.push(
      Array.from(digest.slice(0, 12))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')
    );
  }

  return out;
}

/* ------------------------------------------------------------ record shape */

/** `person-<id>`. The id is derived from the vault key, and never reused. */
export function personRecordId(personId) {
  return `person-${personId}`;
}

/** @returns {string} A bounded, trimmed display name, or '' when there is none. */
export function sanitizeName(value) {
  if (typeof value !== 'string') return '';
  // Collapse whitespace first: a name pasted out of a chat app arrives with
  // newlines in it, and a newline inside a name breaks every line of copy it
  // is interpolated into.
  return value.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH).trim();
}

/** @returns {string} One of PRONOUNS, defaulting rather than throwing. */
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

/**
 * Normalises one decrypted row into a person, or null if it is not one.
 *
 * Rows arrive here from sync, which means they arrive from a device that could
 * in principle be sending anything. A name is interpolated into copy and a
 * pronoun picks a verb, so both are clamped rather than trusted.
 */
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
    createdAt: Number.isFinite(row.createdAt) ? row.createdAt : 0,
    updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0,
  };
}

/* ---------------------------------------------------------------- grammar */

/**
 * What to call this person on screen.
 *
 * The fallback is deliberately a word that works mid-sentence, because every
 * caller interpolates it: "Waiting on your partner" reads; "Waiting on " does
 * not.
 */
export function nameOf(person, fallback = 'your partner') {
  const name = person && sanitizeName(person.name);
  return name || fallback;
}

/** The pronoun set for a person, always defined even for a missing person. */
export function grammarOf(person) {
  return PRONOUN_SETS[sanitizePronoun(person && person.pronoun)];
}

/**
 * "Riya's" / "your partner's". Handles a name that already ends in s, which is
 * common enough (Iris, Jonas) to be worth not getting wrong.
 */
export function possessiveOf(person, fallback = 'your partner') {
  const name = nameOf(person, fallback);
  return /s$/i.test(name) ? `${name}'` : `${name}'s`;
}

/* -------------------------------------------------------- the local hint */

let cachedPersonId = null;

function readStored() {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

/** @returns {string|null} The person this device last claimed to be. */
export function getLocalPersonId() {
  if (cachedPersonId) return cachedPersonId;
  const stored = readStored();
  if (typeof stored === 'string' && TAG_PATTERN.test(stored)) {
    cachedPersonId = stored;
    return cachedPersonId;
  }
  return null;
}

/** Remembers which person is holding this device. Tolerates blocked storage. */
export function setLocalPersonId(personId) {
  if (typeof personId !== 'string' || !TAG_PATTERN.test(personId)) return false;
  // Cached even when the write fails, so a device with storage blocked still
  // holds ONE answer for the life of the page rather than asking again on every
  // screen that needs to know.
  cachedPersonId = personId;
  try {
    localStorage.setItem(STORAGE_KEY, personId);
    return true;
  } catch {
    return false;
  }
}

/** Forgets the hint. Used when this device is handed to the other person. */
export function clearLocalPersonId() {
  cachedPersonId = null;
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* Nothing to do: the cache above is already cleared. */
  }
}

/* ------------------------------------------------------------------ reads */

/**
 * Everyone in the vault, oldest first.
 *
 * Oldest first matters: it is the order the two of you were entered in, so a
 * "which one are you?" prompt lists you the same way on both phones rather
 * than in whatever order IndexedDB felt like.
 *
 * @param {{ cryptoKey: CryptoKey, store?: Object }} args
 * @returns {Promise<Array<Object>>}
 */
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
  for (const row of rows || []) {
    const person = toPerson(row);
    if (person) people.push(person);
  }

  people.sort((a, b) => a.createdAt - b.createdAt || (a.personId < b.personId ? -1 : 1));
  return people;
}

/**
 * Every id that counts as "written by this person".
 *
 * The person id plus every device tag they have ever claimed from. This is the
 * bridge that lets records written before people existed keep belonging to the
 * right human without being rewritten.
 *
 * @param {Object|null} person
 * @returns {Set<string>}
 */
export function ownerIdsFor(person) {
  const ids = new Set();
  if (!person) return ids;
  if (typeof person.personId === 'string') ids.add(person.personId);
  for (const tag of person.deviceIds || []) ids.add(tag);
  return ids;
}

/**
 * Who is holding this device, who the other one is, and whether we know yet.
 *
 * `status` is the whole point of this function - it is what a screen switches
 * on, so no screen has to work out for itself what a half-set-up vault means:
 *
 *   'empty'     Nobody has been entered. Ask for both names.
 *   'unclaimed' People exist, but this device does not know which one it is.
 *               Ask "which one are you?" - this is the state a wiped
 *               localStorage lands in, and it costs one tap to leave.
 *   'ready'     We know. `me` and `partner` are both usable.
 *
 * @param {{ cryptoKey: CryptoKey, store?: Object, deviceId?: string }} args
 * @returns {Promise<{ status: string, people: Array, me: Object|null, partner: Object|null }>}
 */
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

  // The hint is gone (or points at a person who was removed), but this device's
  // tag may still be listed on a person record - which it will be, on every
  // device that ever claimed one. That is the localStorage-eviction recovery
  // path, and it costs the user nothing because it never reaches them.
  if (!me) {
    me = people.find((p) => (p.deviceIds || []).includes(deviceId)) || null;
    if (me) setLocalPersonId(me.personId);
  }

  if (!me) {
    return { status: 'unclaimed', people, me: null, partner: null };
  }

  // Exactly two people, so the partner is simply the other one. With more than
  // two this takes the first that is not us, which is wrong but harmless - and
  // a vault in that state is already outside what this app is.
  const partner = people.find((p) => p.personId !== me.personId) || null;
  return { status: 'ready', people, me, partner };
}

/* ----------------------------------------------------------------- writes */

async function stampFrom(args) {
  const fn = args && args.timestamp;
  if (typeof fn !== 'function') return Date.now();
  return await fn();
}

/**
 * Writes a person record, merging rather than replacing.
 *
 * Merging is what keeps two devices belonging to the same human from knocking
 * each other's tags off the record: each one reads, unions its own tag in, and
 * writes. Last-write-wins still applies to the NAME, which is correct - a name
 * is a single value and the most recent edit should be the one that stands.
 *
 * @param {{ cryptoKey: CryptoKey, personId: string, name?: string, pronoun?: string,
 *   addDeviceId?: string, store?: Object, timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<Object>} The sealed row, ready to broadcast.
 */
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

/**
 * Creates both halves of the couple in one go, and claims one of them for this
 * device.
 *
 * Both at once on purpose. A vault with one person in it is a state every
 * screen would have to handle and nothing would ever produce deliberately -
 * whoever sets the app up knows both names, because they are setting it up FOR
 * the two of them.
 *
 * @param {{ cryptoKey: CryptoKey, mine: {name: string, pronoun?: string},
 *   theirs: {name: string, pronoun?: string}, store?: Object, deviceId?: string,
 *   timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<{ me: Object, partner: Object, rows: Array<Object> }>}
 */
export async function createCouple(args) {
  const { cryptoKey, mine, theirs } = args || {};
  if (!cryptoKey) throw new Error('createCouple: vault is locked');

  const store = args.store || db;
  const deviceId = args.deviceId || getDeviceId();

  // Derived, not minted: see derivePersonSlots. Whichever device sets up first
  // takes slot A, and a second device that set up before syncing lands on the
  // same two records rather than inventing a second pair.
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

  setLocalPersonId(minePersonId);

  const { me, partner } = await resolveIdentity({ cryptoKey, store, deviceId });
  return { me, partner, rows: [mineRow, theirsRow] };
}

/**
 * Takes this device's tag OFF every person who is not `keepPersonId`.
 *
 * A device belongs to exactly one person at a time, and this is what enforces
 * it. Without it, tapping the wrong name once and then correcting it leaves the
 * tag on both records forever - and since a device tag is how rows written
 * before people existed are attributed, BOTH people would then answer to that
 * tag and the same answers would show up as written by each of them.
 *
 * @returns {Promise<Array<Object>>} The sealed rows that changed.
 */
async function releaseDeviceFromOthers(args) {
  const { cryptoKey, store, deviceId, keepPersonId } = args;
  const people = await listPeople({ cryptoKey, store });
  const rows = [];

  for (const person of people) {
    if (person.personId === keepPersonId) continue;
    if (!(person.deviceIds || []).includes(deviceId)) continue;

    const remaining = person.deviceIds.filter((tag) => tag !== deviceId);
    // savePerson merges device tags rather than replacing them, which is
    // exactly what we do NOT want here, so this write goes direct.
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

/**
 * Says "this device is that person", and writes the device tag onto the record
 * so the claim survives losing localStorage.
 *
 * Claiming is EXCLUSIVE: the tag comes off whoever else was holding it first.
 * That is what makes tapping the wrong name a mistake you can simply correct.
 *
 * @param {{ cryptoKey: CryptoKey, personId: string, store?: Object, deviceId?: string,
 *   timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<Array<Object>>} The sealed rows, ready to broadcast.
 */
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

  setLocalPersonId(personId);
  return [...released, row];
}

/**
 * Puts this device's tag back on our own person record if a sync dropped it.
 *
 * It can be dropped, and this is not theoretical. Person records merge by
 * last-write-wins on the whole record, so if two devices belonging to the same
 * human each add their tag while apart, the older write loses its tag when the
 * newer one lands. Re-adding on open is self-healing and costs one read in the
 * overwhelmingly common case where there is nothing to do.
 *
 * @param {{ cryptoKey: CryptoKey, store?: Object, deviceId?: string,
 *   timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<Object|null>} The sealed row if one was written, else null.
 */
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
  sanitizeName,
  sanitizePronoun,
  toPerson,
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
  createCouple,
  claimPerson,
  ensureDeviceClaimed,
};
