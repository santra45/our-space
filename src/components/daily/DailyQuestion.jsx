import React, { useCallback, useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { MessageCircleHeart, X, Lock, Check, History } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { usePeople } from '../../context/PeopleContext';
import { useHaptics } from '../../hooks/useHaptics';
import { getDeviceId } from '../../services/deviceId';
import peerSync from '../../services/peerSync';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import {
  ANSWER_TABLE,
  MAX_ANSWER_LENGTH,
  dateFromDayKey,
  getQuestionForDay,
  saveAnswer,
  readDay,
  listArchive,
} from '../../services/dailyQuestion';

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

function AnswerForm({ draft, onDraft, onSubmit, saving, error, hint, footer }) {
  return (
    <form onSubmit={onSubmit} className="space-y-3">
      {hint}

      <textarea
        value={draft}
        onChange={(e) => onDraft(e.target.value)}
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

      {footer}
    </form>
  );
}

export function DailyQuestion() {
  const { cryptoKey } = useVault();
  const { myOwnerId, myOwnerIds, partnerName, partnerPossessive, partnerGrammar } = usePeople();
  const { tap, celebration } = useHaptics();

  const [today, setToday] = useState(null);
  const [state, setState] = useState(null);
  const [isOpen, setIsOpen] = useState(false);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [showArchive, setShowArchive] = useState(false);
  const [archive, setArchive] = useState([]);
  const [catchUp, setCatchUp] = useState(null);

  const ownerId = myOwnerId || getDeviceId();
  const ownerIds = myOwnerIds;

  const refresh = useCallback(async () => {
    if (!cryptoKey) return;
    try {
      const question = await getQuestionForDay(cryptoKey);
      const day = await readDay({ cryptoKey, ownerId, ownerIds });
      setToday(question);
      setState(day);
    } catch {
      setToday(null);
    }
  }, [cryptoKey, ownerId, ownerIds]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    const onUpdate = () => refresh();
    peerSync.on('data-updated', onUpdate);
    return () => peerSync.off('data-updated', onUpdate);
  }, [refresh]);

  const loadArchive = useCallback(async () => {
    try {
      setArchive(await listArchive({ cryptoKey, ownerId, ownerIds, limit: 120 }));
    } catch {
      setArchive([]);
    }
  }, [cryptoKey, ownerId, ownerIds]);

  const handleSave = async (e) => {
    e.preventDefault();
    const target = catchUp || (today && { day: today.day, question: today.question });
    if (saving || !draft.trim() || !target) return;

    setSaving(true);
    setError('');
    try {
      const row = await saveAnswer({
        cryptoKey,
        ownerId,
        ownerIds,
        questionId: target.question.id,
        text: draft,
        when: catchUp ? dateFromDayKey(catchUp.day) : undefined,
        timestamp: () => peerSync.getSyncSafeTimestamp(),
      });
      peerSync.broadcastLiveRecord(ANSWER_TABLE, row);
      setDraft('');
      celebration();
      fireHeartConfetti();
      if (catchUp) {
        setCatchUp(null);
        await loadArchive();
      }
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
    await loadArchive();
  };

  if (!cryptoKey || !today) return null;

  const answered = !!(state && state.mine);
  const partnerWaiting = !!(state && state.partnerHasAnswered) && !answered;
  const bothIn = answered && !!(state && state.partnerAnswer);

  const writeVerb = partnerGrammar.has === 'have' ? 'write' : 'writes';

  return (
    <>
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
            ? `You both answered. Tap to read 💕`
            : answered
              ? `Answered. ${partnerPossessive} appears the moment ${partnerGrammar.subject} ${writeVerb} one.`
              : partnerWaiting
                ? `${partnerName} has already answered. Yours unlocks it 💕`
                : 'Tap to answer'}
        </p>
      </motion.button>

      {createPortal(
      <AnimatePresence>
        {isOpen && (
          <div className="fixed inset-0 z-[70] flex items-end sm:items-center justify-center p-0 sm:p-4 bg-slate-900/40 backdrop-blur-sm">
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
                  setCatchUp(null);
                }}
                className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
              >
                <X className="w-4 h-4" />
              </button>

              {catchUp ? (
                <>
                  <p className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide mb-1">
                    {prettyDay(catchUp.day)}
                  </p>
                  <p className="font-handwriting text-2xl text-slate-800 leading-snug mb-4 pr-8">
                    {catchUp.question.text}
                  </p>

                  <AnswerForm
                    draft={draft}
                    onDraft={setDraft}
                    onSubmit={handleSave}
                    saving={saving}
                    error={error}
                    hint={
                      <div className="flex items-start gap-2 p-2.5 rounded-2xl bg-lavender-50 border border-lavender-100">
                        <Lock className="w-4 h-4 text-lavender-400 shrink-0 mt-0.5" />
                        <p className="text-[11px] leading-relaxed text-lavender-700">
                          You did not answer this one at the time. Write it now and what
                          {partnerName} wrote that day opens.
                        </p>
                      </div>
                    }
                    footer={
                      <button
                        type="button"
                        onClick={() => {
                          tap();
                          setCatchUp(null);
                          setDraft('');
                          setError('');
                        }}
                        className="w-full text-[11px] font-bold text-slate-400 hover:text-slate-600"
                      >
                        Back to the archive
                      </button>
                    }
                  />
                </>
              ) : !showArchive ? (
                <>
                  <p className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide mb-1">
                    {prettyDay(today.day)}
                  </p>
                  <p className="font-handwriting text-2xl text-slate-800 leading-snug mb-4 pr-8">
                    {today.question.text}
                  </p>

                  {!answered ? (
                    <AnswerForm
                      draft={draft}
                      onDraft={setDraft}
                      onSubmit={handleSave}
                      saving={saving}
                      error={error}
                      hint={
                        partnerWaiting ? (
                          <div className="flex items-start gap-2 p-2.5 rounded-2xl bg-lavender-50 border border-lavender-100">
                            <Lock className="w-4 h-4 text-lavender-400 shrink-0 mt-0.5" />
                            <p className="text-[11px] leading-relaxed text-lavender-700">
                              {partnerName} has answered already. Write yours and you will
                              both be able to read them.
                            </p>
                          </div>
                        ) : null
                      }
                      footer={
                        <p className="text-[10px] text-slate-400 text-center leading-relaxed">
                          You will not see {partnerPossessive} until you have written yours.
                        </p>
                      }
                    />
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
                            {partnerName}
                          </p>
                          <p className="text-sm text-slate-700 leading-relaxed whitespace-pre-wrap">
                            {state.partnerAnswer.text}
                          </p>
                        </div>
                      ) : (
                        <div className="p-3 rounded-2xl bg-slate-50 border border-slate-100 text-center">
                          <p className="text-[11px] text-slate-500 leading-relaxed">
                            Nothing from {partnerName} yet today. It will appear here on its own.
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
                    <span>Everything you have both written</span>
                  </button>
                </>
              ) : (
                <>
                  <p className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide mb-3">
                    Every day so far
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

                          {entry.missed ? (
                            <button
                              type="button"
                              onClick={() => {
                                tap();
                                setDraft('');
                                setError('');
                                setCatchUp({
                                  day: entry.day,
                                  question: entry.question || { id: null, text: '' },
                                });
                              }}
                              disabled={!entry.question}
                              className="w-full mt-1 p-2.5 rounded-2xl bg-lavender-50 border border-lavender-100 text-left flex items-start gap-2 hover:bg-lavender-100 transition-colors disabled:opacity-60 disabled:hover:bg-lavender-50"
                            >
                              <Lock className="w-3.5 h-3.5 text-lavender-400 shrink-0 mt-0.5" />
                              <span className="text-[11px] leading-relaxed text-lavender-700">
                                {entry.question
                                  ? `You missed this one, and something of ${partnerPossessive} is waiting behind it. Tap to answer it now 💕`
                                  : 'You missed this one. The question it was asking is no longer in the app.'}
                              </span>
                            </button>
                          ) : (
                            <>
                              <p className="text-[11px] text-slate-600 leading-relaxed whitespace-pre-wrap">
                                <span className="font-bold text-blush-500">You: </span>
                                {entry.mine.text}
                              </p>
                              {entry.theirs && (
                                <p className="text-[11px] text-slate-600 leading-relaxed whitespace-pre-wrap mt-1">
                                  <span className="font-bold text-lavender-500">{partnerName}: </span>
                                  {entry.theirs.text}
                                </p>
                              )}
                            </>
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
      </AnimatePresence>,
      document.body
      )}
    </>
  );
}

export default DailyQuestion;
