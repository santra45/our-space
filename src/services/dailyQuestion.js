import db from '../db/index.js';
import { ALL_QUESTIONS, QUESTION_BATCHES, findQuestion } from '../data/dailyQuestions.js';

export const ANSWER_TABLE = 'dailyAnswers';

const SHUFFLE_CONTEXT = 'our-space/daily-question/order/v1';

export const MAX_ANSWER_LENGTH = 2000;

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

export function dayKey(when) {
  const date = when instanceof Date ? when : new Date(when === undefined ? Date.now() : when);
  return date.toISOString().slice(0, 10);
}

export function monthKey(dayKeyString) {
  return String(dayKeyString).slice(0, 7);
}

export function dayIndex(when) {
  const date = when instanceof Date ? when : new Date(when === undefined ? Date.now() : when);
  return Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) / 86400000);
}

async function deriveSeed(cryptoKey) {
  const encoder = new TextEncoder();
  const sealed = await webCrypto().subtle.encrypt(
    { name: 'AES-GCM', iv: new Uint8Array(12) },
    cryptoKey,
    encoder.encode(SHUFFLE_CONTEXT)
  );
  return new Uint8Array(await webCrypto().subtle.digest('SHA-256', sealed));
}

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

async function shuffled(items, seed) {
  const out = items.slice();
  const next = await makeRandomStream(seed);
  for (let i = out.length - 1; i > 0; i--) {
    const j = (await next()) % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export async function buildQuestionOrder(cryptoKey, batches) {
  const seed = await deriveSeed(cryptoKey);
  const order = [];
  for (const batch of batches || QUESTION_BATCHES) {
    order.push(...(await shuffled(batch.questions, seed)));
  }
  return order;
}

export async function getQuestionForDay(cryptoKey, when, batches) {
  if (!cryptoKey) throw new Error('getQuestionForDay: vault is locked');
  const order = await buildQuestionOrder(cryptoKey, batches);
  const index = ((dayIndex(when) % order.length) + order.length) % order.length;
  return { question: order[index], day: dayKey(when), index };
}

export function answerRecordId(monthKeyString, ownerId) {
  return `ans-${monthKeyString}-${ownerId}`;
}

function sanitizeAnswerText(text) {
  const trimmed = String(text == null ? '' : text).trim();
  return trimmed.slice(0, MAX_ANSWER_LENGTH);
}

function ownerOf(row) {
  if (!row || typeof row !== 'object') return null;
  if (row._headerTampered === true || row._tableTampered === true) return null;
  if (typeof row.ownerId !== 'string' || !row.ownerId) return null;
  if (typeof row.month !== 'string' || !row.month) return null;
  if (row.id !== answerRecordId(row.month, row.ownerId)) return null;
  return row.ownerId;
}

function mineIds(ownerId, ownerIds) {
  const ids = new Set();
  if (ownerIds && typeof ownerIds[Symbol.iterator] === 'function') {
    for (const id of ownerIds) if (typeof id === 'string' && id) ids.add(id);
  }
  if (typeof ownerId === 'string' && ownerId) ids.add(ownerId);
  return ids;
}

function isAnswer(entry) {
  return !!(entry && typeof entry.text === 'string' && entry.text);
}

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

async function readAllRows(store, cryptoKey) {
  try {
    return (await store.listDecrypted(ANSWER_TABLE, cryptoKey)) || [];
  } catch {
    return [];
  }
}

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
    partnerHasAnswered: theirs !== null,
    partnerAnswer: mine ? theirs : null,
  };
}

export async function listAnswered(args) {
  const { cryptoKey, ownerId } = args;
  if (!cryptoKey || !ownerId) return [];

  const store = args.store || db;
  const ids = mineIds(ownerId, args.ownerIds);
  const rows = await readAllRows(store, cryptoKey);

  const mineByDay = foldAnswers(rows, (owner) => ids.has(owner));
  const theirsByDay = foldAnswers(rows, (owner) => !ids.has(owner));

  const out = [];
  for (const [day, mine] of Object.entries(mineByDay)) {
    const theirs = theirsByDay[day] || null;
    const questionId = mine.questionId || (theirs && theirs.questionId);
    out.push({ day, question: findQuestion(questionId), mine, theirs });
  }

  out.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
  return typeof args.limit === 'number' ? out.slice(0, args.limit) : out;
}

export function dateFromDayKey(day) {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const [y, m, d] = day.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d, 12, 0, 0, 0));
  return Number.isFinite(date.getTime()) ? date : null;
}

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
      theirs: mine ? theirs : null,
      partnerHasAnswered: theirs !== null,
      missed: !mine && theirs !== null,
    });
  }

  out.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
  return typeof args.limit === 'number' ? out.slice(0, args.limit) : out;
}

export async function swapAnswersSince(args) {
  const store = (args && args.store) || db;
  const { rows } = await planAnswerSwap(args);
  if (rows.length === 0) return [];
  const sealed = await store.putEncryptedMany(
    rows.map((fields) => ({ table: ANSWER_TABLE, fields })),
    args.cryptoKey
  );
  return sealed.map((entry) => entry.row);
}

export async function planAnswerSwap(args) {
  const { cryptoKey, personA, personB, since } = args || {};
  if (!cryptoKey) throw new Error('swapAnswersSince: vault is locked');
  if (!personA || !personB || personA === personB) {
    throw new Error('swapAnswersSince: needs two different people');
  }
  if (!Number.isFinite(since)) throw new Error('swapAnswersSince: needs the moment to split at');

  const store = args.store || db;
  const stamp = args.timestamp || (async () => Date.now());
  const otherOf = { [personA]: personB, [personB]: personA };
  const before = await readAllRows(store, cryptoKey);

  const months = new Map();
  for (const row of before) {
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

  const rows = [];
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

      rows.push({
        id: answerRecordId(month, owner),
        ownerId: owner,
        month,
        answers,
        updatedAt: await stamp(),
      });
    }
  }

  const replaced = new Set(rows.map((row) => row.id));
  const after = [...before.filter((row) => !replaced.has(row && row.id)), ...rows];
  return { rows, after };
}

export async function answerSpans(args) {
  const { cryptoKey } = args || {};
  const spans = new Map();
  if (!cryptoKey && !Array.isArray(args && args.rows)) return spans;

  const rows = Array.isArray(args.rows) ? args.rows : await readAllRows(args.store || db, cryptoKey);
  for (const row of rows) {
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
  planAnswerSwap,
  answerSpans,
  totalQuestions: ALL_QUESTIONS.length,
};
