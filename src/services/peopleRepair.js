/**
 * src/services/peopleRepair.js
 * "Swap us back": undoes the two of you trading places by accident.
 *
 * HOW THE PLACES GET TRADED
 * Each person is an id derived from the vault key, and the setup form files
 * "you" under the first one on every phone. A phone that shows that form before
 * the other phone's records arrive therefore writes its own holder's name and
 * device onto the FIRST person's id, and sync lets the newer record win. The
 * names then look swapped on the first phone, the natural fix there is "I'm
 * this one" on the other name, and from that moment each phone writes under
 * the other person's id - while everything written before stays filed under the
 * id it was written with. Names look right again; whose answers are whose does
 * not.
 *
 * WHAT THIS DOES, IN ONE GO
 *  1. Answers written since the trade move to the other person's rows
 *     (dailyQuestion.swapAnswersSince). Everything older is already where it
 *     belongs, because it was written before the ids changed hands.
 *  2. The two person records trade name, pronoun and devices, so each id is
 *     back with the human it started with.
 *  3. Answer rows filed under a device tag that no record lists any more go to
 *     the other person, but only when that tag answered across the same
 *     stretch of days as this phone's holder - which one person answering from
 *     one phone cannot do. A tag whose answers all come before this phone's
 *     could be this phone's own earlier install, so it is left alone.
 *  4. Their last-online times trade too, or each of you would show the other's.
 *  5. This phone follows its own device to the other id. The other phone
 *     follows on its next sync, through resolveIdentity, without anyone
 *     touching it.
 *
 * "SINCE" is when the two person records were last written, which is the trade
 * itself unless one of you was renamed afterwards.
 */

import db from '../db/index.js';
import { getDeviceId } from './deviceId.js';
import {
  PEOPLE_TABLE,
  listPeople,
  personRecordId,
  presenceRecordId,
  setLocalPersonId,
  toPresence,
} from './people.js';
import { answerSpans, swapAnswersSince } from './dailyQuestion.js';

/**
 * The moment the two of you traded places, as far as the records can tell.
 *
 * @param {Array<Object>} people - From listPeople.
 * @returns {number|null}
 */
export function tradedPlacesAt(people) {
  if (!Array.isArray(people) || people.length !== 2) return null;
  const at = Math.max(people[0].updatedAt || 0, people[1].updatedAt || 0);
  return at > 0 ? at : null;
}

/**
 * Device tags no record lists, whose answers sit inside the holder's own span.
 *
 * @param {Map<string, { first: string, last: string }>} spans - From answerSpans.
 * @param {{ holderIds: Array<string>, claimed: Set<string> }} args - Every id
 *   that is the holder's after the swap, and every id some record accounts for.
 * @returns {Array<string>}
 */
export function orphansAnsweringAlongside(spans, { holderIds, claimed }) {
  let first = null;
  let last = null;
  for (const id of holderIds) {
    const span = spans.get(id);
    if (!span) continue;
    if (first === null || span.first < first) first = span.first;
    if (last === null || span.last > last) last = span.last;
  }
  if (first === null) return [];

  const out = [];
  for (const [owner, span] of spans) {
    if (claimed.has(owner)) continue;
    // Strictly overlapping. Touching at one end is what a reinstall on the
    // same day looks like, and that is the case to leave alone.
    if (span.last > first && span.first < last) out.push(owner);
  }
  return out;
}

/**
 * @param {{ cryptoKey: CryptoKey, store?: Object, deviceId?: string,
 *   timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<{ people: Array<Object>, answers: Array<Object>,
 *   holderId: string|null, since: number, adopted: Array<string> }>}
 *   The sealed rows that changed, per table, ready to broadcast.
 */
export async function swapUsBack(args) {
  const { cryptoKey } = args || {};
  if (!cryptoKey) throw new Error('swapUsBack: vault is locked');

  const store = args.store || db;
  const deviceId = args.deviceId || getDeviceId();
  const stamp = async () =>
    typeof args.timestamp === 'function' ? await args.timestamp() : Date.now();

  const people = await listPeople({ cryptoKey, store });
  if (people.length !== 2) throw new Error('swapUsBack: needs exactly two people');
  const [a, b] = people;
  const since = tradedPlacesAt(people);
  if (since === null) throw new Error('swapUsBack: cannot tell when you traded places');

  // 1. Answers first, so the spans below see them where they now belong.
  const answers = await swapAnswersSince({
    cryptoKey,
    store,
    personA: a.personId,
    personB: b.personId,
    since,
    timestamp: args.timestamp,
  });

  // 2. Each id takes the other's devices. This phone's tag moves with them.
  const devices = { [a.personId]: [...b.deviceIds], [b.personId]: [...a.deviceIds] };
  const holderId = devices[a.personId].includes(deviceId)
    ? a.personId
    : devices[b.personId].includes(deviceId)
      ? b.personId
      : null;

  // 3. Orphaned answer tags that can only be the other person's.
  let adopted = [];
  if (holderId) {
    const partnerId = holderId === a.personId ? b.personId : a.personId;
    adopted = orphansAnsweringAlongside(await answerSpans({ cryptoKey, store }), {
      holderIds: [holderId, ...devices[holderId]],
      claimed: new Set([a.personId, b.personId, ...a.deviceIds, ...b.deviceIds]),
    });
    // Existing devices first: a record read back keeps only the first eight.
    devices[partnerId] = [...devices[partnerId], ...adopted];
  }

  const written = [];
  for (const [target, source] of [
    [a, b],
    [b, a],
  ]) {
    written.push(
      await store.putEncrypted(
        PEOPLE_TABLE,
        {
          id: personRecordId(target.personId),
          personId: target.personId,
          name: source.name,
          pronoun: source.pronoun,
          deviceIds: devices[target.personId],
          createdAt: target.createdAt || Date.now(),
          updatedAt: await stamp(),
        },
        cryptoKey
      )
    );
  }

  // 4. Last online, so neither of you shows the other's.
  const lastSeen = {};
  for (const person of people) {
    try {
      const row = toPresence(
        await store.getDecrypted(PEOPLE_TABLE, presenceRecordId(person.personId), cryptoKey)
      );
      if (row) lastSeen[person.personId] = row.lastActiveAt;
    } catch {
      // No presence yet. Nothing to carry over.
    }
  }
  for (const [target, source] of [
    [a, b],
    [b, a],
  ]) {
    if (!Number.isFinite(lastSeen[source.personId])) continue;
    written.push(
      await store.putEncrypted(
        PEOPLE_TABLE,
        {
          id: presenceRecordId(target.personId),
          personId: target.personId,
          lastActiveAt: lastSeen[source.personId],
          updatedAt: await stamp(),
        },
        cryptoKey
      )
    );
  }

  // 5. This phone goes where its device went.
  if (holderId) setLocalPersonId(holderId);

  return { people: written, answers, holderId, since, adopted };
}

export default { swapUsBack, tradedPlacesAt, orphansAnsweringAlongside };
