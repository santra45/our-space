/**
 * src/utils/dateHelpers.js
 * Date calculations for anniversary countdowns and time-locked letters
 */

export function calculateLoveDuration(startDateStr) {
  if (!startDateStr) return { days: 0, hours: 0, minutes: 0, seconds: 0, totalDays: 0 };

  const start = new Date(startDateStr).getTime();
  const now = Date.now();
  const diff = Math.max(0, now - start);

  const totalDays = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff / (1000 * 60 * 60)) % 24);
  const minutes = Math.floor((diff / (1000 * 60)) % 60);
  const seconds = Math.floor((diff / 1000) % 60);

  return { totalDays, hours, minutes, seconds };
}

export function calculateNextMilestone(startDateStr) {
  if (!startDateStr) return null;
  const start = new Date(startDateStr);
  const now = new Date();

  // Next yearly anniversary
  let nextAnniversary = new Date(now.getFullYear(), start.getMonth(), start.getDate());
  if (nextAnniversary.getTime() < now.getTime()) {
    nextAnniversary.setFullYear(now.getFullYear() + 1);
  }

  const diffMs = nextAnniversary.getTime() - now.getTime();
  const daysUntilAnniversary = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
  const yearsTogether = nextAnniversary.getFullYear() - start.getFullYear();

  // Next hundred-day milestone (100, 200, 500, 1000 days)
  const totalDays = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
  let nextRoundDay = Math.ceil((totalDays + 1) / 100) * 100;
  if (nextRoundDay === totalDays) nextRoundDay += 100;
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
  const target = new Date(unlockDateStr).getTime();
  return Date.now() < target;
}

export function formatTimeRemaining(targetDateStr) {
  if (!targetDateStr) return '';
  const diff = new Date(targetDateStr).getTime() - Date.now();
  if (diff <= 0) return 'Unlocked';

  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff / (1000 * 60 * 60)) % 24);
  const mins = Math.floor((diff / (1000 * 60)) % 60);

  if (days > 0) return `${days}d ${hours}h left`;
  if (hours > 0) return `${hours}h ${mins}m left`;
  return `${mins}m left`;
}

export function formatDatePretty(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}
