/**
 * src/components/countdown/MilestoneTracker.jsx
 * Dynamic live relationship counter, anniversary countdown, and encrypted custom milestones
 */
import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Heart, Calendar, Sparkles, Plus, Trophy, Award } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { useLiveCounter } from '../../hooks/useLiveCounter';
import { calculateNextMilestone, formatDatePretty } from '../../utils/dateHelpers';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti, fireCelebrationBurst } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { encryptText, decryptText } from '../../services/crypto';
import peerSync from '../../services/peerSync';

export function MilestoneTracker() {
  const { vaultConfig, cryptoKey, updateVaultSettings } = useVault();
  const startDate = vaultConfig?.startDate || new Date().toISOString().split('T')[0];
  const { totalDays, hours, minutes, seconds } = useLiveCounter(startDate);
  const milestones = calculateNextMilestone(startDate);
  const { celebration, tap } = useHaptics();

  const [isEditingDate, setIsEditingDate] = useState(false);
  const [newDate, setNewDate] = useState(startDate);
  const [isAddingMilestone, setIsAddingMilestone] = useState(false);
  const [milestoneTitle, setMilestoneTitle] = useState('');
  const [milestoneDate, setMilestoneDate] = useState(new Date().toISOString().split('T')[0]);

  // Read custom encrypted milestones from Dexie
  const storedMilestones = useLiveQuery(
    () => db.milestones.filter((m) => !m.deleted).toArray(),
    []
  );

  // Decrypt titles for display
  const [decryptedMilestones, setDecryptedMilestones] = useState([]);
  React.useEffect(() => {
    async function decryptAll() {
      if (!storedMilestones || !cryptoKey) return;
      const list = [];
      for (const m of storedMilestones) {
        try {
          const title = await decryptText(m.titleCipher, m.titleIv, cryptoKey);
          list.push({ ...m, title });
        } catch {
          list.push({ ...m, title: 'Encrypted Milestone' });
        }
      }
      setDecryptedMilestones(list.sort((a, b) => new Date(b.date) - new Date(a.date)));
    }
    decryptAll();
  }, [storedMilestones, cryptoKey]);

  const handleSaveStartDate = async () => {
    await updateVaultSettings({ startDate: newDate });
    setIsEditingDate(false);
    celebration();
  };

  const handleAddMilestone = async (e) => {
    e.preventDefault();
    if (!milestoneTitle.trim() || !cryptoKey) return;

    const { ciphertext, iv } = await encryptText(milestoneTitle.trim(), cryptoKey);
    const newRecord = {
      id: 'ms-' + Date.now(),
      titleCipher: ciphertext,
      titleIv: iv,
      date: milestoneDate,
      updatedAt: Date.now(),
      deleted: false,
    };

    await db.milestones.put(newRecord);
    peerSync.broadcastLiveRecord('milestones', newRecord);

    setMilestoneTitle('');
    setIsAddingMilestone(false);
    celebration();
    fireHeartConfetti();
  };

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
            onClick={() => {
              celebration();
              fireCelebrationBurst();
            }}
            variant="secondary"
            className="text-xs py-2 px-4 rounded-full gap-1.5"
          >
            <span>Send Love Burst 💕</span>
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
              <div className="text-2xl font-extrabold text-slate-800">
                {milestones.anniversary.daysLeft}
                <span className="text-xs font-semibold text-slate-400 ml-1">days left</span>
              </div>
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
              <div className="text-2xl font-extrabold text-slate-800">
                {milestones.hundredDay.daysLeft}
                <span className="text-xs font-semibold text-slate-400 ml-1">days left</span>
              </div>
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
          {decryptedMilestones.length === 0 ? (
            <p className="text-xs text-slate-400 text-center py-4 italic">
              No milestones added yet. Tap + to record your first memory!
            </p>
          ) : (
            decryptedMilestones.map((m) => (
              <div
                key={m.id}
                className="flex items-center justify-between p-3 bg-white/60 rounded-2xl border border-blush-100 hover:bg-white/80 transition"
              >
                <div className="flex items-center gap-2.5">
                  <div className="w-2 h-2 rounded-full bg-blush-400" />
                  <span className="text-xs font-bold text-slate-700">{m.title}</span>
                </div>
                <span className="text-[11px] font-medium text-slate-400">
                  {formatDatePretty(m.date)}
                </span>
              </div>
            ))
          )}
        </div>
      </GlassCard>
    </div>
  );
}

export default MilestoneTracker;
