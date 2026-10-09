import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import {
  Mail,
  MailOpen,
  Lock,
  Plus,
  Clock,
  Sparkles,
  X,
  Heart,
  Trash2,
  ShieldAlert,
  Info,
} from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import { usePeople } from '../../context/PeopleContext';
import {
  decryptRecord,
  generateUrlSafeNonce,
  isTimeLockOpen,
  sealTimeLocked,
  unsealTimeLocked,
  TimeLockedError,
} from '../../services/crypto';
import peerSync from '../../services/peerSync';
import { formatTimeRemaining, formatDatePretty } from '../../utils/dateHelpers';
import LetterEnvelope from './LetterEnvelope';
import BouncyButton from '../common/BouncyButton';
import GlassCard from '../common/GlassCard';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

const LOCK_TICK_MS = 30000;

const NOTICE_TTL_MS = 7000;

const MAX_SEAL_UPGRADE_ATTEMPTS = 3;

function localTodayIso() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function normalizeUnlockDate(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString().slice(0, 10);
}

function newLetterId() {
  return `let-${Date.now().toString(36)}-${generateUrlSafeNonce(6)}`;
}

function stripInternalFields(record) {
  const out = {};
  for (const [field, value] of Object.entries(record)) {
    if (field.startsWith('_')) continue;
    out[field] = value;
  }
  return out;
}

function nextTimestamp() {
  try {
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

export function SecretCapsule() {
  const { cryptoKey } = useVault();
  const { partnerName, partnerPossessive } = usePeople();
  const [isWriteModalOpen, setIsWriteModalOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [unlockDate, setUnlockDate] = useState('');
  const [activeReadingLetter, setActiveReadingLetter] = useState(null);
  const [openingId, setOpeningId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState('');
  const [notice, setNotice] = useState(null);
  const [records, setRecords] = useState([]);
  const [skippedCount, setSkippedCount] = useState(0);
  const [nowTick, setNowTick] = useState(() => Date.now());
  const { tap, celebration } = useHaptics();

  const storedLetters = useLiveQuery(() => db.letters.toArray(), []);

  const decryptCache = useRef(new Map());

  const upgradeAttempts = useRef(new Map());

  const sealInFlight = useRef(new Set());

  const today = useMemo(() => localTodayIso(), []);

  useEffect(() => {
    decryptCache.current = new Map();
    upgradeAttempts.current = new Map();
  }, [cryptoKey]);

  useEffect(() => {
    let active = true;

    async function decryptAll() {
      if (!cryptoKey) {
        setRecords([]);
        setSkippedCount(0);
        return;
      }
      if (!storedLetters) return;

      const cache = decryptCache.current;
      const seen = new Set();
      const next = [];
      let skipped = 0;

      for (const row of storedLetters) {
        if (!row || typeof row !== 'object') continue;
        if (row.deleted === true) continue;

        const fingerprint = row.iv || row.contentIv || row.titleIv || '';
        const cacheKey = `${row.id}::${row.updatedAt}::${fingerprint}`;
        seen.add(cacheKey);

        let record = cache.get(cacheKey);
        if (!record) {
          let decrypted;
          try {
            decrypted = await decryptRecord(row, cryptoKey, { table: 'letters' });
          } catch {
            skipped += 1;
            continue;
          }
          if (decrypted._headerTampered) {
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
      setRecords(next);
      setSkippedCount(skipped);
    }

    decryptAll();
    return () => {
      active = false;
    };
  }, [storedLetters, cryptoKey]);

  useEffect(() => {
    if (!cryptoKey || records.length === 0) return undefined;
    let active = true;

    async function sealOnePendingLock(id) {
      const stored = await db.getDecrypted('letters', id, cryptoKey);
      if (!stored) return 'skipped';
      if (stored.deleted === true) return 'skipped';
      if (stored._headerTampered === true) return 'skipped';
      if (stored.sealedContent) return 'skipped';
      if (typeof stored.content !== 'string' || stored.content.length === 0) return 'skipped';

      const lockDate = normalizeUnlockDate(stored.unlockDate);
      if (!lockDate) return 'skipped';
      if (isTimeLockOpen(lockDate)) return 'skipped';

      const sealedContent = await sealTimeLocked(stored.content, lockDate, cryptoKey, {
        context: id,
      });

      const row = await db.putEncrypted(
        'letters',
        {
          ...stripInternalFields(stored),
          unlockDate: lockDate,
          sealedContent,
          content: undefined,
          updatedAt: nextTimestamp(),
        },
        cryptoKey
      );

      const confirmed = await db.getDecrypted('letters', id, cryptoKey);
      if (!confirmed || !confirmed.sealedContent) return 'failed';

      await peerSync.broadcastLiveRecord('letters', row);
      return 'sealed';
    }

    async function upgradePendingLocks() {
      for (const record of records) {
        if (!active) return;
        if (record.sealedContent) continue;
        if (typeof record.content !== 'string' || record.content.length === 0) continue;

        const lockDate = normalizeUnlockDate(record.unlockDate);
        if (!lockDate) continue;
        if (isTimeLockOpen(lockDate)) continue;

        const id = record.id;
        if (sealInFlight.current.has(id)) continue;
        if ((upgradeAttempts.current.get(id) || 0) >= MAX_SEAL_UPGRADE_ATTEMPTS) continue;

        sealInFlight.current.add(id);
        let outcome;
        try {
          outcome = await sealOnePendingLock(id);
        } catch {
          outcome = 'failed';
        } finally {
          sealInFlight.current.delete(id);
        }

        if (outcome === 'sealed' || outcome === 'failed') {
          upgradeAttempts.current.set(id, (upgradeAttempts.current.get(id) || 0) + 1);
        }
      }
    }

    upgradePendingLocks();
    return () => {
      active = false;
    };
  }, [records, cryptoKey]);

  const letters = useMemo(() => {
    return records
      .map((record) => {
        const lockDate = normalizeUnlockDate(record.unlockDate);
        return {
          ...record,
          lockDate,
          isLocked: lockDate ? !isTimeLockOpen(lockDate, nowTick) : false,
          isSealed: Boolean(record.sealedContent),
          writtenAt: Number.isFinite(record.createdAt) ? record.createdAt : record.updatedAt,
        };
      })
      .sort((a, b) => (b.writtenAt || 0) - (a.writtenAt || 0));
  }, [records, nowTick]);

  const hasPendingLocks = useMemo(() => letters.some((letter) => letter.isLocked), [letters]);

  useEffect(() => {
    if (!hasPendingLocks) return undefined;
    const timer = setInterval(() => setNowTick(Date.now()), LOCK_TICK_MS);
    return () => clearInterval(timer);
  }, [hasPendingLocks]);

  useEffect(() => {
    if (!notice) return undefined;
    const timer = setTimeout(() => setNotice(null), NOTICE_TTL_MS);
    return () => clearTimeout(timer);
  }, [notice]);

  const handleOpenLetter = useCallback(
    async (letter) => {
      if (!cryptoKey || openingId) return;
      tap();
      setNotice(null);

      if (letter.isLocked) {
        const until = `${formatDatePretty(letter.lockDate)} - ${formatTimeRemaining(letter.lockDate)}`;
        setNotice({
          tone: 'lock',
          text: letter.isSealed
            ? `"${letter.title}" is sealed until ${until} 💕 We will not open it early.`
            : `"${letter.title}" stays shut until ${until} 💕 We are still tucking this one away properly — it will be sealed the next time this screen can.`,
        });
        return;
      }

      if (!letter.isSealed) {
        setActiveReadingLetter({
          ...letter,
          content: typeof letter.content === 'string' ? letter.content : '',
        });
        return;
      }

      setOpeningId(letter.id);
      try {
        const body = await unsealTimeLocked(letter.sealedContent, cryptoKey, {
          context: letter.id,
        });
        setActiveReadingLetter({ ...letter, content: body });
      } catch (err) {
        if (err instanceof TimeLockedError) {
          setNowTick(Date.now());
          setNotice({
            tone: 'lock',
            text: `Still sealed until ${formatDatePretty(err.unlockDate)}.`,
          });
        } else {
          setNotice({
            tone: 'error',
            text: 'We could not open this letter. Something about it changed, so it cannot be read any more.',
          });
        }
      } finally {
        setOpeningId(null);
      }
    },
    [cryptoKey, openingId, tap]
  );

  const handleLetterOpened = useCallback(
    async (letterId) => {
      if (!cryptoKey || !letterId) return;
      try {
        const stored = await db.getDecrypted('letters', letterId, cryptoKey);
        if (!stored || stored.deleted === true || stored.isOpened === true) return;
        const row = await db.putEncrypted(
          'letters',
          {
            ...stripInternalFields(stored),
            isOpened: true,
            openedAt: Date.now(),
            updatedAt: nextTimestamp(),
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('letters', row);
      } catch {
      }
    },
    [cryptoKey]
  );

  const handleSaveLetter = async (e) => {
    e.preventDefault();
    const trimmedTitle = title.trim();
    const trimmedContent = content.trim();
    if (!trimmedTitle || !trimmedContent || !cryptoKey || saving) return;

    setSaveError('');
    try {
      setSaving(true);
      tap();

      const id = newLetterId();
      const lockDate = normalizeUnlockDate(unlockDate);
      const base = {
        id,
        title: trimmedTitle,
        unlockDate: lockDate,
        isOpened: false,
        createdAt: Date.now(),
        updatedAt: nextTimestamp(),
        deleted: false,
      };

      const record = lockDate
        ? {
            ...base,
            sealedContent: await sealTimeLocked(trimmedContent, lockDate, cryptoKey, {
              context: id,
            }),
          }
        : { ...base, content: trimmedContent };

      const row = await db.putEncrypted('letters', record, cryptoKey);
      peerSync.broadcastLiveRecord('letters', row);

      celebration();
      fireHeartConfetti();
      setTitle('');
      setContent('');
      setUnlockDate('');
      setIsWriteModalOpen(false);
    } catch {
      setSaveError('Could not seal this letter. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteLetter = async (e, id) => {
    if (e) e.stopPropagation();
    if (
      !window.confirm(
        `Delete this love letter? It goes from your phone and ${partnerPossessive}, for good.`
      )
    ) {
      return;
    }
    tap();
    try {
      const row = await db.softDelete('letters', id, cryptoKey);
      if (row) peerSync.broadcastLiveRecord('letters', row);
    } catch {
      setNotice({ tone: 'error', text: 'Could not delete that letter. Please try again.' });
    }
    if (activeReadingLetter?.id === id) {
      setActiveReadingLetter(null);
    }
  };

  const isLoading = Boolean(cryptoKey) && storedLetters === undefined;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between px-1">
        <div>
          <h2 className="text-xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
            <span>Secret Capsule</span>
            <Sparkles className="w-4 h-4 text-amber-500" />
          </h2>
          <p className="text-xs text-slate-500">Time-locked letters &amp; sweet notes</p>
        </div>

        <BouncyButton
          onClick={() => {
            tap();
            setSaveError('');
            setIsWriteModalOpen(true);
          }}
          className="py-2 px-3.5 text-xs gap-1.5 rounded-full"
        >
          <Plus className="w-4 h-4" />
          <span>Write Letter</span>
        </BouncyButton>
      </div>

      {notice && (
        <div
          className={`flex items-start gap-2 px-3.5 py-2.5 rounded-2xl text-[11px] leading-relaxed border ${
            notice.tone === 'error'
              ? 'bg-rose-50 border-rose-200 text-rose-700'
              : 'bg-slate-50 border-slate-200 text-slate-600'
          }`}
        >
          {notice.tone === 'error' ? (
            <ShieldAlert className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" />
          ) : (
            <Lock className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" />
          )}
          <span className="flex-1">{notice.text}</span>
          <button
            type="button"
            onClick={() => setNotice(null)}
            className="text-current opacity-50 hover:opacity-100"
            aria-label="Dismiss"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {skippedCount > 0 && (
        <div className="flex items-start gap-2 px-3.5 py-2.5 rounded-2xl text-[11px] leading-relaxed bg-amber-50 border border-amber-200 text-amber-800">
          <ShieldAlert className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" />
          <span>
            {skippedCount} letter{skippedCount === 1 ? '' : 's'} could not be opened with your
            passphrase, so {skippedCount === 1 ? 'it is' : 'they are'} hidden for now.
          </span>
        </div>
      )}

      {isLoading ? (
        <div className="text-center py-16 text-xs text-slate-400">Unsealing your letters...</div>
      ) : letters.length === 0 ? (
        <div className="text-center py-16 px-4 bg-white/50 rounded-3xl border-2 border-dashed border-blush-200">
          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-blush-100 text-blush-400 flex items-center justify-center">
            <Mail className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-slate-700">No Letters Yet</h3>
          <p className="text-xs text-slate-500 max-w-xs mx-auto mt-1 mb-5">
            Leave a surprise letter for {partnerName}, or seal a time capsule to open on your next
            anniversary!
          </p>
          <BouncyButton
            onClick={() => setIsWriteModalOpen(true)}
            className="text-xs py-2.5 px-5 rounded-full"
          >
            Write First Love Letter 💌
          </BouncyButton>
        </div>
      ) : (
        <div className="space-y-3">
          {letters.map((letter) => (
            <GlassCard
              key={letter.id}
              hoverEffect={!letter.isLocked}
              onClick={() => handleOpenLetter(letter)}
              className={`p-4 transition cursor-pointer border ${
                letter.isLocked
                  ? 'bg-slate-50/70 border-slate-200 opacity-80'
                  : 'bg-white/80 border-blush-100 hover:border-blush-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3 flex-1 min-w-0 pr-2">
                  <div
                    className={`w-10 h-10 rounded-2xl flex items-center justify-center shadow-sm flex-shrink-0 ${
                      letter.isLocked
                        ? 'bg-slate-200 text-slate-500'
                        : 'bg-blush-100 text-blush-600'
                    }`}
                  >
                    {letter.isLocked ? (
                      <Lock className="w-5 h-5" />
                    ) : letter.isOpened ? (
                      <MailOpen className="w-5 h-5" />
                    ) : (
                      <Mail className="w-5 h-5" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <h4 className="text-sm font-bold text-slate-800 truncate">{letter.title}</h4>
                    <p className="text-[11px] text-slate-400">
                      Written on {formatDatePretty(letter.writtenAt)}
                      {letter.isLocked && letter.isSealed ? ' · sealed' : ''}
                      {!letter.isLocked && letter.isOpened ? ' · already opened' : ''}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-2 flex-shrink-0">
                  {letter.isLocked ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-slate-200/80 text-slate-600 text-[10px] font-bold">
                      <Clock className="w-3 h-3" />
                      <span>{formatTimeRemaining(letter.lockDate)}</span>
                    </div>
                  ) : (
                    <span className="text-xs font-semibold text-blush-600 hover:underline">
                      {openingId === letter.id ? 'Unsealing...' : 'Read Letter 💌'}
                    </span>
                  )}
                  <button
                    type="button"
                    onClick={(e) => handleDeleteLetter(e, letter.id)}
                    className="w-8 h-8 rounded-xl flex items-center justify-center text-slate-300 hover:text-rose-500 hover:bg-rose-50 transition ml-1"
                    title="Delete love letter"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            </GlassCard>
          ))}
        </div>
      )}

      {activeReadingLetter && (
        <LetterEnvelope
          letter={activeReadingLetter}
          onClose={() => setActiveReadingLetter(null)}
          onOpened={() => handleLetterOpened(activeReadingLetter.id)}
          onDelete={() => handleDeleteLetter(null, activeReadingLetter.id)}
        />
      )}

      {isWriteModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 relative max-h-[90vh] overflow-y-auto"
          >
            <button
              onClick={() => setIsWriteModalOpen(false)}
              className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
            >
              <X className="w-4 h-4" />
            </button>

            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 rounded-full bg-blush-100 text-blush-500 flex items-center justify-center">
                <Heart className="w-4 h-4 fill-blush-400" />
              </div>
              <div>
                <h3 className="text-base font-bold text-slate-800">Write Love Letter</h3>
                <p className="text-[11px] text-slate-400">
                  Only the two of you can read it
                </p>
              </div>
            </div>

            <form onSubmit={handleSaveLetter} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Title / Prompt
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. Open when you miss me, or 1st Anniversary"
                  required
                  maxLength={120}
                  className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
                <p className="text-[10px] text-slate-400 mt-0.5">
                  The title still shows while it is sealed — only the letter itself is hidden.
                </p>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Letter Body
                </label>
                <textarea
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  placeholder="Write your heart out..."
                  required
                  rows={6}
                  className="w-full px-3 py-2 font-handwriting text-lg bg-amber-50/30 border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Time-Lock Until (Optional)
                </label>
                <input
                  type="date"
                  value={unlockDate}
                  min={today}
                  onChange={(e) => setUnlockDate(e.target.value)}
                  className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
                <p className="text-[10px] text-slate-400 mt-0.5">
                  Leave blank to allow opening immediately. A locked letter opens at 00:00 local
                  time on the chosen day.
                </p>
              </div>

              <div className="flex items-start gap-2 px-3 py-2.5 rounded-2xl bg-slate-50 border border-slate-200 text-[10px] leading-relaxed text-slate-600">
                <Info className="w-3.5 h-3.5 mt-0.5 flex-shrink-0 text-slate-400" />
                <p>
                  The app will not open a sealed letter early — though anyone who knows your
                  passphrase and changes their phone&apos;s date could. It is a promise, not a
                  padlock. 💕
                </p>
              </div>

              {saveError && (
                <p className="text-[11px] font-semibold text-rose-600 text-center">{saveError}</p>
              )}

              <BouncyButton
                type="submit"
                disabled={saving || !title.trim() || !content.trim()}
                className="w-full py-3 text-sm font-bold shadow-md shadow-blush-300/40"
              >
                {saving
                  ? unlockDate
                    ? 'Sealing…'
                    : 'Tucking it away…'
                  : unlockDate
                    ? 'Seal Until ' + formatDatePretty(unlockDate) + ' 🔒'
                    : 'Seal with Wax Stamp 💌'}
              </BouncyButton>
            </form>
          </motion.div>
        </div>
      )}
    </div>
  );
}

export default SecretCapsule;
