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
 * Both phones share one key, so her answer arrives on your device readable. The
 * app will not show it to you until you have written yours, and that gate is
 * the whole feature - but it is a promise, not a lock, exactly like the
 * time-locked letters. Someone determined and technical could read around it.
 * That is not the failure mode this is built for.
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

/** Reads a month bucket, tolerating one that is absent or unreadable. */
async function readMonth(store, monthKeyString, ownerId, cryptoKey) {
  try {
    const row = await store.getDecrypted(
      ANSWER_TABLE,
      answerRecordId(monthKeyString, ownerId),
      cryptoKey
    );
    if (!row) return null;
    if (row._headerTampered === true || row._tableTampered === true) return null;
    return row;
  } catch {
    return null;
  }
}

/**
 * Writes today's answer into this month's bucket.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, questionId: string, text: string,
 *   when?: Date|number, store?: Object, timestamp?: () => number|Promise<number> }} args
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

  const existing = await readMonth(store, month, ownerId, cryptoKey);
  const answers = existing && existing.answers && typeof existing.answers === 'object'
    ? { ...existing.answers }
    : {};

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

  let rows;
  try {
    rows = await store.listDecrypted(ANSWER_TABLE, cryptoKey);
  } catch {
    return empty;
  }

  const mineId = answerRecordId(month, ownerId);
  let mine = null;
  let theirs = null;

  for (const row of rows || []) {
    if (!row || row.month !== month) continue;
    if (row._headerTampered === true || row._tableTampered === true) continue;
    if (!row.answers || typeof row.answers !== 'object') continue;
    const entry = row.answers[day];
    if (!entry || typeof entry.text !== 'string' || !entry.text) continue;

    if (row.id === mineId) mine = entry;
    else theirs = entry;
  }

  return {
    day,
    mine,
    // Whether she has answered is safe to show - it is what makes the gate feel
    // like a locked box rather than an empty room. The words are not.
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
  let rows;
  try {
    rows = await store.listDecrypted(ANSWER_TABLE, cryptoKey);
  } catch {
    return [];
  }

  /** @type {Map<string, { mine: Object|null, theirs: Object|null }>} */
  const byDay = new Map();

  for (const row of rows || []) {
    if (!row || !row.answers || typeof row.answers !== 'object') continue;
    if (row._headerTampered === true || row._tableTampered === true) continue;
    const isMine = row.ownerId === ownerId;

    for (const [day, entry] of Object.entries(row.answers)) {
      if (!entry || typeof entry.text !== 'string' || !entry.text) continue;
      if (!byDay.has(day)) byDay.set(day, { mine: null, theirs: null });
      const slot = byDay.get(day);
      if (isMine) slot.mine = entry;
      else slot.theirs = entry;
    }
  }

  const out = [];
  for (const [day, slot] of byDay) {
    // Only days where YOURS exists. An archive is not a place to read around
    // the gate you have not passed yet.
    if (!slot.mine) continue;
    const questionId = slot.mine.questionId || (slot.theirs && slot.theirs.questionId);
    out.push({ day, question: findQuestion(questionId), mine: slot.mine, theirs: slot.theirs });
  }

  out.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
  return typeof args.limit === 'number' ? out.slice(0, args.limit) : out;
}

export default {
  ANSWER_TABLE,
  MAX_ANSWER_LENGTH,
  dayKey,
  monthKey,
  dayIndex,
  buildQuestionOrder,
  getQuestionForDay,
  answerRecordId,
  saveAnswer,
  readDay,
  listAnswered,
  totalQuestions: ALL_QUESTIONS.length,
};
