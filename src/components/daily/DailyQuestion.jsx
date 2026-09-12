/**
 * src/components/daily/DailyQuestion.jsx
 * Today's question, on the first screen she sees.
 *
 * WHY A CARD AND NOT A TAB
 * A daily habit cannot live behind navigation. This sits at the top of the
 * landing tab, so it is the first thing in front of her every time she opens
 * the app - the rest of the feature (writing, the archive) opens from here.
 *
 * THE GATE IS NOT ENFORCED HERE
 * services/dailyQuestion.js withholds the partner's answer until yours exists,
 * and this component simply never receives it. That is on purpose: a gate
 * implemented in a screen is one refactor away from being rendered by accident.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { MessageCircleHeart, X, Lock, Check, History } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { useHaptics } from '../../hooks/useHaptics';
import { getDeviceId } from '../../services/deviceId';
import peerSync from '../../services/peerSync';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import {
  ANSWER_TABLE,
  MAX_ANSWER_LENGTH,
  getQuestionForDay,
  saveAnswer,
  readDay,
  listAnswered,
} from '../../services/dailyQuestion';

/** `2026-09-10` -> `10 September`. */
function prettyDay(day) {
  try {
    const [y, m, d] = String(day).split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString(undefined, {
      day: 'numeric',
      month: 'long',
      timeZone: 'UTC',
    });
  } catch {
    return day;
  }
}

export function DailyQuestion() {
  const { cryptoKey } = useVault();
  const { tap, celebration } = useHaptics();

  const [today, setToday] = useState(null);
  const [state, setState] = useState(null);
  const [isOpen, setIsOpen] = useState(false);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [showArchive, setShowArchive] = useState(false);
  const [archive, setArchive] = useState([]);

  const ownerId = getDeviceId();

  const refresh = useCallback(async () => {
    if (!cryptoKey) return;
    try {
      const question = await getQuestionForDay(cryptoKey);
      const day = await readDay({ cryptoKey, ownerId });
      setToday(question);
      setState(day);
    } catch {
      // A screen that cannot read today is not an emergency - it just has
      // nothing to show, and the rest of the app carries on around it.
      setToday(null);
    }
  }, [cryptoKey, ownerId]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  /* Her answer can land while this is open, so follow the table rather than
     only reading once. */
  useEffect(() => {
    const onUpdate = () => refresh();
    peerSync.on('data-updated', onUpdate);
    return () => peerSync.off('data-updated', onUpdate);
  }, [refresh]);

  const handleSave = async (e) => {
    e.preventDefault();
    if (saving || !draft.trim() || !today) return;

    setSaving(true);
    setError('');
    try {
      const row = await saveAnswer({
        cryptoKey,
        ownerId,
        questionId: today.question.id,
        text: draft,
        timestamp: () => peerSync.getSyncSafeTimestamp(),
      });
      peerSync.broadcastLiveRecord(ANSWER_TABLE, row);
      setDraft('');
      celebration();
      fireHeartConfetti();
      await refresh();
    } catch {
      setError('That did not save. Try again in a moment.');
    } finally {
      setSaving(false);
    }
  };

  const openArchive = async () => {
    tap();
    setShowArchive(true);
    try {
      setArchive(await listAnswered({ cryptoKey, ownerId, limit: 120 }));
    } catch {
      setArchive([]);
    }
  };

  if (!cryptoKey || !today) return null;

  const answered = !!(state && state.mine);
  const partnerWaiting = !!(state && state.partnerHasAnswered) && !answered;
  const bothIn = answered && !!(state && state.partnerAnswer);

  return (
    <>
      {/* ---------------------------------------------------------- the card */}
      <motion.button
        type="button"
        onClick={() => {
          tap();
          setIsOpen(true);
        }}
        whileTap={{ scale: 0.98 }}
        className="w-full text-left mb-4 p-4 rounded-3xl bg-white/80 backdrop-blur-sm border border-lavender-200 shadow-sm hover:shadow-md transition-shadow"
      >
        <div className="flex items-center gap-2 mb-1.5">
          <MessageCircleHeart className="w-4 h-4 text-lavender-400" />
          <span className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide">
            Today&apos;s question
          </span>
          {bothIn && <Check className="w-3.5 h-3.5 text-emerald-500 ml-auto" />}
        </div>

        <p className="font-handwriting text-xl text-slate-800 leading-snug">
          {today.question.text}
        </p>

        <p className="text-[11px] text-slate-500 mt-2">
          {bothIn
            ? 'You both answered. Tap to read both 💕'
            : answered
              ? "Answered. Your partner's appears the moment they write one."
              : partnerWaiting
                ? 'Your partner has already answered. Yours unlocks it 💕'
                : 'Tap to answer'}
        </p>
      </motion.button>

      {/* --------------------------------------------------------- the sheet */}
      <AnimatePresence>
        {isOpen && (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-slate-900/40 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, y: 40 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 40 }}
              className="w-full sm:max-w-md max-h-[92vh] overflow-y-auto overscroll-contain bg-white rounded-t-3xl sm:rounded-3xl p-5 shadow-2xl border border-lavender-100 relative"
            >
              <button
                onClick={() => {
                  setIsOpen(false);
                  setShowArchive(false);
                }}
                className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
              >
                <X className="w-4 h-4" />
              </button>

              {!showArchive ? (
                <>
                  <p className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide mb-1">
                    {prettyDay(today.day)}
                  </p>
                  <p className="font-handwriting text-2xl text-slate-800 leading-snug mb-4 pr-8">
                    {today.question.text}
                  </p>

                  {!answered ? (
                    <form onSubmit={handleSave} className="space-y-3">
                      {partnerWaiting && (
                        <div className="flex items-start gap-2 p-2.5 rounded-2xl bg-lavender-50 border border-lavender-100">
                          <Lock className="w-4 h-4 text-lavender-400 shrink-0 mt-0.5" />
                          <p className="text-[11px] leading-relaxed text-lavender-700">
                            Your partner has answered already. Write yours and you will both be able to
                            read them.
                          </p>
                        </div>
                      )}

                      <textarea
                        value={draft}
                        onChange={(e) => setDraft(e.target.value)}
                        maxLength={MAX_ANSWER_LENGTH}
                        rows={5}
                        autoFocus
                        placeholder="However much or little you want…"
                        className="w-full px-4 py-3 bg-white border border-lavender-200 rounded-2xl text-slate-800 text-sm leading-relaxed focus:outline-none focus:ring-2 focus:ring-lavender-300 placeholder:text-slate-400 resize-none"
                      />

                      {error && (
                        <p role="alert" className="text-[11px] text-rose-600 font-semibold">
                          {error}
                        </p>
                      )}

                      <BouncyButton
                        type="submit"
                        disabled={saving || !draft.trim()}
                        className="w-full py-3 text-sm font-bold disabled:opacity-50"
                      >
                        {saving ? 'Saving…' : 'Answer 💕'}
                      </BouncyButton>

                      <p className="text-[10px] text-slate-400 text-center leading-relaxed">
                        You will not see your partner&apos;s until you have written yours.
                      </p>
                    </form>
                  ) : (
                    <div className="space-y-3">
                      <div className="p-3 rounded-2xl bg-blush-50/70 border border-blush-100">
                        <p className="text-[10px] font-bold text-blush-500 uppercase tracking-wide mb-1">
                          You
                        </p>
                        <p className="text-sm text-slate-700 leading-relaxed whitespace-pre-wrap">
                          {state.mine.text}
                        </p>
                      </div>

                      {state.partnerAnswer ? (
                        <div className="p-3 rounded-2xl bg-lavender-50 border border-lavender-100">
                          <p className="text-[10px] font-bold text-lavender-500 uppercase tracking-wide mb-1">
                            Them
                          </p>
                          <p className="text-sm text-slate-700 leading-relaxed whitespace-pre-wrap">
                            {state.partnerAnswer.text}
                          </p>
                        </div>
                      ) : (
                        <div className="p-3 rounded-2xl bg-slate-50 border border-slate-100 text-center">
                          <p className="text-[11px] text-slate-500 leading-relaxed">
                            Nothing from your partner yet today. It will appear here on its own.
                          </p>
                        </div>
                      )}
                    </div>
                  )}

                  <button
                    type="button"
                    onClick={openArchive}
                    className="w-full mt-4 pt-3 border-t border-slate-100 inline-flex items-center justify-center gap-1.5 text-xs font-bold text-slate-500 hover:text-lavender-600"
                  >
                    <History className="w-3.5 h-3.5" />
                    <span>Everything you have answered</span>
                  </button>
                </>
              ) : (
                <>
                  <p className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide mb-3">
                    Your answers so far
                  </p>

                  {archive.length === 0 ? (
                    <p className="text-xs text-slate-500 leading-relaxed py-6 text-center">
                      Nothing here yet. Answer today&apos;s and it starts filling itself.
                    </p>
                  ) : (
                    <div className="space-y-4">
                      {archive.map((entry) => (
                        <div key={entry.day} className="pb-3 border-b border-slate-100 last:border-0">
                          <p className="text-[10px] text-slate-400 font-mono mb-1">
                            {prettyDay(entry.day)}
                          </p>
                          <p className="font-handwriting text-lg text-slate-800 leading-snug mb-1.5">
                            {entry.question ? entry.question.text : 'A question from back then'}
                          </p>
                          <p className="text-[11px] text-slate-600 leading-relaxed whitespace-pre-wrap">
                            <span className="font-bold text-blush-500">You: </span>
                            {entry.mine.text}
                          </p>
                          {entry.theirs && (
                            <p className="text-[11px] text-slate-600 leading-relaxed whitespace-pre-wrap mt-1">
                              <span className="font-bold text-lavender-500">Them: </span>
                              {entry.theirs.text}
                            </p>
                          )}
                        </div>
                      ))}
                    </div>
                  )}

                  <button
                    type="button"
                    onClick={() => setShowArchive(false)}
                    className="w-full mt-4 pt-3 border-t border-slate-100 text-xs font-bold text-slate-500 hover:text-lavender-600"
                  >
                    Back to today
                  </button>
                </>
              )}
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </>
  );
}

export default DailyQuestion;
