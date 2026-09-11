/**
 * src/utils/dateHelpers.js
 * Date calculations for anniversary countdowns and time-locked letters.
 *
 * Everything here works in LOCAL calendar days, deliberately. `new Date('YYYY-MM-DD')`
 * is specified to parse as UTC midnight, while every getter used for display
 * (getMonth, getDate, ...) reads local components. Combining the two shifts every
 * stored date by a day for anyone west of UTC, and for the small hours of every
 * timezone east of it - which is why parseLocalDate() is the single place that
 * conversion is allowed to happen, and why nothing in this file calls
 * toISOString() to derive a calendar day.
 */

const MS_PER_DAY = 1000 * 60 * 60 * 24;

/** A bare calendar day as a date input emits it. */
const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/**
 * A UTC-midnight instant, which is what older builds produced by running a bare
 * 'YYYY-MM-DD' from a LOCAL date input through `new Date(x).toISOString()`.
 */
const UTC_MIDNIGHT_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T00:00:00(?:\.0+)?Z$/;

/**
 * Parses a stored date into local midnight (00:00:00.000) of the day the user
 * actually picked.
 *
 * Three shapes are recognised:
 *   'YYYY-MM-DD'              -> that calendar day, local midnight
 *   'YYYY-MM-DDT00:00:00.000Z' -> legacy write path; the UTC components ARE the
 *                                 day the user picked, so they are re-anchored
 *                                 to local midnight rather than read locally
 *   any other ISO instant      -> honoured as a real point in time
 *
 * @param {string|Date} dateStr
 * @returns {Date} May be an Invalid Date; callers check with Number.isNaN(d.getTime()).
 */
export function parseLocalDate(dateStr) {
  if (!dateStr) return new Date();
  if (dateStr instanceof Date) return dateStr;

  if (typeof dateStr === 'string') {
    const trimmed = dateStr.trim();

    if (DATE_ONLY_PATTERN.test(trimmed)) {
      const [year, month, day] = trimmed.split('-').map(Number);
      return new Date(year, month - 1, day, 0, 0, 0, 0);
    }

    const utcMidnight = UTC_MIDNIGHT_PATTERN.exec(trimmed);
    if (utcMidnight) {
      return new Date(
        Number(utcMidnight[1]),
        Number(utcMidnight[2]) - 1,
        Number(utcMidnight[3]),
        0,
        0,
        0,
        0
      );
    }

    if (trimmed.includes('T')) {
      const parsed = new Date(trimmed);
      if (!Number.isNaN(parsed.getTime())) return parsed;
    }
  }

  return new Date(dateStr);
}

/**
 * Midnight at the start of the local day containing `date`.
 * @param {Date} [date]
 * @returns {Date}
 */
export function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

/**
 * The local calendar day as a `<input type="date">` value.
 *
 * The replacement for `new Date().toISOString().split('T')[0]`, which reports
 * yesterday for every local time before the UTC offset rolls over (all night in
 * the Americas, and until 05:30 in IST).
 *
 * @param {Date} [date]
 * @returns {string} 'YYYY-MM-DD'
 */
export function toLocalDateInput(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * Elapsed time since the relationship start date.
 * @param {string} startDateStr
 * @returns {{ totalDays: number, hours: number, minutes: number, seconds: number }}
 */
export function calculateLoveDuration(startDateStr) {
  const zero = { totalDays: 0, hours: 0, minutes: 0, seconds: 0 };
  if (!startDateStr) return zero;

  const start = parseLocalDate(startDateStr).getTime();
  if (!Number.isFinite(start)) return zero;

  const diff = Math.max(0, Date.now() - start);

  return {
    totalDays: Math.floor(diff / MS_PER_DAY),
    hours: Math.floor((diff / (1000 * 60 * 60)) % 24),
    minutes: Math.floor((diff / (1000 * 60)) % 60),
    seconds: Math.floor((diff / 1000) % 60),
  };
}

/**
 * The next yearly anniversary and the next hundred-day mark.
 *
 * Both counts are measured midnight-to-midnight rather than from the current
 * instant, so the day of a milestone reports 0 days left instead of rolling
 * straight past it to the next one.
 *
 * @param {string} startDateStr
 * @param {Date} [now] - The real clock by default. Tests pass one, so that
 *   "today" is a fixed date rather than whatever day the suite runs on.
 * @returns {{ anniversary: Object, hundredDay: Object }|null}
 */
export function calculateNextMilestone(startDateStr, now = new Date()) {
  if (!startDateStr) return null;

  const start = parseLocalDate(startDateStr);
  if (Number.isNaN(start.getTime())) return null;

  const today = startOfLocalDay(now);

  let nextAnniversary = new Date(
    today.getFullYear(),
    start.getMonth(),
    start.getDate(),
    0,
    0,
    0,
    0
  );
  // Strictly before today, not before *now*: on the anniversary itself the day
  // has already begun, and rolling here is what used to render "364 days left"
  // on the one day the couple is actually celebrating.
  if (nextAnniversary.getTime() < today.getTime()) {
    nextAnniversary = new Date(
      today.getFullYear() + 1,
      start.getMonth(),
      start.getDate(),
      0,
      0,
      0,
      0
    );
  }

  // The first anniversary is a year AFTER the start - never the start itself.
  // On the start day, which is exactly what a brand-new space defaults to,
  // "this year's" anniversary came out as today and the card read
  // "Today! Year 0 Celebration": a party for zero years together, on the
  // first screen she would ever see. The same guard covers a start date set
  // in the future, which otherwise also reported year 0.
  if (nextAnniversary.getFullYear() <= start.getFullYear()) {
    nextAnniversary = new Date(
      start.getFullYear() + 1,
      start.getMonth(),
      start.getDate(),
      0,
      0,
      0,
      0
    );
  }

  // A local midnight-to-midnight span is 23 or 25 hours across a DST boundary,
  // so this rounds rather than ceils.
  const daysUntilAnniversary = Math.round(
    (nextAnniversary.getTime() - today.getTime()) / MS_PER_DAY
  );
  const yearsTogether = nextAnniversary.getFullYear() - start.getFullYear();

  const totalDays = Math.max(0, Math.floor((now.getTime() - start.getTime()) / MS_PER_DAY));
  // Math.ceil already lands on the current hundred when totalDays is an exact
  // multiple, so day 100 reads "Day 100, 0 days left". The old
  // `if (nextRoundDay === totalDays)` guard sat behind a `+ 1` that made it
  // unreachable, and skipped the milestone the moment it arrived.
  const nextRoundDay = Math.max(100, Math.ceil(totalDays / 100) * 100);
  const daysUntilRound = nextRoundDay - totalDays;

  return {
    anniversary: {
      date: nextAnniversary,
      daysLeft: daysUntilAnniversary,
      year: yearsTogether,
    },
    hundredDay: {
      milestone: nextRoundDay,
      daysLeft: daysUntilRound,
    },
  };
}

/**
 * Whether a time-locked item is still sealed.
 *
 * This is presentation only. The real lock is the key wrap in
 * crypto.sealTimeLocked(); a false here does not by itself open anything.
 *
 * @param {string} unlockDateStr
 * @returns {boolean}
 */
export function isDateLocked(unlockDateStr) {
  if (!unlockDateStr) return false;
  const target = parseLocalDate(unlockDateStr).getTime();
  if (!Number.isFinite(target)) return false;
  return Date.now() < target;
}

/**
 * Human countdown to a target date.
 * @param {string} targetDateStr
 * @returns {string}
 */
export function formatTimeRemaining(targetDateStr) {
  if (!targetDateStr) return '';

  const target = parseLocalDate(targetDateStr).getTime();
  if (!Number.isFinite(target)) return '';

  const diff = target - Date.now();
  if (diff <= 0) return 'Unlocked';

  const days = Math.floor(diff / MS_PER_DAY);
  const hours = Math.floor((diff / (1000 * 60 * 60)) % 24);
  const mins = Math.floor((diff / (1000 * 60)) % 60);

  if (days > 0) return `${days}d ${hours}h left`;
  if (hours > 0) return `${hours}h ${mins}m left`;
  return `${mins}m left`;
}

/**
 * Short display form of a stored date.
 * @param {string} dateStr
 * @returns {string}
 */
export function formatDatePretty(dateStr) {
  if (!dateStr) return '';

  const parsed = parseLocalDate(dateStr);
  if (Number.isNaN(parsed.getTime())) return '';

  return parsed.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}
