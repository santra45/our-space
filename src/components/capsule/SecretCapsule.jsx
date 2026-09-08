/**
 * src/components/capsule/SecretCapsule.jsx
 * Time-locked love letters and digital time capsule.
 *
 * Schema v2: only `id`, `updatedAt` and `deleted` stay in plaintext on disk.
 * `unlockDate`, `isOpened`, `title` and the body all live inside the encrypted
 * record envelope, so none of them are indexed any more - every filter and sort
 * in this file happens in memory, after decryptRecord().
 *
 * The time lock is a real key wrap, not a UI check. A sealed letter's body is
 * encrypted under a random content key that is itself wrapped under a key
 * derived from the vault key AND the unlock date (crypto.sealTimeLocked). The
 * plaintext is never present in the record, so there is no `if (!locked)` branch
 * left to skip - reaching the body requires unsealTimeLocked(), which refuses
 * before the date, and editing the stored date breaks decryption outright rather
 * than bypassing a check.
 *
 * The honest limit, stated the same way in the UI and the README: this is not a
 * vault against its own owner. Everything needed to re-derive the wrapping key
 * sits on the device from the moment the letter is written, so anyone holding
 * the vault passphrase - either partner - can open a sealed letter early by
 * moving their device clock forward. It defeats accidents, curiosity and
 * tampering with the stored data. It does not defeat determination.
 */
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

/** How often the locked/unlocked split is recomputed while letters are pending. */
const LOCK_TICK_MS = 30000;

/** How long a transient banner stays on screen. */
const NOTICE_TTL_MS = 7000;

/**
 * How many times one letter may be re-sealed in a single session.
 *
 * The retro-seal pass below re-tries a row whose seal did not survive to disk,
 * and each successful write wakes useLiveQuery, which re-runs the pass. Without
 * a ceiling, a row that is being clobbered on every attempt would spin the
 * crypto and the database forever. Three is enough to beat the one racing writer
 * that actually exists (the v1 -> v2 migration, which touches each row once) and
 * small enough that a pathological loop stops on its own.
 */
const MAX_SEAL_UPGRADE_ATTEMPTS = 3;

/**
 * Today as the date input sees it: LOCAL calendar day, never toISOString().
 * @returns {string} 'YYYY-MM-DD'
 */
function localTodayIso() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/**
 * Coerces any stored unlock date to the bare local calendar day it was meant to be.
 *
 * Letters written by older builds stored `new Date('YYYY-MM-DD').toISOString()`,
 * i.e. UTC midnight of the day the writer picked on a LOCAL date input. Reading
 * the UTC components back recovers exactly that calendar day; reading local ones
 * would shift it by a day for most of the planet.
 *
 * @param {string|null|undefined} value
 * @returns {string|null} 'YYYY-MM-DD', or null when there is no usable date.
 */
function normalizeUnlockDate(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString().slice(0, 10);
}

/**
 * Collision-resistant record id. `'let-' + Date.now()` alone loses a letter when
 * both devices write inside the same millisecond and sync picks one.
 */
function newLetterId() {
  return `let-${Date.now().toString(36)}-${generateUrlSafeNonce(6)}`;
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

/** Monotonic write stamp, so a skewed device clock cannot permanently win or lose. */
function nextTimestamp() {
  try {
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

export function SecretCapsule() {
  const { cryptoKey } = useVault();
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

  // Raw rows only, purely for liveness. Everything meaningful is encrypted, so
  // the query cannot filter or sort - that happens below, after decryption.
  const storedLetters = useLiveQuery(() => db.letters.toArray(), []);

  const decryptCache = useRef(new Map());

  /** id -> how many seal writes have been ATTEMPTED for it this session. */
  const upgradeAttempts = useRef(new Map());

  /**
   * Ids currently being sealed. The effect re-runs on every `records` change,
   * including the one its own write causes, so without this a second pass would
   * start sealing a row the first pass is still awaiting. Worst case if it ever
   * misses is a duplicate but equivalent envelope, resolved by last-write-wins.
   */
  const sealInFlight = useRef(new Set());

  const today = useMemo(() => localTodayIso(), []);

  /* --------------------------------------------------------------------- *
   * Decrypt pass
   * --------------------------------------------------------------------- */

  useEffect(() => {
    // A different key invalidates every cached plaintext.
    decryptCache.current = new Map();
    upgradeAttempts.current = new Map();
    // sealInFlight is deliberately NOT reset: its entries are removed in a
    // `finally`, and clearing it out from under a seal that is still awaiting
    // would let a second pass start on the same row.
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

        // The IV changes on every re-encryption, so this key is stable exactly
        // as long as the stored bytes are - useLiveQuery hands back fresh object
        // identities on every write, and without this every letter would be
        // re-decrypted whenever any letter changed.
        const fingerprint = row.iv || row.contentIv || row.titleIv || '';
        const cacheKey = `${row.id}::${row.updatedAt}::${fingerprint}`;
        seen.add(cacheKey);

        let record = cache.get(cacheKey);
        if (!record) {
          let decrypted;
          try {
            // The table is REQUIRED here. Without it decryptRecord has no expected
            // table to compare the sealed `_tbl` against, so a row sealed for a
            // different one is never flagged and renders as ordinary content.
            decrypted = await decryptRecord(row, cryptoKey, { table: 'letters' });
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
      setRecords(next);
      setSkippedCount(skipped);
    }

    decryptAll();
    return () => {
      active = false;
    };
  }, [storedLetters, cryptoKey]);

  /* --------------------------------------------------------------------- *
   * Retro-seal pass
   * --------------------------------------------------------------------- */

  /**
   * Letters written before real time locks (and letters carried through the v1
   * -> v2 migration, which cannot re-shape content it has no key for) hold their
   * body as ordinary text inside the envelope, guarded only by a clock check.
   * Any of those that are still pending get sealed properly here.
   *
   * THIS PASS HAS A COMPETITOR AND MUST ASSUME IT LOSES.
   * db.migrateLegacyRecords() is started un-awaited the moment the vault unlocks
   * (VaultContext), and it rewrites these exact rows: it reads a row, decrypts
   * it, and bulkPuts a re-sealed copy some time later. If it read a letter
   * BEFORE this pass sealed it and its batch lands AFTER, the sealed envelope is
   * silently replaced by the plaintext-in-envelope body - and the UI goes on
   * calling that letter "key-wrapped". Three things stop that here:
   *
   *   1. RE-READ    `records` is a snapshot that may already be stale, so the
   *                 row is read and re-checked from disk immediately before the
   *                 write, and the seal is built from THAT copy.
   *   2. DEFER      a row the migration has not converted yet is left alone for
   *                 one write cycle rather than raced. Its own bulkPut wakes
   *                 useLiveQuery and this pass runs again against a v2 row.
   *   3. VERIFY     after writing, the row is read back. If the seal is not
   *                 there, the attempt is not treated as done and may retry.
   *
   * The rewrite no longer preserves updatedAt. Keeping it was what made the race
   * unrecoverable: two devices ended up with differing-but-equivalent rows at
   * EQUAL timestamps, and peerSync._diffManifest only ever requests strictly
   * newer records, so a device that lost its seal could never be repaired from
   * its partner. Bumping the stamp costs one extra sync of a letter body and one
   * possible flap between two equally valid seals. That is the right trade: the
   * alternative is a letter that stays unsealed forever while the app claims
   * otherwise.
   */
  useEffect(() => {
    if (!cryptoKey || records.length === 0) return undefined;
    let active = true;

    /**
     * Seals exactly one letter, from the row as it stands on disk right now.
     * Writes nothing unless the fresh copy still needs it.
     *
     * @param {string} id
     * @returns {Promise<'sealed'|'deferred'|'skipped'|'failed'>}
     */
    async function sealOnePendingLock(id) {
      const stored = await db.getDecrypted('letters', id, cryptoKey);
      if (!stored) return 'skipped';
      // Never resurrect a tombstone, never rewrite a record whose plaintext
      // header a peer has edited, and never re-seal what is already sealed.
      if (stored.deleted === true) return 'skipped';
      if (stored._headerTampered === true) return 'skipped';
      if (stored.sealedContent) return 'skipped';
      if (typeof stored.content !== 'string' || stored.content.length === 0) return 'skipped';

      // Still a v1 row: the legacy migration owns it and is very likely holding
      // a pre-seal copy of it in a pending bulkPut. Waiting one cycle is free;
      // writing now is a coin flip whose losing side destroys the seal.
      //
      // If the migration never finishes (it throws, and VaultContext turns that
      // into a warning), this letter is simply not upgraded this session - it
      // stays exactly as it was, fully readable, and the next unlock tries
      // again. Choosing that over racing is choosing safety over convenience:
      // an un-upgraded letter loses nothing, a lost seal loses the lock while
      // the UI keeps promising it.
      if (stored._needsReencrypt === true) return 'deferred';

      const lockDate = normalizeUnlockDate(stored.unlockDate);
      if (!lockDate) return 'skipped';
      if (isTimeLockOpen(lockDate)) return 'skipped'; // already readable, nothing left to protect

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

      // The migration's batch can still land between the read above and this
      // write. Read back rather than trusting the put: reporting a letter as
      // key-wrapped when the body is sitting in the envelope in plain text is
      // exactly the failure this whole pass exists to prevent.
      const confirmed = await db.getDecrypted('letters', id, cryptoKey);
      if (!confirmed || !confirmed.sealedContent) return 'failed';

      // Now that updatedAt moved, the partner can actually converge on this.
      // Best-effort: a manifest diff picks it up on the next connection anyway.
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
        if (isTimeLockOpen(lockDate)) continue; // already readable, nothing left to protect

        const id = record.id;
        if (sealInFlight.current.has(id)) continue;
        if ((upgradeAttempts.current.get(id) || 0) >= MAX_SEAL_UPGRADE_ATTEMPTS) continue;

        sealInFlight.current.add(id);
        let outcome;
        try {
          outcome = await sealOnePendingLock(id);
        } catch {
          // Leave the record exactly as it was; it stays readable the old way.
          outcome = 'failed';
        } finally {
          sealInFlight.current.delete(id);
        }

        // Only a real write attempt burns an attempt. A 'deferred' row never got
        // as far as a write, so counting it would strand the letter unsealed for
        // the rest of the session for no reason; a 'skipped' row needed nothing.
        // A 'sealed' row IS counted, so that if its seal is clobbered after the
        // read-back the retries are bounded instead of endless.
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

  /* --------------------------------------------------------------------- *
   * In-memory filter / sort
   * --------------------------------------------------------------------- */

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

  /* --------------------------------------------------------------------- *
   * Actions
   * --------------------------------------------------------------------- */

  const handleOpenLetter = useCallback(
    async (letter) => {
      if (!cryptoKey || openingId) return;
      tap();
      setNotice(null);

      // A date-locked letter is one of TWO different things, and saying the
      // stronger one about the weaker one is a lie the user cannot check.
      //
      //   isSealed  - the body is wrapped under a sub-key derived from the
      //               unlock date and the record id. Nothing here can re-derive
      //               it before that date; the clock is not what stops you.
      //   !isSealed - the body is plaintext inside the ordinary vault envelope
      //               and only this app's date check hides it. That is the state
      //               a letter is in when the retro-seal pass deferred it (the
      //               legacy migration never finished) or gave up after
      //               MAX_SEAL_UPGRADE_ATTEMPTS.
      //
      // The list badge already only says "key-wrapped" for the sealed case; this
      // banner used to claim the key wrap for both.
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

  /** Records that the seal has actually been broken, and replicates that. */
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
        // Purely cosmetic bookkeeping - never block the reader over it.
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

      // A sealed letter stores ONLY the wrapped envelope - the body never sits
      // in the record in a form the app can read before the date.
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
        'Delete this love letter? It goes from your phone and your partner’s, for good.'
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

  /* --------------------------------------------------------------------- *
   * Render
   * --------------------------------------------------------------------- */

  return (
    <div className="space-y-4">
      {/* Header bar */}
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

      {/* Transient banner: lock refusals and real failures */}
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

      {/* Letters List */}
      {isLoading ? (
        <div className="text-center py-16 text-xs text-slate-400">Unsealing your letters...</div>
      ) : letters.length === 0 ? (
        <div className="text-center py-16 px-4 bg-white/50 rounded-3xl border-2 border-dashed border-blush-200">
          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-blush-100 text-blush-400 flex items-center justify-center">
            <Mail className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-slate-700">No Letters Yet</h3>
          <p className="text-xs text-slate-500 max-w-xs mx-auto mt-1 mb-5">
            Leave a surprise letter for your partner, or seal a time capsule to open on your next
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

      {/* Reading modal */}
      {activeReadingLetter && (
        <LetterEnvelope
          letter={activeReadingLetter}
          onClose={() => setActiveReadingLetter(null)}
          onOpened={() => handleLetterOpened(activeReadingLetter.id)}
          onDelete={() => handleDeleteLetter(null, activeReadingLetter.id)}
        />
      )}

      {/* Write Letter Modal */}
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

              {/* Honesty box - this wording must match the README's threat model */}
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
