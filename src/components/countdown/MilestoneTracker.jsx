/**
 * src/components/countdown/MilestoneTracker.jsx
 * Dynamic live relationship counter, anniversary countdown, and encrypted custom milestones.
 *
 * Schema v2: only `id`, `updatedAt` and `deleted` remain in plaintext on disk. The
 * milestone's `title` and its `date` both live inside the encrypted record
 * envelope, so the `date` index is gone and the reverse-chronological ordering
 * below happens in memory, after decryptRecord().
 *
 * Every calendar day in this file comes from toLocalDateInput(), never from
 * `toISOString().split('T')[0]` - the latter is UTC and reports yesterday for all
 * of the Americas overnight and until 05:30 in IST.
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { Heart, Calendar, Sparkles, Plus, Trophy, Award, Trash2, AlertTriangle } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { useSync } from '../../context/SyncContext';
import { useLiveCounter } from '../../hooks/useLiveCounter';
import {
  calculateNextMilestone,
  formatDatePretty,
  parseLocalDate,
  toLocalDateInput,
} from '../../utils/dateHelpers';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti, fireCelebrationBurst } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { decryptRecord, generateUrlSafeNonce } from '../../services/crypto';
import peerSync from '../../services/peerSync';

/**
 * Collision-resistant id for a milestone.
 *
 * `'ms-' + Date.now()` collides whenever both partners record something inside
 * the same millisecond, and last-write-wins then silently destroys one of them.
 */
function newMilestoneId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `ms-${crypto.randomUUID()}`;
  }
  return `ms-${generateUrlSafeNonce(12)}`;
}

/** Monotonic write stamp, so a skewed device clock cannot permanently win or lose. */
function nextTimestamp() {
  try {
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

/** Drops decryptRecord's `_`-prefixed diagnostics before writing a record back. */
function stripInternalFields(record) {
  const out = {};
  for (const [field, value] of Object.entries(record)) {
    if (field.startsWith('_')) continue;
    out[field] = value;
  }
  return out;
}

/** Sort key for a milestone whose `date` may be missing or unparseable. */
function milestoneSortKey(record) {
  if (!record.date) return 0;
  const parsed = parseLocalDate(record.date).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

export function MilestoneTracker() {
  const { vaultConfig, cryptoKey, updateVaultSettings } = useVault();
  const { sendLoveBurst } = useSync();
  const startDate = vaultConfig?.startDate || toLocalDateInput();
  const { totalDays, hours, minutes, seconds } = useLiveCounter(startDate);
  const milestones = calculateNextMilestone(startDate);
  const { celebration, tap } = useHaptics();

  const [isSendingBurst, setIsSendingBurst] = useState(false);
  const [isEditingDate, setIsEditingDate] = useState(false);
  const [newDate, setNewDate] = useState(startDate);
  const [isAddingMilestone, setIsAddingMilestone] = useState(false);
  const [milestoneTitle, setMilestoneTitle] = useState('');
  const [milestoneDate, setMilestoneDate] = useState(() => toLocalDateInput());
  const [records, setRecords] = useState([]);
  const [skippedCount, setSkippedCount] = useState(0);
  const [error, setError] = useState('');

  useEffect(() => {
    if (startDate) setNewDate(startDate);
  }, [startDate]);

  // Raw rows only, purely for liveness. `date` is encrypted now, so the query
  // cannot order by it - see the decrypt pass below.
  const storedMilestones = useLiveQuery(() => db.milestones.toArray(), []);

  const decryptCache = useRef(new Map());

  /* --------------------------------------------------------------------- *
   * Decrypt pass
   * --------------------------------------------------------------------- */

  useEffect(() => {
    // A different key invalidates every cached plaintext.
    decryptCache.current = new Map();
  }, [cryptoKey]);

  useEffect(() => {
    let active = true;

    async function decryptAll() {
      if (!cryptoKey) {
        setRecords([]);
        setSkippedCount(0);
        return;
      }
      if (!storedMilestones) return;

      const cache = decryptCache.current;
      const seen = new Set();
      const next = [];
      let skipped = 0;

      for (const row of storedMilestones) {
        if (!row || typeof row !== 'object') continue;
        if (row.deleted === true) continue;

        // useLiveQuery returns fresh object identities on every write to the
        // table, so without this cache every milestone would be re-decrypted
        // whenever any one of them changed. The IV rotates on each
        // re-encryption, which makes it a sound staleness marker.
        const fingerprint = row.iv || row.titleIv || '';
        const cacheKey = `${row.id}::${row.updatedAt}::${fingerprint}`;
        seen.add(cacheKey);

        let record = cache.get(cacheKey);
        if (!record) {
          let decrypted;
          try {
            // The table is REQUIRED here. Without it decryptRecord has no expected
            // table to compare the sealed `_tbl` against, so a row sealed for a
            // different one is never flagged and renders as ordinary content.
            decrypted = await decryptRecord(row, cryptoKey, { table: 'milestones' });
          } catch {
            skipped += 1;
            continue;
          }
          if (decrypted._headerTampered) {
            // A peer rewrote the plaintext id/updatedAt/deleted header. Refuse it.
            skipped += 1;
            continue;
          }
          record = stripInternalFields(decrypted);
          cache.set(cacheKey, record);
        }

        if (record.deleted === true) continue;
        next.push(record);
      }

      for (const key of Array.from(cache.keys())) {
        if (!seen.has(key)) cache.delete(key);
      }

      if (!active) return;

      next.sort((a, b) => milestoneSortKey(b) - milestoneSortKey(a));
      setRecords(next);
      setSkippedCount(skipped);
    }

    decryptAll();
    return () => {
      active = false;
    };
  }, [storedMilestones, cryptoKey]);

  /* --------------------------------------------------------------------- *
   * Mutations
   * --------------------------------------------------------------------- */

  const handleSaveStartDate = useCallback(async () => {
    await updateVaultSettings({ startDate: newDate });
    setIsEditingDate(false);
    celebration();
  }, [updateVaultSettings, newDate, celebration]);

  const handleAddMilestone = useCallback(
    async (e) => {
      e.preventDefault();
      const title = milestoneTitle.trim();
      if (!title || !cryptoKey) return;

      try {
        const row = await db.putEncrypted(
          'milestones',
          {
            id: newMilestoneId(),
            title,
            // Stored as the bare local calendar day the picker emitted. Running
            // it through new Date(x).toISOString() would move it to UTC midnight
            // and shift the displayed day for most of the world.
            date: milestoneDate,
            updatedAt: nextTimestamp(),
            deleted: false,
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('milestones', row);

        setMilestoneTitle('');
        setIsAddingMilestone(false);
        setError('');
        celebration();
        fireHeartConfetti();
      } catch {
        setError('Could not save that milestone. Our Space may have locked.');
      }
    },
    [milestoneTitle, milestoneDate, cryptoKey, celebration]
  );

  const handleDeleteMilestone = useCallback(
    async (id) => {
      if (!window.confirm('Delete this milestone?')) return;
      tap();

      try {
        // Tombstone rather than delete: the row keeps its id and a bumped
        // updatedAt so the removal replicates, and drops its payload so the
        // title is really gone.
        const row = await db.softDelete('milestones', id, cryptoKey);
        if (row) peerSync.broadcastLiveRecord('milestones', row);
        setError('');
      } catch {
        setError('Could not delete that milestone. Our Space may have locked.');
      }
    },
    [cryptoKey, tap]
  );

  return (
    <div className="space-y-5">
      {/* Primary Big Days Counter */}
      <GlassCard className="text-center relative overflow-hidden bg-gradient-to-b from-white/90 to-blush-50/80 border-2 border-blush-200">
        <div className="absolute -top-10 -right-10 w-36 h-36 bg-blush-200/40 rounded-full blur-2xl pointer-events-none" />
        <div className="absolute -bottom-10 -left-10 w-36 h-36 bg-lavender-200/40 rounded-full blur-2xl pointer-events-none" />

        <div className="flex items-center justify-center gap-1.5 text-xs font-semibold text-blush-500 uppercase tracking-widest mb-1">
          <Heart className="w-3.5 h-3.5 fill-blush-400" />
          <span>Together Forever</span>
          <Heart className="w-3.5 h-3.5 fill-blush-400" />
        </div>

        <motion.div
          key={totalDays}
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          className="text-6xl font-black text-slate-800 tracking-tight my-2"
        >
          {totalDays}
          <span className="text-2xl font-bold text-blush-500 ml-2">Days</span>
        </motion.div>

        {/* Live Sub-counter: Hours, Mins, Secs */}
        <div className="grid grid-cols-3 gap-2 max-w-[260px] mx-auto my-3 text-center">
          <div className="bg-white/70 py-1.5 px-2 rounded-2xl border border-blush-100 shadow-sm">
            <span className="block text-lg font-bold text-slate-700 leading-tight">
              {String(hours).padStart(2, '0')}
            </span>
            <span className="text-[10px] font-semibold text-slate-400 uppercase">Hours</span>
          </div>
          <div className="bg-white/70 py-1.5 px-2 rounded-2xl border border-blush-100 shadow-sm">
            <span className="block text-lg font-bold text-slate-700 leading-tight">
              {String(minutes).padStart(2, '0')}
            </span>
            <span className="text-[10px] font-semibold text-slate-400 uppercase">Minutes</span>
          </div>
          <div className="bg-white/70 py-1.5 px-2 rounded-2xl border border-blush-100 shadow-sm">
            <span className="block text-lg font-bold text-blush-600 leading-tight font-mono">
              {String(seconds).padStart(2, '0')}
            </span>
            <span className="text-[10px] font-semibold text-slate-400 uppercase">Seconds</span>
          </div>
        </div>

        {/* Start Date Indicator / Edit */}
        <div className="pt-2">
          {isEditingDate ? (
            <div className="flex items-center justify-center gap-2 max-w-xs mx-auto">
              <input
                type="date"
                value={newDate}
                onChange={(e) => setNewDate(e.target.value)}
                className="px-3 py-1.5 text-xs bg-white border border-blush-300 rounded-xl"
              />
              <BouncyButton onClick={handleSaveStartDate} className="py-1.5 px-3 text-xs">
                Save
              </BouncyButton>
              <button
                onClick={() => setIsEditingDate(false)}
                className="text-xs text-slate-400 hover:text-slate-600"
              >
                Cancel
              </button>
            </div>
          ) : (
            <button
              onClick={() => {
                tap();
                setIsEditingDate(true);
              }}
              className="text-xs text-slate-500 hover:text-blush-600 font-medium inline-flex items-center gap-1.5"
            >
              <Calendar className="w-3.5 h-3.5 text-blush-400" />
              <span>Since {formatDatePretty(startDate)} (Tap to edit)</span>
            </button>
          )}
        </div>

        {/* Heart Burst Trigger */}
        <div className="mt-4 pt-4 border-t border-blush-100/70 flex justify-center">
          <BouncyButton
            onClick={async () => {
              celebration();
              fireCelebrationBurst();
              if (sendLoveBurst && !isSendingBurst) {
                setIsSendingBurst(true);
                try {
                  await sendLoveBurst();
                } finally {
                  setTimeout(() => setIsSendingBurst(false), 1000);
                }
              }
            }}
            variant="secondary"
            className="text-xs py-2 px-4 rounded-full gap-1.5"
            disabled={isSendingBurst}
          >
            <span>{isSendingBurst ? 'Sending Love... 💕' : 'Send Love Burst 💕'}</span>
          </BouncyButton>
        </div>
      </GlassCard>

      {/* Upcoming Milestones Grid */}
      {milestones && (
        <div className="grid grid-cols-2 gap-3">
          {/* Next Anniversary */}
          <GlassCard className="p-4 flex flex-col justify-between border border-blush-100/90">
            <div className="flex items-center justify-between text-blush-500 mb-2">
              <Award className="w-5 h-5" />
              <span className="text-[10px] font-bold uppercase tracking-wider bg-blush-100 px-2 py-0.5 rounded-full">
                Anniversary
              </span>
            </div>
            <div>
              {milestones.anniversary.daysLeft === 0 ? (
                <div className="text-2xl font-extrabold text-blush-600">Today! 🎉</div>
              ) : (
                <div className="text-2xl font-extrabold text-slate-800">
                  {milestones.anniversary.daysLeft}
                  <span className="text-xs font-semibold text-slate-400 ml-1">days left</span>
                </div>
              )}
              <p className="text-xs text-slate-500 mt-0.5 font-medium">
                Year {milestones.anniversary.year} Celebration
              </p>
            </div>
          </GlassCard>

          {/* Next 100-Day Milestone */}
          <GlassCard className="p-4 flex flex-col justify-between border border-lavender-100/90">
            <div className="flex items-center justify-between text-lavender-500 mb-2">
              <Trophy className="w-5 h-5" />
              <span className="text-[10px] font-bold uppercase tracking-wider bg-lavender-100 px-2 py-0.5 rounded-full text-lavender-700">
                Day {milestones.hundredDay.milestone}
              </span>
            </div>
            <div>
              {milestones.hundredDay.daysLeft === 0 ? (
                <div className="text-2xl font-extrabold text-lavender-600">Today! 🎉</div>
              ) : (
                <div className="text-2xl font-extrabold text-slate-800">
                  {milestones.hundredDay.daysLeft}
                  <span className="text-xs font-semibold text-slate-400 ml-1">days left</span>
                </div>
              )}
              <p className="text-xs text-slate-500 mt-0.5 font-medium">
                Next 100-day milestone
              </p>
            </div>
          </GlassCard>
        </div>
      )}

      {/* Custom Milestones Scrapbook */}
      <GlassCard className="p-5">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <Sparkles className="w-4 h-4 text-amber-500" />
            <h3 className="text-sm font-bold text-slate-800">Relationship Milestones</h3>
          </div>
          <button
            onClick={() => {
              tap();
              setIsAddingMilestone(!isAddingMilestone);
            }}
            className="w-7 h-7 rounded-full bg-blush-100 text-blush-600 flex items-center justify-center hover:bg-blush-200 transition"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>

        {/* Failure surface - previously these paths failed silently */}
        {(error || skippedCount > 0) && (
          <div className="flex items-start gap-2 p-3 mb-3 rounded-2xl bg-amber-50 border border-amber-200 text-amber-800">
            <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" />
            <p className="text-xs font-medium leading-snug">
              {error ||
                `${skippedCount} milestone${skippedCount === 1 ? '' : 's'} could not be opened with your passphrase, so ${
                  skippedCount === 1 ? 'it is' : 'they are'
                } hidden for now.`}
            </p>
          </div>
        )}

        {isAddingMilestone && (
          <form onSubmit={handleAddMilestone} className="space-y-3 mb-4 p-3 bg-white/80 rounded-2xl border border-blush-200">
            <div>
              <input
                type="text"
                value={milestoneTitle}
                onChange={(e) => setMilestoneTitle(e.target.value)}
                placeholder="e.g. First kiss, moved in together..."
                required
                className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="date"
                value={milestoneDate}
                onChange={(e) => setMilestoneDate(e.target.value)}
                required
                className="px-3 py-1.5 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
              />
              <BouncyButton type="submit" className="py-1.5 px-4 text-xs font-bold">
                Add
              </BouncyButton>
            </div>
          </form>
        )}

        <div className="space-y-2">
          {records.length === 0 ? (
            <p className="text-xs text-slate-400 text-center py-4 italic">
              No milestones yet. Tap + to add your first one!
            </p>
          ) : (
            records.map((m) => (
              <div
                key={m.id}
                className="flex items-center justify-between p-3 bg-white/60 rounded-2xl border border-blush-100 hover:bg-white/80 transition group"
              >
                <div className="flex items-center gap-2.5 flex-1 min-w-0 pr-2">
                  <div className="w-2 h-2 rounded-full bg-blush-400 flex-shrink-0" />
                  <span className="text-xs font-bold text-slate-700 truncate">
                    {m.title || 'A milestone'}
                  </span>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  <span className="text-[11px] font-medium text-slate-400">
                    {formatDatePretty(m.date)}
                  </span>
                  <button
                    type="button"
                    onClick={() => handleDeleteMilestone(m.id)}
                    className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-300 hover:text-rose-500 hover:bg-rose-50 transition"
                    title="Delete milestone"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </GlassCard>
    </div>
  );
}

export default MilestoneTracker;
