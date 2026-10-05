/**
 * src/services/dailyQuestion.js
 * One question a day, the same one on both phones, with neither answer visible
 * until both are written.
 *
 * HOW BOTH PHONES AGREE WITHOUT ASKING EACH OTHER
 * The order is a shuffle of the question bank seeded by the vault key, and the
 * day picks a position in it. Both devices hold the same key, so both compute
 * the same order and land on the same question - with no server, no message,
 * and no need to have spoken that day at all. Two people who have not connected
 * in a week still get the same question every morning.
 *
 * WHY A SHUFFLE AND NOT `hash(day) % N`
 * Because independent draws collide. With 180 questions and a modulo, a year
 * lands on one already answered on roughly a third of days, sometimes twice in
 * the same month - which reads as broken and quietly kills the habit. Walking a
 * permutation guarantees every question appears once before any comes back.
 *
 * BATCHES ARE SHUFFLED SEPARATELY, ON PURPOSE
 * Shuffling the whole bank would mean adding questions later reshuffles
 * everything, moving the day pointer onto questions already answered. Each
 * batch is shuffled within itself and appended, so batch one's order is
 * untouched forever no matter how many batches follow it.
 *
 * DAYS ARE UTC
 * "Today" has to mean the same thing on both phones or the two answers are to
 * different questions and the pairing is meaningless. UTC is the only boundary
 * that needs no configuration and no assumption about where either person is.
 * In India that turns the question over at about half past five in the morning,
 * which is a better moment than midnight anyway - you wake up to a new one.
 *
 * ONE HONEST LIMIT ON THE BLIND REVEAL
 * Both phones share one key, so their answer arrives on your device readable.
 * The app will not show it to you until you have written yours, and that gate
 * is the whole feature - but it is a promise, not a lock, exactly like the
 * time-locked letters. Someone determined and technical could read around it.
 * That is not the failure mode this is built for.
 *
 * WHOSE ANSWER IS WHOSE
 * Decided in exactly one place, by ownerOf() below, and a person is matched
 * against a SET of ids rather than one - see services/people.js. A person is
 * not a device: they have a phone and a laptop, and before people existed they
 * had only a device tag that localStorage could lose. Every row any of those
 * wrote is theirs, and folding rather than picking is what stops a month
 * splitting in half the day an id changes.
 */

import db from '../db/index.js';
import { ALL_QUESTIONS, QUESTION_BATCHES, findQuestion } from '../data/dailyQuestions.js';

export const ANSWER_TABLE = 'dailyAnswers';

/** Domain separation, so this use of the vault key is its own. */
const SHUFFLE_CONTEXT = 'our-space/daily-question/order/v1';

/** Cap on a single answer. Long enough for a real one, short enough to bound a month. */
export const MAX_ANSWER_LENGTH = 2000;

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

/* ------------------------------------------------------------------- days */

/**
 * The UTC day, as `YYYY-MM-DD`.
 * @param {Date|number} [when]
 * @returns {string}
 */
export function dayKey(when) {
  const date = when instanceof Date ? when : new Date(when === undefined ? Date.now() : when);
  return date.toISOString().slice(0, 10);
}

/** `YYYY-MM`, which is the bucket a whole month of answers lands in. */
export function monthKey(dayKeyString) {
  return String(dayKeyString).slice(0, 7);
}

/** Whole UTC days since the epoch. The position in the shuffled order. */
export function dayIndex(when) {
  const date = when instanceof Date ? when : new Date(when === undefined ? Date.now() : when);
  return Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) / 86400000);
}

/* ---------------------------------------------------------------- ordering */

/**
 * Deterministic key material for the shuffle.
 *
 * The vault key is non-extractable, so it cannot be fed to a hash directly.
 * It can still ENCRYPT, and AES-GCM over a fixed plaintext with a fixed IV is
 * deterministic - the same key gives the same bytes on both phones, and a
 * different key gives unrelated ones. The fixed IV is safe here precisely
 * because it is used once, for one constant plaintext, and the output is a
 * seed rather than a secret.
 *
 * @param {CryptoKey} cryptoKey
 * @returns {Promise<Uint8Array>}
 */
async function deriveSeed(cryptoKey) {
  const encoder = new TextEncoder();
  const sealed = await webCrypto().subtle.encrypt(
    { name: 'AES-GCM', iv: new Uint8Array(12) },
    cryptoKey,
    encoder.encode(SHUFFLE_CONTEXT)
  );
  return new Uint8Array(await webCrypto().subtle.digest('SHA-256', sealed));
}

/** A counter-mode stream of 32-bit values from one seed. Deterministic anywhere. */
async function makeRandomStream(seed) {
  const values = [];
  let counter = 0;

  return async function next() {
    if (values.length === 0) {
      const block = new Uint8Array(seed.length + 4);
      block.set(seed, 0);
      new DataView(block.buffer).setUint32(seed.length, counter++, false);
      const digest = new Uint8Array(await webCrypto().subtle.digest('SHA-256', block));
      for (let i = 0; i < digest.length; i += 4) {
        values.push(new DataView(digest.buffer, i, 4).getUint32(0, false));
      }
    }
    return values.pop();
  };
}

/**
 * Fisher-Yates, driven by the seeded stream. Modulo bias is irrelevant at these
 * sizes and the alternative is rejection sampling for no gain anyone could see.
 */
async function shuffled(items, seed) {
  const out = items.slice();
  const next = await makeRandomStream(seed);
  for (let i = out.length - 1; i > 0; i--) {
    const j = (await next()) % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * The full question order for this vault: each batch shuffled within itself,
 * batches in the order they shipped.
 *
 * @param {CryptoKey} cryptoKey
 * @param {Array<{id: string, questions: Array}>} [batches] - The shipped bank by
 *   default. Only the tests pass this, to prove that appending a batch leaves
 *   the earlier ones exactly where they were.
 * @returns {Promise<Array<{id: string, tone: string, text: string}>>}
 */
export async function buildQuestionOrder(cryptoKey, batches) {
  const seed = await deriveSeed(cryptoKey);
  const order = [];
  for (const batch of batches || QUESTION_BATCHES) {
    order.push(...(await shuffled(batch.questions, seed)));
  }
  return order;
}

/**
 * Today's question.
 *
 * @param {CryptoKey} cryptoKey
 * @param {Date|number} [when]
 * @param {Array} [batches] - See buildQuestionOrder.
 * @returns {Promise<{ question: Object, day: string, index: number }>}
 */
export async function getQuestionForDay(cryptoKey, when, batches) {
  if (!cryptoKey) throw new Error('getQuestionForDay: vault is locked');
  const order = await buildQuestionOrder(cryptoKey, batches);
  const index = ((dayIndex(when) % order.length) + order.length) % order.length;
  return { question: order[index], day: dayKey(when), index };
}

/* ----------------------------------------------------------------- answers */

/**
 * Answers live one record per person per MONTH, not per day.
 *
 * Per-day records would be two rows a day - seven hundred a year, every one of
 * them listed in every sync manifest for the rest of the relationship. A month
 * bucket is twenty-four rows a year and rewrites cleanly: only its owner ever
 * writes it, so last-write-wins has no real conflict to resolve.
 */
export function answerRecordId(monthKeyString, ownerId) {
  return `ans-${monthKeyString}-${ownerId}`;
}

function sanitizeAnswerText(text) {
  const trimmed = String(text == null ? '' : text).trim();
  return trimmed.slice(0, MAX_ANSWER_LENGTH);
}

/**
 * Who wrote this row, or null if the row cannot say so consistently.
 *
 * ONE ANSWER TO "WHOSE IS THIS", AND ONLY ONE. This used to be decided in two
 * places by two different tests: readDay compared the record ID against the one
 * it expected, while listAnswered read `ownerId` out of the sealed body. Both
 * are inside the envelope so neither was forgeable, but they were two sources
 * of truth for the same question, agreeing only because one function happened
 * to write both fields consistently. Today's card and the archive could
 * disagree about whose answer an answer was, and nothing would have caught it.
 *
 * So the id and the body must now AGREE, and disagreement is not attributed at
 * all. A row like that is not an attack - it is a bug or a hand-edited backup -
 * and either way guessing which half to believe is worse than declining to.
 *
 * @param {Object} row - A decrypted answer row.
 * @returns {string|null}
 */
function ownerOf(row) {
  if (!row || typeof row !== 'object') return null;
  if (row._headerTampered === true || row._tableTampered === true) return null;
  if (typeof row.ownerId !== 'string' || !row.ownerId) return null;
  if (typeof row.month !== 'string' || !row.month) return null;
  if (row.id !== answerRecordId(row.month, row.ownerId)) return null;
  return row.ownerId;
}

/**
 * Every id that counts as "written by me".
 *
 * More than one, because a person is not a device. It is their person id plus
 * every device tag they have written under - their old phone, their laptop, and
 * whatever they were using before people existed at all. See
 * services/people.js#ownerIdsFor, which is where this set comes from.
 *
 * @param {string} ownerId - The id to WRITE under. Always counts as mine.
 * @param {Set<string>|Array<string>} [ownerIds] - Everything else that is mine.
 * @returns {Set<string>}
 */
function mineIds(ownerId, ownerIds) {
  const ids = new Set();
  if (ownerIds && typeof ownerIds[Symbol.iterator] === 'function') {
    for (const id of ownerIds) if (typeof id === 'string' && id) ids.add(id);
  }
  if (typeof ownerId === 'string' && ownerId) ids.add(ownerId);
  return ids;
}

/** @returns {boolean} True for an answer entry with actual words in it. */
function isAnswer(entry) {
  return !!(entry && typeof entry.text === 'string' && entry.text);
}

/**
 * Folds every row belonging to one side into a single day -> answer map.
 *
 * Folding rather than picking, because one person legitimately has more than
 * one row per month: a phone and a laptop each wrote their own before their
 * tags were joined up under one person, and a month answered before this
 * version shipped sits under a device tag while this month sits under a person
 * id. Picking one row would hide the others; folding shows the month the person
 * actually lived.
 *
 * Ties go to the most recently written entry, which is the only ordering the
 * records themselves carry.
 */
function foldAnswers(rows, predicate) {
  const out = {};
  for (const row of rows || []) {
    const owner = ownerOf(row);
    if (!owner || !predicate(owner)) continue;
    if (!row.answers || typeof row.answers !== 'object') continue;

    for (const [day, entry] of Object.entries(row.answers)) {
      if (!isAnswer(entry)) continue;
      const prev = out[day];
      if (!prev || (entry.answeredAt || 0) >= (prev.answeredAt || 0)) out[day] = entry;
    }
  }
  return out;
}

/** Reads every answer row, tolerating storage that is unavailable. */
async function readAllRows(store, cryptoKey) {
  try {
    return (await store.listDecrypted(ANSWER_TABLE, cryptoKey)) || [];
  } catch {
    return [];
  }
}

/**
 * Writes an answer into a month's bucket.
 *
 * `when` is not always today. The archive lets either person answer a day they
 * missed, and this already supported it - a month bucket is keyed by day, so
 * writing into a past one was never a different operation.
 *
 * WHY THIS READS EVERY ROW OF MINE AND NOT JUST ONE
 * The row it writes is the canonical one for this month under the id this
 * person writes under NOW. Anything the same person wrote under an older id
 * (their laptop's tag, or the device tag they used before people existed) is
 * folded in first, so the canonical row converges on the whole month instead of
 * the month splitting permanently the day the id changed.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, ownerIds?: Set<string>|Array<string>,
 *   questionId: string, text: string, when?: Date|number, store?: Object,
 *   timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<Object>} The sealed row, ready to broadcast.
 */
export async function saveAnswer(args) {
  const { cryptoKey, ownerId, questionId, text, when } = args;
  if (!cryptoKey) throw new Error('saveAnswer: vault is locked');
  if (!ownerId) throw new Error('saveAnswer: missing owner id');

  const body = sanitizeAnswerText(text);
  if (!body) throw new Error('saveAnswer: nothing to save');

  const store = args.store || db;
  const stamp = args.timestamp || (async () => Date.now());
  const day = dayKey(when);
  const month = monthKey(day);
  const ids = mineIds(ownerId, args.ownerIds);

  const rows = await readAllRows(store, cryptoKey);
  const answers = foldAnswers(
    rows.filter((row) => row && row.month === month),
    (owner) => ids.has(owner)
  );

  answers[day] = { questionId, text: body, answeredAt: Date.now() };

  return await store.putEncrypted(
    ANSWER_TABLE,
    {
      id: answerRecordId(month, ownerId),
      ownerId,
      month,
      answers,
      updatedAt: await stamp(),
    },
    cryptoKey
  );
}

/**
 * Both answers for a day, and whether the other one may be shown yet.
 *
 * `partnerAnswer` is null until yours exists. That is the gate, and it is
 * deliberately applied HERE rather than in the screen, so no future component
 * can render it by accident.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, when?: Date|number, store?: Object }} args
 * @returns {Promise<{ day: string, mine: Object|null, partnerAnswer: Object|null,
 *   partnerHasAnswered: boolean }>}
 */
export async function readDay(args) {
  const { cryptoKey, ownerId, when } = args;
  const day = dayKey(when);
  const empty = { day, mine: null, partnerAnswer: null, partnerHasAnswered: false };
  if (!cryptoKey || !ownerId) return empty;

  const store = args.store || db;
  const month = monthKey(day);
  const ids = mineIds(ownerId, args.ownerIds);

  const rows = (await readAllRows(store, cryptoKey)).filter((row) => row && row.month === month);

  const mine = foldAnswers(rows, (owner) => ids.has(owner))[day] || null;
  const theirs = foldAnswers(rows, (owner) => !ids.has(owner))[day] || null;

  return {
    day,
    mine,
    // Whether they have answered is safe to show - it is what makes the gate
    // feel like a locked box rather than an empty room. The words are not.
    partnerHasAnswered: theirs !== null,
    partnerAnswer: mine ? theirs : null,
  };
}

/**
 * Every day both of you have answered, newest first. The archive that makes
 * this worth doing for a year.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, store?: Object, limit?: number }} args
 * @returns {Promise<Array<{ day: string, question: Object|null, mine: Object|null,
 *   theirs: Object|null }>>}
 */
export async function listAnswered(args) {
  const { cryptoKey, ownerId } = args;
  if (!cryptoKey || !ownerId) return [];

  const store = args.store || db;
  const ids = mineIds(ownerId, args.ownerIds);
  const rows = await readAllRows(store, cryptoKey);

  // The same fold, and therefore the same idea of "mine", that readDay uses.
  const mineByDay = foldAnswers(rows, (owner) => ids.has(owner));
  const theirsByDay = foldAnswers(rows, (owner) => !ids.has(owner));

  const out = [];
  for (const [day, mine] of Object.entries(mineByDay)) {
    // Only days where YOURS exists. An archive is not a place to read around
    // the gate you have not passed yet.
    const theirs = theirsByDay[day] || null;
    const questionId = mine.questionId || (theirs && theirs.questionId);
    out.push({ day, question: findQuestion(questionId), mine, theirs });
  }

  out.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
  return typeof args.limit === 'number' ? out.slice(0, args.limit) : out;
}

/**
 * A Date at noon UTC on a `YYYY-MM-DD` day.
 *
 * Noon rather than midnight so that nothing - a stray local-time conversion, a
 * daylight-saving edge - can push the value onto the day before or after. The
 * only thing this is ever used for is turning an archive row back into a `when`
 * for saveAnswer, and landing on the wrong day there would write the answer
 * against someone else's question.
 *
 * @param {string} day
 * @returns {Date|null}
 */
export function dateFromDayKey(day) {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const [y, m, d] = day.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d, 12, 0, 0, 0));
  return Number.isFinite(date.getTime()) ? date : null;
}

/**
 * The archive, including the days you did not answer.
 *
 * WHY THIS EXISTS SEPARATELY FROM listAnswered
 * Because the gate and the archive want different things, and conflating them
 * was a real hole. listAnswered shows only days YOU answered, which is correct
 * for "what have we written" - but it meant that whoever started using the app
 * later saw almost nothing, forever. One person had weeks of answers and the
 * other had one, with no way to ever close the gap, because nothing let you
 * answer a day that had already passed.
 *
 * So a day the other person answered and you did not is listed here as
 * `missed`, with their words still withheld. It is not a hole in the archive
 * any more; it is something with a reward behind it, and answering it opens
 * exactly the same door that answering on the day would have.
 *
 * THE GATE IS STILL ENFORCED HERE, not in the screen. `theirs` is null on any
 * day you have not answered, exactly as in readDay, for exactly the same
 * reason: a gate implemented in a component is one refactor from being
 * rendered by accident.
 *
 * Days where NEITHER of you answered are not included. There is nothing to
 * show and nothing waiting, and listing a hundred and eighty untouched
 * questions would bury the handful that actually have something behind them.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, ownerIds?: Set<string>|Array<string>,
 *   store?: Object, limit?: number }} args
 * @returns {Promise<Array<{ day: string, question: Object|null, mine: Object|null,
 *   theirs: Object|null, partnerHasAnswered: boolean, missed: boolean }>>}
 */
export async function listArchive(args) {
  const { cryptoKey, ownerId } = args;
  if (!cryptoKey || !ownerId) return [];

  const store = args.store || db;
  const ids = mineIds(ownerId, args.ownerIds);
  const rows = await readAllRows(store, cryptoKey);

  const mineByDay = foldAnswers(rows, (owner) => ids.has(owner));
  const theirsByDay = foldAnswers(rows, (owner) => !ids.has(owner));

  const days = new Set([...Object.keys(mineByDay), ...Object.keys(theirsByDay)]);
  const out = [];

  for (const day of days) {
    const mine = mineByDay[day] || null;
    const theirs = theirsByDay[day] || null;
    const questionId = (mine && mine.questionId) || (theirs && theirs.questionId);

    out.push({
      day,
      question: findQuestion(questionId),
      mine,
      // The same gate as readDay, and deliberately the same line of code shape:
      // their words only exist in the result once yours do.
      theirs: mine ? theirs : null,
      partnerHasAnswered: theirs !== null,
      missed: !mine && theirs !== null,
    });
  }

  out.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
  return typeof args.limit === 'number' ? out.slice(0, args.limit) : out;
}

/**
 * Moves every answer written since `since` out of each person's rows and into
 * the other's, month by month. Anything older stays exactly where it is.
 *
 * This is the answers half of undoing the two of you trading places (see
 * services/peopleRepair.js), and the moment of the trade splits them cleanly.
 * Before it, each id belonged to the right person, so everything filed under it
 * is theirs. After it, each phone was writing under the other person's id, so
 * everything new under an id belongs to the OTHER one.
 *
 * A day that ends up answered on both sides of a merge keeps the later entry,
 * the same rule foldAnswers uses.
 *
 * @param {{ cryptoKey: CryptoKey, personA: string, personB: string, since: number,
 *   store?: Object, timestamp?: () => number|Promise<number> }} args
 * @returns {Promise<Array<Object>>} The sealed rows that changed, ready to broadcast.
 */
export async function swapAnswersSince(args) {
  const { cryptoKey, personA, personB, since } = args || {};
  if (!cryptoKey) throw new Error('swapAnswersSince: vault is locked');
  if (!personA || !personB || personA === personB) {
    throw new Error('swapAnswersSince: needs two different people');
  }
  if (!Number.isFinite(since)) throw new Error('swapAnswersSince: needs the moment to split at');

  const store = args.store || db;
  const stamp = args.timestamp || (async () => Date.now());
  const otherOf = { [personA]: personB, [personB]: personA };

  // month -> owner -> { kept, moved }
  const months = new Map();
  for (const row of await readAllRows(store, cryptoKey)) {
    const owner = ownerOf(row);
    if (owner !== personA && owner !== personB) continue;
    if (!row.answers || typeof row.answers !== 'object') continue;

    const kept = {};
    const moved = {};
    for (const [day, entry] of Object.entries(row.answers)) {
      if (!isAnswer(entry)) continue;
      if ((entry.answeredAt || 0) >= since) moved[day] = entry;
      else kept[day] = entry;
    }
    if (!months.has(row.month)) months.set(row.month, {});
    months.get(row.month)[owner] = { kept, moved };
  }

  const written = [];
  for (const [month, owners] of months) {
    const anythingMoves = Object.values(owners).some((o) => Object.keys(o.moved).length > 0);
    if (!anythingMoves) continue;

    for (const owner of [personA, personB]) {
      const own = owners[owner] || { kept: {}, moved: {} };
      const arriving = (owners[otherOf[owner]] || { moved: {} }).moved;

      const answers = { ...own.kept };
      for (const [day, entry] of Object.entries(arriving)) {
        const prev = answers[day];
        if (!prev || (entry.answeredAt || 0) >= (prev.answeredAt || 0)) answers[day] = entry;
      }

      written.push(
        await store.putEncrypted(
          ANSWER_TABLE,
          {
            id: answerRecordId(month, owner),
            ownerId: owner,
            month,
            answers,
            updatedAt: await stamp(),
          },
          cryptoKey
        )
      );
    }
  }

  return written;
}

/**
 * The first and last day each owner answered, for every owner that has.
 *
 * Day keys are `YYYY-MM-DD`, so comparing them as strings orders them.
 *
 * @param {{ cryptoKey: CryptoKey, store?: Object }} args
 * @returns {Promise<Map<string, { first: string, last: string }>>}
 */
export async function answerSpans(args) {
  const { cryptoKey } = args || {};
  const spans = new Map();
  if (!cryptoKey) return spans;

  const store = args.store || db;
  for (const row of await readAllRows(store, cryptoKey)) {
    const owner = ownerOf(row);
    if (!owner || !row.answers || typeof row.answers !== 'object') continue;
    for (const [day, entry] of Object.entries(row.answers)) {
      if (!isAnswer(entry)) continue;
      const span = spans.get(owner);
      if (!span) {
        spans.set(owner, { first: day, last: day });
        continue;
      }
      if (day < span.first) span.first = day;
      if (day > span.last) span.last = day;
    }
  }
  return spans;
}

export default {
  ANSWER_TABLE,
  MAX_ANSWER_LENGTH,
  dayKey,
  dateFromDayKey,
  listArchive,
  monthKey,
  dayIndex,
  buildQuestionOrder,
  getQuestionForDay,
  answerRecordId,
  saveAnswer,
  readDay,
  listAnswered,
  swapAnswersSince,
  answerSpans,
  totalQuestions: ALL_QUESTIONS.length,
};
