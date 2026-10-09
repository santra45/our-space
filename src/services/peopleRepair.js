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
import { ANSWER_TABLE, answerSpans, planAnswerSwap } from './dailyQuestion.js';

export function tradedPlacesAt(people) {
  if (!Array.isArray(people) || people.length !== 2) return null;
  const at = Math.max(people[0].updatedAt || 0, people[1].updatedAt || 0);
  return at > 0 ? at : null;
}

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
    if (span.last > first && span.first < last) out.push(owner);
  }
  return out;
}

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

  const answerPlan = await planAnswerSwap({
    cryptoKey,
    store,
    personA: a.personId,
    personB: b.personId,
    since,
    timestamp: args.timestamp,
  });

  const devices = { [a.personId]: [...b.deviceIds], [b.personId]: [...a.deviceIds] };
  const holderId = devices[a.personId].includes(deviceId)
    ? a.personId
    : devices[b.personId].includes(deviceId)
      ? b.personId
      : null;

  let adopted = [];
  if (holderId) {
    const partnerId = holderId === a.personId ? b.personId : a.personId;
    adopted = orphansAnsweringAlongside(await answerSpans({ rows: answerPlan.after }), {
      holderIds: [holderId, ...devices[holderId]],
      claimed: new Set([a.personId, b.personId, ...a.deviceIds, ...b.deviceIds]),
    });
    devices[partnerId] = [...devices[partnerId], ...adopted];
  }

  const entries = answerPlan.rows.map((fields) => ({ table: ANSWER_TABLE, fields }));

  for (const [target, source] of [
    [a, b],
    [b, a],
  ]) {
    entries.push({
      table: PEOPLE_TABLE,
      fields: {
        id: personRecordId(target.personId),
        personId: target.personId,
        name: source.name,
        pronoun: source.pronoun,
        deviceIds: devices[target.personId],
        createdAt: target.createdAt || Date.now(),
        updatedAt: await stamp(),
      },
    });
  }

  const lastSeen = {};
  for (const person of people) {
    try {
      const row = toPresence(
        await store.getDecrypted(PEOPLE_TABLE, presenceRecordId(person.personId), cryptoKey)
      );
      if (row) lastSeen[person.personId] = row.lastActiveAt;
    } catch {
    }
  }
  for (const [target, source] of [
    [a, b],
    [b, a],
  ]) {
    if (!Number.isFinite(lastSeen[source.personId])) continue;
    entries.push({
      table: PEOPLE_TABLE,
      fields: {
        id: presenceRecordId(target.personId),
        personId: target.personId,
        lastActiveAt: lastSeen[source.personId],
        updatedAt: await stamp(),
      },
    });
  }

  const sealed = await store.putEncryptedMany(entries, cryptoKey);

  if (holderId) setLocalPersonId(holderId);

  return {
    people: sealed.filter((entry) => entry.table === PEOPLE_TABLE).map((entry) => entry.row),
    answers: sealed.filter((entry) => entry.table === ANSWER_TABLE).map((entry) => entry.row),
    holderId,
    since,
    adopted,
  };
}

export default { swapUsBack, tradedPlacesAt, orphansAnsweringAlongside };
