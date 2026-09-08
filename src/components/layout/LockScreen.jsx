/**
 * src/components/layout/LockScreen.jsx
 * Zero-knowledge vault unlock, partner pairing, and initial setup screen.
 *
 * THE FOOTGUN THIS SCREEN GUARDS
 * Two of the three forms here write a fresh salt to vaultMeta, which makes
 * every existing memory, letter, milestone and bucket item permanently
 * undecryptable. A returning user must therefore land on UNLOCK - never on
 * CREATE - and must not be able to reach either destructive form without
 * typing a confirmation phrase and being offered a rescue backup first.
 *
 * Mode is derived from `vaultCheckState`, which has FOUR values, not two.
 * 'checking' and 'unreadable' both render a non-destructive holding screen and
 * no form at all: a vault we cannot see is not a vault that is not there, and
 * offering CREATE VAULT on a read error is how a returning user gets walked into
 * erasing everything. 'unreadable' additionally names the usual cause - another
 * tab holding the old database schema open - and offers a retry.
 */
import React, { useState, useEffect, useMemo, useRef } from 'react';
import { motion } from 'framer-motion';
import {
  Heart,
  Lock,
  KeyRound,
  Sparkles,
  Eye,
  EyeOff,
  ShieldCheck,
  ShieldAlert,
  Users,
  Link2,
  UserCheck,
  Download,
  Upload,
  LifeBuoy,
  RefreshCw,
  CheckCircle2,
  AlertTriangle,
} from 'lucide-react';
import { useVault, DESTROY_CONFIRMATION_PHRASE, localDateString } from '../../context/VaultContext';
import {
  MIN_PASSPHRASE_LENGTH,
  normalizePassphrase,
  createEncryptedBackup,
  decryptBackupContainer,
} from '../../services/crypto';
import db, { MAX_BACKUP_FILE_BYTES, readBackupVaultIdentity } from '../../db';
import { parseInvite } from '../../utils/invite';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

/**
 * Restore failures, phrased so the user knows what to do next rather than what
 * threw. Keys are the `code` values returned by VaultContext.restoreVaultFromBackup.
 */
const RESTORE_ERRORS = {
  no_identity: 'This file is missing the part we need to rebuild your space here.',
  bad_salt: 'This file looks damaged, so we left everything as it is.',
  passphrase_too_short: `The passphrase needs at least ${MIN_PASSPHRASE_LENGTH} characters.`,
  passphrase_mismatch:
    'That is not the passphrase this file was saved with. Nothing changed. It is the one you used ' +
    'to open Our Space back when you saved it — not always the same one that opened the file.',
  unreadable:
    'We could not read what is already on this phone, so we stopped instead of risking it. Close ' +
    'any other tabs with Our Space open, then reload and try again.',
  same_vault:
    'This file is from this very phone, so there is nothing to swap. Just unlock as usual, then ' +
    'use Bring in a copy in the Sync Hub to add its things back.',
  needs_confirmation: 'Type the words above to replace what is on this phone.',
  write_failed: 'That stopped partway. Nothing more was written.',
};

/**
 * The blocking confirmation shown before anything replaces an existing vault.
 * Defined at module scope so React keeps its inputs mounted (and focused)
 * across the parent's re-renders.
 */
function DangerGate({
  headline,
  confirmText,
  onConfirmTextChange,
  isConfirmed,
  backupPassphrase,
  onBackupPassphraseChange,
  onDownloadBackup,
  backupBusy,
  backupDone,
  backupError,
}) {
  return (
    <div className="p-3.5 rounded-2xl bg-rose-50 border-2 border-rose-300 space-y-3">
      <div className="flex items-start gap-2">
        <ShieldAlert className="w-5 h-5 text-rose-600 flex-shrink-0 mt-0.5" />
        <div>
          <p className="text-xs font-extrabold text-rose-800 uppercase tracking-wide">
            This erases everything on this phone
          </p>
          <p className="text-[11px] text-rose-700 mt-1 leading-relaxed">
            {headline} Every photo, letter, milestone and wish saved here{' '}
            <strong>can never be opened again</strong>, and all of it is erased from this phone.
            There is no undo — not by us, not by anyone.
          </p>
          <p className="text-[11px] text-rose-700 mt-1.5 leading-relaxed">
            If you have only forgotten the passphrase, <strong>please stop here</strong>. Nothing on
            this screen can bring it back, and your partner&apos;s phone may still have everything.
          </p>
        </div>
      </div>

      {/* Rescue backup: the encrypted rows are still on disk, so let them out.
          The copy here is deliberately blunt about the TWO passphrases involved.
          It used to say this file was "the only way back" - while no code path
          in the app could write a salt back from a backup, so the file was in
          fact unrestorable. The restore flow now exists (mode 'restore' below),
          and this text describes exactly what it can and cannot do. */}
      <div className="p-2.5 rounded-xl bg-white/70 border border-rose-200 space-y-2">
        <p className="text-[11px] font-bold text-slate-700 flex items-center gap-1.5">
          <Download className="w-3.5 h-3.5 text-slate-500" />
          Save a copy first
        </p>
        <p className="text-[10px] text-slate-500 leading-relaxed">
          This saves everything on this phone into one file. To open it later you will need the
          passphrase you type below, and the one you open Our Space with today.
        </p>
        <input
          type="password"
          value={backupPassphrase}
          onChange={(e) => onBackupPassphraseChange(e.target.value)}
          placeholder={`Passphrase for this file (at least ${MIN_PASSPHRASE_LENGTH})`}
          minLength={MIN_PASSPHRASE_LENGTH}
          autoComplete="new-password"
          className="w-full px-3 py-2 bg-white border border-slate-200 rounded-xl text-slate-800 text-xs focus:outline-none focus:ring-2 focus:ring-slate-400 placeholder:text-slate-400"
        />
        <button
          type="button"
          onClick={onDownloadBackup}
          disabled={backupBusy}
          className="w-full py-2 rounded-xl bg-slate-800 text-white text-xs font-bold hover:bg-slate-900 disabled:opacity-50 transition"
        >
          {backupBusy ? 'Saving…' : 'Save a copy'}
        </button>
        {backupDone && (
          <p className="text-[10px] text-emerald-700 font-semibold flex items-center gap-1">
            <CheckCircle2 className="w-3 h-3" />
            Saved. That passphrase opens it. 💕
          </p>
        )}
        {backupError && (
          <p className="text-[10px] text-rose-600 font-semibold flex items-center gap-1">
            <AlertTriangle className="w-3 h-3" />
            {backupError}
          </p>
        )}
      </div>

      <div>
        <label className="block text-[11px] font-bold text-rose-800 mb-1">
          Type <span className="font-mono bg-rose-100 px-1 rounded">{DESTROY_CONFIRMATION_PHRASE}</span>{' '}
          to continue
        </label>
        <input
          type="text"
          value={confirmText}
          onChange={(e) => onConfirmTextChange(e.target.value)}
          placeholder={DESTROY_CONFIRMATION_PHRASE}
          autoCapitalize="characters"
          autoCorrect="off"
          spellCheck={false}
          className={`w-full px-3 py-2 bg-white border rounded-xl text-slate-800 text-xs font-mono tracking-wide focus:outline-none focus:ring-2 transition ${
            isConfirmed
              ? 'border-rose-400 focus:ring-rose-400'
              : 'border-slate-200 focus:ring-slate-400'
          }`}
        />
      </div>
    </div>
  );
}

/**
 * How long vaultCheckState may sit at 'checking' before the spinner explains itself.
 *
 * A blocked schema upgrade does NOT resolve to 'unreadable'. Dexie fires
 * on('blocked') but leaves the open request PENDING with no reject, so the
 * vaultMeta read never settles, checkVault never leaves 'checking', and the
 * blocked panel below - which lived only in the 'unreadable' branch - was
 * unreachable in precisely the case it was written for. A genuinely blocked user
 * watched "Looking for your vault…" forever and was never told to close the
 * other tab. So the guidance has to be reachable from 'checking' too.
 *
 * 6 seconds: opening IndexedDB and reading one row is single-digit milliseconds
 * on a warm start and tens of milliseconds on a phone waking from sleep, so this
 * is two orders of magnitude past normal - far too long to fire on a merely slow
 * device, short enough that a stuck user is not abandoned. The common block
 * self-resolves anyway (Dexie's default versionchange handler closes the other
 * tab's connection); a sustained one needs a frozen or non-Dexie holder, which
 * is rare enough that a time-based HINT is the honest shape here. It diagnoses
 * nothing, changes nothing, and the spinner keeps running underneath in case the
 * read does land.
 */
const CHECK_SLOW_MS = 6000;

export function LockScreen() {
  const {
    vaultCheckState,
    vaultCheckBlocked,
    retryVaultCheck,
    unlockVault,
    initializeVault,
    initializeFromPartnerInvite,
    restoreVaultFromBackup,
    vaultSalt,
    error: vaultError,
    clearError,
  } = useVault();

  const [passphrase, setPassphrase] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [coupleNames, setCoupleNames] = useState('');
  const [startDate, setStartDate] = useState(localDateString());
  const [partnerInviteInput, setPartnerInviteInput] = useState('');
  const [inviteData, setInviteData] = useState(null);
  const [mode, setMode] = useState('unlock'); // 'unlock' | 'setup' | 'join' | 'restore'
  const [loading, setLoading] = useState(false);
  const [localError, setLocalError] = useState(null);

  // Destructive-path confirmation state
  const [confirmText, setConfirmText] = useState('');
  const [backupPassphrase, setBackupPassphrase] = useState('');
  const [backupBusy, setBackupBusy] = useState(false);
  const [backupDone, setBackupDone] = useState(false);
  const [backupError, setBackupError] = useState(null);

  // Rescue-restore state. `restoreTables` holds the DECRYPTED container payload,
  // which is still fully encrypted at the record level - opening the file proves
  // nothing about the vault passphrase.
  const [restoreFileName, setRestoreFileName] = useState('');
  const [restoreContainer, setRestoreContainer] = useState(null);
  const [restoreFilePassphrase, setRestoreFilePassphrase] = useState('');
  const [restoreTables, setRestoreTables] = useState(null);
  const [restoreIdentity, setRestoreIdentity] = useState(null);
  const [restoreVaultPassphrase, setRestoreVaultPassphrase] = useState('');
  const [restoreBusy, setRestoreBusy] = useState(false);
  const [restoreError, setRestoreError] = useState(null);

  const { celebration, tap } = useHaptics();

  const isChecking = vaultCheckState === 'checking';
  const isUnreadable = vaultCheckState === 'unreadable';
  const hasVault = vaultCheckState === 'present';
  /** No form may be rendered until the vault question has an actual answer. */
  const canRenderForms = hasVault || vaultCheckState === 'absent';

  /** See CHECK_SLOW_MS: a blocked upgrade never leaves 'checking' on its own. */
  const [checkIsSlow, setCheckIsSlow] = useState(false);
  useEffect(() => {
    if (!isChecking) {
      setCheckIsSlow(false);
      return undefined;
    }
    const timer = setTimeout(() => setCheckIsSlow(true), CHECK_SLOW_MS);
    return () => clearTimeout(timer);
  }, [isChecking]);

  /** Once the user picks a form, the default-mode effect stops overriding them. */
  const modeTouched = useRef(false);

  /**
   * Switches form, wiping every error and confirmation from the previous one.
   * Leaving `restore` also drops the decrypted container from memory - it is the
   * whole vault in plaintext-envelope form and has no business outliving the
   * screen that needed it.
   */
  const switchMode = (next) => {
    tap();
    modeTouched.current = true;
    setMode(next);
    setLocalError(null);
    setConfirmText('');
    setBackupDone(false);
    setBackupError(null);
    if (next !== 'restore') resetRestoreState();
    clearError();
  };

  // Detect an invite link in the URL hash on mount and on hash change.
  useEffect(() => {
    const handleHash = () => {
      const invite = parseInvite(window.location.hash);
      if (invite && (invite.partnerPeerId || invite.salt)) {
        setInviteData(invite);
      }
    };

    handleHash();
    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, []);

  /**
   * Derive the default form from what we actually know.
   *
   * A device that already has a vault ALWAYS defaults to unlock, invite link or
   * not. Honouring `#salt=` here is how a crafted link used to drop an existing
   * user straight onto a form that replaced their salt: one tap, one passphrase,
   * whole vault orphaned. The link is remembered and applied after unlocking.
   */
  useEffect(() => {
    if (modeTouched.current) return;
    if (vaultCheckState === 'present') {
      setMode('unlock');
    } else if (vaultCheckState === 'absent') {
      setMode(inviteData && inviteData.salt ? 'join' : 'setup');
    }
    // 'checking' and 'unreadable' deliberately choose nothing.
  }, [vaultCheckState, inviteData]);

  /** The salt this join would adopt, as far as we can tell right now. */
  const pendingJoinSalt = useMemo(() => {
    if (inviteData && inviteData.salt) return inviteData.salt;
    if (!partnerInviteInput.trim()) return null;
    const parsed = parseInvite(partnerInviteInput);
    return (parsed && parsed.salt) || null;
  }, [inviteData, partnerInviteInput]);

  /** True when this join would adopt a DIFFERENT salt than the one on disk. */
  const joinReplacesVault = hasVault && pendingJoinSalt !== vaultSalt;
  /** True when a restore would replace a DIFFERENT vault already on this device. */
  const restoreReplacesVault = Boolean(
    hasVault && restoreIdentity && restoreIdentity.salt !== vaultSalt
  );
  const isConfirmed = confirmText.trim().toUpperCase() === DESTROY_CONFIRMATION_PHRASE;
  const destroyToken = isConfirmed ? DESTROY_CONFIRMATION_PHRASE : undefined;

  /** An invite for a vault that is not the one on this device. */
  const inviteIsForAnotherVault = Boolean(
    hasVault && inviteData && inviteData.salt && inviteData.salt !== vaultSalt
  );

  /**
   * Writes an encrypted container of everything currently on disk, then proves
   * the file opens with the passphrase that was just typed. A backup nobody can
   * decrypt is worse than no backup, because it feels like insurance.
   */
  const handleDownloadRescueBackup = async () => {
    setBackupError(null);
    setBackupDone(false);

    if (normalizePassphrase(backupPassphrase).length < MIN_PASSPHRASE_LENGTH) {
      setBackupError(`Pick a passphrase with at least ${MIN_PASSPHRASE_LENGTH} characters.`);
      return;
    }

    setBackupBusy(true);
    let url = null;
    try {
      const raw = await db.exportRawDataForBackup();
      const container = await createEncryptedBackup(raw, backupPassphrase);
      // Round-trip it before handing it over. This is the check the old export
      // flow never did, which is how typos produced unopenable .vault files.
      await decryptBackupContainer(container, backupPassphrase);

      const blob = new Blob([JSON.stringify(container)], { type: 'application/json' });
      url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `our-space-rescue-${localDateString()}.vault`;
      // Firefox aborts a download whose anchor was never in the document, and
      // aborts it again if the object URL is revoked in the same tick.
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setBackupDone(true);
    } catch (err) {
      console.error('Rescue backup failed:', err);
      setBackupError('We could not save that copy. Please try again.');
    } finally {
      if (url) setTimeout(() => URL.revokeObjectURL(url), 60000);
      setBackupBusy(false);
    }
  };

  /* ----------------------------------------------------------------------- *
   * Rescue restore
   *
   * Three separate steps, on purpose, because they prove three different things:
   *   1. pick the file          - it is a .vault container
   *   2. open the container     - the FILE passphrase is right
   *   3. adopt the identity     - the VAULT passphrase is right
   * Step 2 succeeding tells you nothing about step 3. Collapsing them into one
   * "restore" button is what would let someone adopt a salt they cannot decrypt.
   * ----------------------------------------------------------------------- */

  const resetRestoreState = () => {
    setRestoreFileName('');
    setRestoreContainer(null);
    setRestoreFilePassphrase('');
    setRestoreTables(null);
    setRestoreIdentity(null);
    setRestoreVaultPassphrase('');
    setRestoreError(null);
    setConfirmText('');
  };

  const handleRestoreFilePick = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    resetRestoreState();

    if (file.size > MAX_BACKUP_FILE_BYTES) {
      setRestoreError(
        `That file is ${Math.round(file.size / (1024 * 1024))}MB, over the ${Math.round(
          MAX_BACKUP_FILE_BYTES / (1024 * 1024)
        )}MB limit.`
      );
      return;
    }

    try {
      const text = await file.text();
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        setRestoreError('That does not look like a file Our Space saved.');
        return;
      }
      setRestoreFileName(file.name);
      setRestoreContainer(parsed);
    } catch {
      setRestoreError('That does not look like a file Our Space saved.');
    }
  };

  /** Step 2: open the container and read the identity it carries. */
  const handleOpenRestoreContainer = async (e) => {
    e.preventDefault();
    setRestoreError(null);
    if (!restoreContainer) return;

    setRestoreBusy(true);
    try {
      const decrypted = await decryptBackupContainer(restoreContainer, restoreFilePassphrase);
      const identity = readBackupVaultIdentity(decrypted.tables);
      if (!identity) {
        setRestoreError(
          'That file opened, but it is missing the part we need to rebuild your space here. It was ' +
            'probably saved by an older version. You can still bring its things in from the Sync ' +
            'Hub once you are unlocked.'
        );
        return;
      }
      setRestoreTables(decrypted.tables);
      setRestoreIdentity(identity);
      // Most rescue files are written with the vault's own passphrase, so try it
      // first rather than making the user type it twice for nothing.
      setRestoreVaultPassphrase(restoreFilePassphrase);
    } catch (err) {
      console.error('Could not open the backup container:', err);
      setRestoreError('We could not open that file. Check the passphrase and try again.');
    } finally {
      setRestoreBusy(false);
    }
  };

  /** Step 3: adopt the identity, keyed by the ORIGINAL vault passphrase. */
  const handleRestoreVault = async (e) => {
    e.preventDefault();
    setRestoreError(null);
    if (!restoreTables) return;

    if (restoreReplacesVault && !isConfirmed) {
      setRestoreError(`Type ${DESTROY_CONFIRMATION_PHRASE} to confirm.`);
      return;
    }

    setRestoreBusy(true);
    tap();
    const result = await restoreVaultFromBackup(restoreTables, restoreVaultPassphrase, {
      confirmDestroy: destroyToken,
    });
    setRestoreBusy(false);

    if (result.ok) {
      resetRestoreState();
      celebration();
      fireHeartConfetti();
      return;
    }

    setRestoreError(RESTORE_ERRORS[result.code] || 'That did not finish. Please try again.');
  };

  /** Remembers the peer id so SyncContext can offer to dial after unlock. */
  const rememberPartnerId = (partnerPeerId) => {
    if (!partnerPeerId) return;
    try {
      sessionStorage.setItem('pending_partner_connect', partnerPeerId);
      localStorage.setItem('sweetheart_paired_partner_id', partnerPeerId);
    } catch {
      // Storage blocked (private window). Pairing still works, it just will not
      // be remembered for next time.
    }
  };

  const handleUnlock = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (normalizePassphrase(passphrase).length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`);
      return;
    }
    setLoading(true);
    tap();

    const success = await unlockVault(passphrase);
    setLoading(false);
    if (success) {
      if (inviteData && inviteData.partnerPeerId && !inviteIsForAnotherVault) {
        rememberPartnerId(inviteData.partnerPeerId);
      }
      setPassphrase('');
      celebration();
      fireHeartConfetti();
    }
  };

  const handleSetup = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (normalizePassphrase(passphrase).length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(
        `Please choose a memorable secret passphrase of at least ${MIN_PASSPHRASE_LENGTH} characters.`
      );
      return;
    }
    if (hasVault && !isConfirmed) {
      setLocalError(`Type ${DESTROY_CONFIRMATION_PHRASE} to confirm you want to erase everything here.`);
      return;
    }
    setLoading(true);
    tap();

    const success = await initializeVault(
      passphrase,
      { coupleNames: coupleNames.trim() || 'Us', startDate },
      { confirmDestroy: destroyToken }
    );
    setLoading(false);
    if (success) {
      setPassphrase('');
      setConfirmText('');
      celebration();
      fireHeartConfetti();
    }
  };

  const handleJoin = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (normalizePassphrase(passphrase).length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`);
      return;
    }

    // Prefer the invite from the URL; fall back to whatever was pasted in.
    const invite =
      inviteData && inviteData.salt ? inviteData : parseInvite(partnerInviteInput);

    if (!invite || !invite.salt) {
      setLocalError(
        'Please paste your partner’s invite link — the one they sent you, or the QR code you scanned.'
      );
      return;
    }

    if (joinReplacesVault && !isConfirmed) {
      setLocalError(`Type ${DESTROY_CONFIRMATION_PHRASE} to confirm you want to erase everything here.`);
      return;
    }

    setLoading(true);
    tap();

    const success = await initializeFromPartnerInvite(
      passphrase,
      invite.salt,
      {
        startDate: invite.startDate,
        coupleNames: invite.coupleNames,
        // Present only once invites carry them; verified when they are.
        canary: invite.canary,
        canaryIv: invite.canaryIv,
      },
      { confirmDestroy: destroyToken }
    );
    setLoading(false);

    if (success) {
      rememberPartnerId(invite.partnerPeerId);
      setPassphrase('');
      setConfirmText('');
      celebration();
      fireHeartConfetti();
    }
  };

  const displayError = localError || vaultError;

  const errorBanner = displayError ? (
    <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
      {displayError}
    </div>
  ) : null;

  const dangerGate = (headline) => (
    <DangerGate
      headline={headline}
      confirmText={confirmText}
      onConfirmTextChange={setConfirmText}
      isConfirmed={isConfirmed}
      backupPassphrase={backupPassphrase}
      onBackupPassphraseChange={(value) => {
        setBackupPassphrase(value);
        setBackupError(null);
        setBackupDone(false);
      }}
      onDownloadBackup={handleDownloadRescueBackup}
      backupBusy={backupBusy}
      backupDone={backupDone}
      backupError={backupError}
    />
  );

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-4 relative z-10">
      <motion.div
        initial={{ opacity: 0, y: 20, scale: 0.95 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.5, ease: 'easeOut' }}
        className="w-full max-w-md"
      >
        {/* Cute Icon Avatar */}
        <div className="text-center mb-6">
          <motion.div
            animate={{
              scale: [1, 1.08, 1],
              rotate: [0, -3, 3, 0],
            }}
            transition={{
              repeat: Infinity,
              duration: 3,
              ease: 'easeInOut',
            }}
            className="w-20 h-20 mx-auto rounded-full bg-gradient-to-tr from-blush-300 via-blush-200 to-lavender-200 flex items-center justify-center shadow-lg shadow-blush-200/50 border-4 border-white"
          >
            <Heart className="w-10 h-10 text-blush-500 fill-blush-400" />
          </motion.div>
          <h1 className="text-3xl font-extrabold text-slate-800 mt-4 tracking-tight">
            Our Space 💕
          </h1>
          <p className="text-sm text-slate-500 mt-1 font-medium">
            A little corner just for the two of us
          </p>
        </div>

        <GlassCard className="border-2 border-blush-100 shadow-xl shadow-blush-200/30">
          {/* Still reading IndexedDB. Showing a form now means guessing, and
              guessing wrong offers a returning user the CREATE VAULT form. */}
          {isChecking && (
            <div className="py-10 text-center space-y-3">
              <div className="w-8 h-8 mx-auto rounded-full border-2 border-blush-200 border-t-blush-500 animate-spin" />
              <p className="text-xs text-slate-500 font-medium">Finding your space…</p>

              {/* Dexie told us another connection is holding the old schema. The
                  read above will never settle on its own, so this is the only
                  place the user can be told why. */}
              {vaultCheckBlocked && (
                <div className="mx-2 p-3 rounded-xl bg-amber-50 border border-amber-200 text-[11px] text-amber-900 leading-relaxed text-left">
                  <p className="font-bold">Our Space is open somewhere else.</p>
                  <p className="mt-1">
                    Close the other tabs you have open and this will carry on by itself.
                  </p>
                </div>
              )}

              {/* No blocked event, but the read is still not back. Same advice,
                  stated as a possibility rather than a fact, because we do not
                  actually know the cause here. */}
              {!vaultCheckBlocked && checkIsSlow && (
                <div className="mx-2 p-3 rounded-xl bg-slate-50 border border-slate-200 text-[11px] text-slate-600 leading-relaxed text-left">
                  <p className="font-bold">This is taking a little while.</p>
                  <p className="mt-1">
                    Usually that means Our Space is open in another tab. Try closing them. Nothing
                    here has changed, and nothing will until this finishes.
                  </p>
                </div>
              )}
            </div>
          )}

          {/* The read FAILED. This is not the same as "there is no vault", and it
              must never be rendered as one: every form below either unlocks a
              vault we cannot see or replaces it. So: no forms, a named cause, and
              a retry. */}
          {isUnreadable && (
            <div className="py-6 text-center space-y-3">
              <ShieldAlert className="w-8 h-8 mx-auto text-amber-500" />
              <p className="text-sm font-bold text-slate-700">
                Something went wrong opening your space
              </p>
              <p className="text-[11px] text-slate-600 leading-relaxed px-2">
                Nothing was lost — try again, and close any other tabs you have open.
              </p>
              <button
                type="button"
                onClick={() => {
                  tap();
                  retryVaultCheck();
                }}
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl bg-slate-800 text-white text-xs font-bold hover:bg-slate-900"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                <span>Try again</span>
              </button>
            </div>
          )}

          {/* Mode switcher, only once we know there is nothing to lose. */}
          {vaultCheckState === 'absent' && mode !== 'restore' && (
            <div className="flex bg-slate-100/80 p-1 rounded-2xl mb-5">
              <button
                type="button"
                onClick={() => switchMode('setup')}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition flex items-center justify-center gap-1.5 ${
                  mode === 'setup'
                    ? 'bg-white text-slate-800 shadow-sm'
                    : 'text-slate-500 hover:text-slate-700'
                }`}
              >
                <Sparkles className="w-3.5 h-3.5 text-blush-500" />
                <span>Create New Space</span>
              </button>
              <button
                type="button"
                onClick={() => switchMode('join')}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition flex items-center justify-center gap-1.5 ${
                  mode === 'join'
                    ? 'bg-white text-slate-800 shadow-sm'
                    : 'text-slate-500 hover:text-slate-700'
                }`}
              >
                <Users className="w-3.5 h-3.5 text-indigo-500" />
                <span>Join Partner&apos;s Space</span>
              </button>
            </div>
          )}

          {/* MODE 1: UNLOCK EXISTING VAULT */}
          {canRenderForms && mode === 'unlock' && (
            <form onSubmit={handleUnlock} className="space-y-4">
              <div className="text-center mb-4">
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blush-100/70 text-blush-600 text-xs font-semibold">
                  <Lock className="w-3.5 h-3.5" />
                  <span>Locked</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Enter the passphrase you two share to open your memories and notes.
                </p>
              </div>

              {inviteData && inviteData.partnerPeerId && !inviteIsForAnotherVault && (
                <div className="p-2.5 bg-indigo-50/70 border border-indigo-100 rounded-xl text-[11px] text-indigo-800 flex items-center gap-2">
                  <Link2 className="w-4 h-4 text-indigo-500 flex-shrink-0" />
                  <span>
                    Your partner&apos;s invite is here. Unlock, and we&apos;ll offer to connect to
                    their phone.
                  </span>
                </div>
              )}

              {inviteIsForAnotherVault && (
                <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-xl text-[11px] text-amber-900 flex items-start gap-2">
                  <AlertTriangle className="w-4 h-4 text-amber-500 flex-shrink-0 mt-0.5" />
                  <span>
                    That invite is for a <strong>different space</strong>, not this one. Unlocking
                    here is safe — the link is ignored. Joining it would replace everything on this
                    phone.
                  </span>
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                      if (vaultError) clearError();
                    }}
                    placeholder={`Enter your secret passphrase (min ${MIN_PASSPHRASE_LENGTH} chars)...`}
                    required
                    minLength={MIN_PASSPHRASE_LENGTH}
                    autoFocus
                    className="w-full px-4 py-3 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                  />
                  <KeyRound className="w-4 h-4 text-slate-400 absolute left-3.5 top-3.5" />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-slate-400 hover:text-slate-600"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {errorBanner}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim()}
                className="w-full py-3.5 text-base font-bold shadow-md shadow-blush-300/40"
              >
                {loading ? 'Opening…' : 'Unlock Our Space 💕'}
              </BouncyButton>

              <div className="pt-2 flex flex-col gap-1.5 text-center">
                <button
                  type="button"
                  onClick={() => switchMode('join')}
                  className="text-xs text-indigo-600 hover:text-indigo-700 underline font-medium"
                >
                  Joining partner&apos;s space with an invite link?
                </button>
                <button
                  type="button"
                  onClick={() => switchMode('setup')}
                  className="text-xs text-slate-400 hover:text-slate-600 underline"
                >
                  Start over with a brand new space (erases this one)
                </button>
              </div>
            </form>
          )}

          {/* MODE 2: JOIN PARTNER'S SPACE (Via Link or Manual Code) */}
          {canRenderForms && mode === 'join' && (
            <form onSubmit={handleJoin} className="space-y-4">
              <div className="text-center mb-3">
                <div className="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-xs font-bold">
                  <UserCheck className="w-3.5 h-3.5 text-indigo-500" />
                  <span>Join Partner&apos;s Space 💕</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  {inviteData && inviteData.partnerPeerId
                    ? 'Your partner invited you! 💕'
                    : 'Use your partner’s invite link to join their space.'}
                </p>
              </div>

              {/* If no salt came from the URL, take a pasted link or code. */}
              {!(inviteData && inviteData.salt) && (
                <div>
                  <label className="block text-xs font-semibold text-slate-600 mb-1">
                    Partner&apos;s Invite Link or Code
                  </label>
                  <div className="relative">
                    <input
                      type="text"
                      value={partnerInviteInput}
                      onChange={(e) => {
                        setPartnerInviteInput(e.target.value);
                        if (localError) setLocalError(null);
                        if (vaultError) clearError();
                      }}
                      placeholder="Paste link (e.g. https://...#connect=...)"
                      required
                      className="w-full px-4 py-2.5 pl-10 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-400 placeholder:text-slate-400 transition"
                    />
                    <Link2 className="w-4 h-4 text-slate-400 absolute left-3.5 top-3" />
                  </div>
                  <p className="text-[11px] text-slate-400 mt-1">
                    Ask your partner to tap &quot;Share Pairing Link&quot; in their Sync Hub, then
                    paste it here.
                  </p>
                </div>
              )}

              {pendingJoinSalt && !joinReplacesVault && hasVault && (
                <div className="p-2.5 bg-emerald-50/70 border border-emerald-100 rounded-xl text-[11px] text-emerald-800 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  <span>
                    This invite is for the space you already have here. Pairing again is safe —
                    nothing gets erased.
                  </span>
                </div>
              )}

              {pendingJoinSalt && !hasVault && (
                <div className="p-2.5 bg-emerald-50/70 border border-emerald-100 rounded-xl text-[11px] text-emerald-800 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  <span>Found your partner&apos;s invite! Enter the passphrase you both chose.</span>
                </div>
              )}

              {joinReplacesVault &&
                dangerGate(
                  'Joining this invite moves this phone over to your partner’s space.'
                )}

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Shared Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                      if (vaultError) clearError();
                    }}
                    placeholder="Enter the secret phrase you both agreed on..."
                    required
                    minLength={MIN_PASSPHRASE_LENGTH}
                    autoFocus={!joinReplacesVault}
                    className="w-full px-4 py-3 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 placeholder:text-slate-400 transition"
                  />
                  <KeyRound className="w-4 h-4 text-slate-400 absolute left-3.5 top-3.5" />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-slate-400 hover:text-slate-600"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
                <p className="text-[11px] text-slate-400 mt-1">
                  It has to match theirs exactly, letter for letter.
                </p>
              </div>

              {errorBanner}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim() || (joinReplacesVault && !isConfirmed)}
                className="w-full py-3.5 text-base font-bold bg-indigo-600 hover:bg-indigo-700 text-white shadow-md shadow-indigo-300/40"
              >
                {loading ? 'Pairing…' : 'Pair & Enter Our Space 💕'}
              </BouncyButton>

              {hasVault && (
                <div className="pt-1 text-center">
                  <button
                    type="button"
                    onClick={() => switchMode('unlock')}
                    className="text-xs text-slate-500 hover:text-slate-700 underline"
                  >
                    Cancel and return to unlock
                  </button>
                </div>
              )}
            </form>
          )}

          {/* MODE 3: CREATE NEW SPACE (Initiator First-Time Setup) */}
          {canRenderForms && mode === 'setup' && (
            <form onSubmit={handleSetup} className="space-y-4">
              <div className="text-center mb-2">
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-lavender-100 text-lavender-700 text-xs font-semibold">
                  <Sparkles className="w-3.5 h-3.5 text-lavender-500" />
                  <span>Setup Your Private Space</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Choose a passphrase only the two of you know. It is the only thing that opens
                  your space.
                </p>
              </div>

              {hasVault &&
                dangerGate(
                  'Starting a new space gives this phone a brand new lock.'
                )}

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Your Nicknames / Couple Name
                </label>
                <input
                  type="text"
                  value={coupleNames}
                  onChange={(e) => setCoupleNames(e.target.value)}
                  placeholder="e.g. Romeo & Juliet"
                  className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  When Did Your Story Begin?
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  required
                  className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 transition"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Shared Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                      if (vaultError) clearError();
                    }}
                    placeholder={`Create a shared secret phrase (min ${MIN_PASSPHRASE_LENGTH} chars)...`}
                    required
                    minLength={MIN_PASSPHRASE_LENGTH}
                    className="w-full px-4 py-2.5 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                  />
                  <KeyRound className="w-4 h-4 text-slate-400 absolute left-3.5 top-3.5" />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-slate-400 hover:text-slate-600"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
                <p className="text-[11px] text-slate-400 mt-1">
                  At least {MIN_PASSPHRASE_LENGTH} characters — a little sentence only you two would
                  know works best. It is never saved anywhere, so if you both forget it, everything
                  here is gone.
                </p>
              </div>

              {errorBanner}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim() || (hasVault && !isConfirmed)}
                className="w-full py-3.5 text-base font-bold"
              >
                {loading
                  ? 'Setting things up…'
                  : hasVault
                    ? 'Erase & Start Fresh'
                    : 'Create Our Space 💕'}
              </BouncyButton>

              {hasVault && (
                <div className="pt-1 text-center">
                  <button
                    type="button"
                    onClick={() => switchMode('unlock')}
                    className="text-xs text-slate-500 hover:text-slate-700 underline"
                  >
                    Cancel and return to unlock
                  </button>
                </div>
              )}
            </form>
          )}

          {/* MODE 4: RESTORE FROM A RESCUE BACKUP
              The counterpart to the rescue download in DangerGate, and the only
              flow in the app that writes a vault salt out of a file. Kept
              separate from the Sync Hub's merge-import on purpose: that one keeps
              the key you already have, this one replaces it. */}
          {canRenderForms && mode === 'restore' && (
            <div className="space-y-4">
              <div className="text-center mb-1">
                <div className="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-full bg-amber-50 border border-amber-200 text-amber-800 text-xs font-bold">
                  <LifeBuoy className="w-3.5 h-3.5 text-amber-500" />
                  <span>Bring back a saved copy</span>
                </div>
                <p className="text-xs text-slate-500 mt-2 leading-relaxed">
                  Rebuilds your space on this phone from a file you saved earlier, so everything
                  inside opens again.
                </p>
              </div>

              {/* Step 1: the file */}
              <div>
                <label className="flex items-center justify-center gap-2 py-2.5 px-3 rounded-2xl border-2 border-dashed border-slate-300 text-xs font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
                  <Upload className="w-4 h-4 text-slate-400" />
                  <span>{restoreFileName || 'Choose the file you saved'}</span>
                  <input
                    type="file"
                    accept=".vault,.json,application/json"
                    onChange={handleRestoreFilePick}
                    className="hidden"
                  />
                </label>
              </div>

              {/* Step 2: the FILE passphrase */}
              {restoreContainer && !restoreTables && (
                <form onSubmit={handleOpenRestoreContainer} className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-600">
                    Passphrase that opens this <em>file</em>
                  </label>
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={restoreFilePassphrase}
                    onChange={(e) => {
                      setRestoreFilePassphrase(e.target.value);
                      setRestoreError(null);
                    }}
                    placeholder="Passphrase for this file"
                    autoComplete="off"
                    autoFocus
                    className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-amber-400 placeholder:text-slate-400"
                  />
                  <BouncyButton
                    type="submit"
                    disabled={restoreBusy || !restoreFilePassphrase.trim()}
                    className="w-full py-3 text-sm font-bold bg-slate-800 hover:bg-slate-900 text-white"
                  >
                    {restoreBusy ? 'Opening…' : 'Open this file'}
                  </BouncyButton>
                </form>
              )}

              {/* Step 3: the VAULT passphrase, which is a different question. */}
              {restoreTables && restoreIdentity && (
                <form onSubmit={handleRestoreVault} className="space-y-3">
                  <div className="p-2.5 rounded-xl bg-emerald-50/70 border border-emerald-100 text-[11px] text-emerald-800 flex items-start gap-2">
                    <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0 mt-0.5" />
                    <span>
                      File opened! Now the passphrase you used <strong>back then</strong> will bring
                      everything inside back.
                    </span>
                  </div>

                  {restoreReplacesVault &&
                    dangerGate(
                      'Bringing this file back moves this phone over to the space inside it.'
                    )}

                  {/* The old copy said "nothing here will be overwritten", which
                      the code does not honour: restoreVaultFromBackup calls
                      wipeSyncedTables unconditionally, including on this path.
                      The wipe is deliberately kept - a device with no vaultMeta
                      can still hold rows a previous destroy orphaned, and those
                      are encrypted under a key that no longer exists anywhere,
                      so carrying them into the restored vault would only feed
                      permanently unreadable rows back into sync. So the STRING
                      moves to meet the code, not the other way round. */}
                  {!hasVault && (
                    <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[11px] text-slate-600 leading-relaxed">
                      There is nothing here to replace. Anything left over from an older space on
                      this phone is tidied away first — it cannot be opened any more anyway.
                    </div>
                  )}

                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1">
                      The passphrase you used <em>back then</em>
                    </label>
                    <input
                      type={showPassword ? 'text' : 'password'}
                      value={restoreVaultPassphrase}
                      onChange={(e) => {
                        setRestoreVaultPassphrase(e.target.value);
                        setRestoreError(null);
                      }}
                      placeholder="The passphrase you used to unlock the app back then"
                      minLength={MIN_PASSPHRASE_LENGTH}
                      autoComplete="off"
                      className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-amber-400 placeholder:text-slate-400"
                    />
                    <p className="text-[11px] text-slate-400 mt-1 leading-relaxed">
                      Usually the same as the file passphrase, so we have filled it in. We check it
                      before anything is written, so a wrong guess costs you nothing.
                    </p>
                  </div>

                  {restoreError && (
                    <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-[11px] font-medium leading-relaxed">
                      {restoreError}
                    </div>
                  )}

                  <BouncyButton
                    type="submit"
                    disabled={
                      restoreBusy ||
                      !restoreVaultPassphrase.trim() ||
                      (restoreReplacesVault && !isConfirmed)
                    }
                    className="w-full py-3.5 text-base font-bold bg-amber-600 hover:bg-amber-700 text-white shadow-md shadow-amber-300/40"
                  >
                    {restoreBusy ? 'Bringing it back…' : 'Bring everything back'}
                  </BouncyButton>
                </form>
              )}

              {restoreError && !restoreTables && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-[11px] font-medium leading-relaxed">
                  {restoreError}
                </div>
              )}

              <div className="pt-1 text-center">
                <button
                  type="button"
                  onClick={() => switchMode(hasVault ? 'unlock' : 'setup')}
                  className="text-xs text-slate-500 hover:text-slate-700 underline"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          {/* Entry point to the restore flow, from wherever the user is stuck. */}
          {canRenderForms && mode !== 'restore' && (
            <div className="pt-3 mt-1 text-center">
              <button
                type="button"
                onClick={() => switchMode('restore')}
                className="inline-flex items-center gap-1.5 text-xs text-amber-700 hover:text-amber-800 underline font-medium"
              >
                <LifeBuoy className="w-3.5 h-3.5" />
                <span>Bring back a copy you saved</span>
              </button>
            </div>
          )}

          {/* Security badge */}
          <div className="mt-5 pt-4 border-t border-blush-100/80 flex items-center justify-center gap-2 text-slate-400 text-[11px]">
            <ShieldCheck className="w-4 h-4 text-emerald-500" />
            <span>Locked with your passphrase. Only you two can open it.</span>
          </div>
        </GlassCard>
      </motion.div>
    </div>
  );
}

export default LockScreen;
