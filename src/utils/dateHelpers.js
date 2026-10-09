const MS_PER_DAY = 1000 * 60 * 60 * 24;

const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

const UTC_MIDNIGHT_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T00:00:00(?:\.0+)?Z$/;

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

export function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

export function toLocalDateInput(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

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

  const daysUntilAnniversary = Math.round(
    (nextAnniversary.getTime() - today.getTime()) / MS_PER_DAY
  );
  const yearsTogether = nextAnniversary.getFullYear() - start.getFullYear();

  const totalDays = Math.max(0, Math.floor((now.getTime() - start.getTime()) / MS_PER_DAY));
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

export function isDateLocked(unlockDateStr) {
  if (!unlockDateStr) return false;
  const target = parseLocalDate(unlockDateStr).getTime();
  if (!Number.isFinite(target)) return false;
  return Date.now() < target;
}

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

export function formatLastSeen(timestamp, now = Date.now()) {
  if (!timestamp || !Number.isFinite(timestamp)) return null;
  const diff = Math.max(0, now - timestamp);
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;

  const date = new Date(timestamp);
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

export function formatLastConnected(timestamp, now = Date.now()) {
  if (!timestamp || !Number.isFinite(timestamp)) return null;
  const diff = Math.max(0, now - timestamp);
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;

  const date = new Date(timestamp);
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
