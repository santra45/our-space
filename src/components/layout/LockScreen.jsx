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
  no_identity:
    'That backup does not carry a vault salt, so there is no identity to restore from it.',
  bad_salt: 'That backup carries a malformed vault salt and was refused.',
  passphrase_too_short: `The vault passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`,
  passphrase_mismatch:
    'That is not the passphrase this backup’s vault was encrypted with. Nothing was changed. It is ' +
    'the passphrase you used to unlock the app back when this file was made — not necessarily the ' +
    'one that opened the file itself.',
  unreadable:
    'This device’s existing vault could not be read, so the restore was refused rather than risk ' +
    'overwriting it. Close any other tab or window running Our Space, then reload and try again.',
  same_vault:
    'This backup is for the vault already on this device, so there is no identity to replace. ' +
    'Unlock normally, then use Import .vault in the Sync Hub to merge its records back in.',
  needs_confirmation: 'Type the confirmation phrase to replace the vault already on this device.',
  write_failed: 'The restore failed partway through. Nothing further was written.',
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
            This destroys the vault on this device
          </p>
          <p className="text-[11px] text-rose-700 mt-1 leading-relaxed">
            {headline} A new encryption key means every photo, letter, milestone and bucket-list item
            already stored here becomes <strong>permanently unreadable</strong>, and they will be
            erased from this device. There is no undo and no recovery — not by us, not by anyone.
          </p>
          <p className="text-[11px] text-rose-700 mt-1.5 leading-relaxed">
            If you simply forgot the passphrase, <strong>stop here</strong>. Nothing on this screen
            can recover it, and your partner&apos;s device may still hold everything.
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
          Save an encrypted rescue backup first
        </p>
        <p className="text-[10px] text-slate-500 leading-relaxed">
          Downloads every encrypted row on this device, plus this vault&apos;s salt and canary, in one
          file. It can be put back later with <strong>&quot;Restore from a rescue backup&quot;</strong>{' '}
          on this screen.
        </p>
        <p className="text-[10px] text-slate-500 leading-relaxed">
          <strong>It needs two passphrases, not one.</strong> The one you type below only opens the
          file. The photos and letters inside stay encrypted under the passphrase{' '}
          <strong>this vault uses today</strong> — restoring them means supplying that one as well.
          If it is truly lost, this file cannot bring them back, and neither can anything else. That
          is what end-to-end encryption costs.
        </p>
        <input
          type="password"
          value={backupPassphrase}
          onChange={(e) => onBackupPassphraseChange(e.target.value)}
          placeholder={`Passphrase for the backup file (min ${MIN_PASSPHRASE_LENGTH})`}
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
          {backupBusy ? 'Encrypting backup…' : 'Download rescue backup'}
        </button>
        {backupDone && (
          <p className="text-[10px] text-emerald-700 font-semibold flex items-center gap-1">
            <CheckCircle2 className="w-3 h-3" />
            Backup written and verified — that passphrase opens the file.
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
      setBackupError(`Choose a backup passphrase of at least ${MIN_PASSPHRASE_LENGTH} characters.`);
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
      setBackupError('Could not create the backup: ' + (err.message || 'Unknown error'));
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
        setRestoreError('That file is not a valid .vault backup.');
        return;
      }
      setRestoreFileName(file.name);
      setRestoreContainer(parsed);
    } catch {
      setRestoreError('That file is not a valid .vault backup (it is not readable JSON).');
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
          'That backup opened, but it does not carry the vault salt and canary, so there is no ' +
            'identity to restore. It was most likely written by an older version of the app. Its ' +
            'records can still be merged into an unlocked vault from the Sync Hub.'
        );
        return;
      }
      setRestoreTables(decrypted.tables);
      setRestoreIdentity(identity);
      // Most rescue files are written with the vault's own passphrase, so try it
      // first rather than making the user type it twice for nothing.
      setRestoreVaultPassphrase(restoreFilePassphrase);
    } catch (err) {
      setRestoreError(err.message || 'Could not open that backup file.');
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

    setRestoreError(RESTORE_ERRORS[result.code] || result.message || 'The restore did not complete.');
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
      setLocalError(`Type ${DESTROY_CONFIRMATION_PHRASE} to confirm you want to destroy this vault.`);
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
        'Please paste a valid invite link containing your partner’s vault salt (copied from WhatsApp, or scanned from their QR code).'
      );
      return;
    }

    if (joinReplacesVault && !isConfirmed) {
      setLocalError(`Type ${DESTROY_CONFIRMATION_PHRASE} to confirm you want to destroy this vault.`);
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
        kdfIterations: invite.kdfIterations,
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
            Private, Encrypted Sanctuary For Two
          </p>
        </div>

        <GlassCard className="border-2 border-blush-100 shadow-xl shadow-blush-200/30">
          {/* Still reading IndexedDB. Showing a form now means guessing, and
              guessing wrong offers a returning user the CREATE VAULT form. */}
          {isChecking && (
            <div className="py-10 text-center space-y-3">
              <div className="w-8 h-8 mx-auto rounded-full border-2 border-blush-200 border-t-blush-500 animate-spin" />
              <p className="text-xs text-slate-500 font-medium">Looking for your vault…</p>
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
                Could not read this device&apos;s vault
              </p>
              {vaultCheckBlocked ? (
                <p className="text-[11px] text-slate-600 leading-relaxed px-2">
                  Our Space is open in <strong>another tab or window</strong>, and it is holding the
                  older version of the local database open. The upgrade cannot finish until that copy
                  closes. Close every other tab running Our Space, then tap Try again.
                </p>
              ) : (
                <p className="text-[11px] text-slate-600 leading-relaxed px-2">
                  The local database would not open. Another tab may be holding it, or the browser
                  may be blocking storage (private windows do this), or the disk may be full.
                </p>
              )}
              <p className="text-[11px] text-slate-500 leading-relaxed px-2">
                Nothing has been changed, and no setup form is offered here on purpose — a read
                error is not proof this device is empty, and creating a new vault on top of one we
                cannot see would destroy it.
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
                  <span>Vault Locked</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Enter your shared secret passphrase to unlock your private memories and notes.
                </p>
              </div>

              {inviteData && inviteData.partnerPeerId && !inviteIsForAnotherVault && (
                <div className="p-2.5 bg-indigo-50/70 border border-indigo-100 rounded-xl text-[11px] text-indigo-800 flex items-center gap-2">
                  <Link2 className="w-4 h-4 text-indigo-500 flex-shrink-0" />
                  <span>
                    Invite link detected. Unlock and this device will offer to connect to{' '}
                    {inviteData.partnerPeerId}.
                  </span>
                </div>
              )}

              {inviteIsForAnotherVault && (
                <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-xl text-[11px] text-amber-900 flex items-start gap-2">
                  <AlertTriangle className="w-4 h-4 text-amber-500 flex-shrink-0 mt-0.5" />
                  <span>
                    That invite link is for a <strong>different vault</strong> than the one on this
                    device. Unlocking here is safe and ignores the link. Joining it would replace
                    everything stored here.
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
                {loading ? 'Deriving Key...' : 'Unlock Our Space 💕'}
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
                    ? `Partner device (${inviteData.partnerPeerId}) invited you!`
                    : 'Pair your device directly with your partner using their invite link.'}
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
                    Ask your partner to tap &quot;Share Pairing Link&quot; in their Sync Hub and paste
                    the link here.
                  </p>
                </div>
              )}

              {pendingJoinSalt && !joinReplacesVault && hasVault && (
                <div className="p-2.5 bg-emerald-50/70 border border-emerald-100 rounded-xl text-[11px] text-emerald-800 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  <span>
                    This invite is for the vault already on this device. Re-pairing is safe — nothing
                    will be erased.
                  </span>
                </div>
              )}

              {pendingJoinSalt && !hasVault && (
                <div className="p-2.5 bg-emerald-50/70 border border-emerald-100 rounded-xl text-[11px] text-emerald-800 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  <span>Partner&apos;s encryption salt found! Enter your shared passphrase to pair.</span>
                </div>
              )}

              {joinReplacesVault &&
                dangerGate(
                  'Joining this invite adopts your partner’s encryption salt in place of the one this device already uses.'
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
                  Must match partner&apos;s passphrase exactly to derive the identical 256-bit AES key.
                </p>
              </div>

              {errorBanner}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim() || (joinReplacesVault && !isConfirmed)}
                className="w-full py-3.5 text-base font-bold bg-indigo-600 hover:bg-indigo-700 text-white shadow-md shadow-indigo-300/40"
              >
                {loading ? 'Deriving Key & Pairing...' : 'Pair & Enter Our Space 💕'}
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
                  Choose a passphrase only the two of you know. It derives your AES-GCM 256
                  encryption key.
                </p>
              </div>

              {hasVault &&
                dangerGate(
                  'Creating a new space generates a brand new encryption salt for this device.'
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
                  Must be at least {MIN_PASSPHRASE_LENGTH} characters (e.g. a memorable secret
                  sentence only you two know). It is never stored anywhere — forget it and the vault
                  is gone.
                </p>
              </div>

              {errorBanner}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim() || (hasVault && !isConfirmed)}
                className="w-full py-3.5 text-base font-bold"
              >
                {loading
                  ? 'Deriving 256-bit Key...'
                  : hasVault
                    ? 'Erase & Create New Vault'
                    : 'Create Vault & Start 💕'}
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
                  <span>Restore from a rescue backup</span>
                </div>
                <p className="text-xs text-slate-500 mt-2 leading-relaxed">
                  Rebuilds a vault on this device from a <code>.vault</code> file — its encryption
                  salt as well as its records, so the memories inside open again.
                </p>
              </div>

              {/* Step 1: the file */}
              <div>
                <label className="flex items-center justify-center gap-2 py-2.5 px-3 rounded-2xl border-2 border-dashed border-slate-300 text-xs font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
                  <Upload className="w-4 h-4 text-slate-400" />
                  <span>{restoreFileName || 'Choose your .vault rescue file'}</span>
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
                    placeholder="Backup file passphrase"
                    autoComplete="off"
                    autoFocus
                    className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-amber-400 placeholder:text-slate-400"
                  />
                  <BouncyButton
                    type="submit"
                    disabled={restoreBusy || !restoreFilePassphrase.trim()}
                    className="w-full py-3 text-sm font-bold bg-slate-800 hover:bg-slate-900 text-white"
                  >
                    {restoreBusy ? 'Opening backup…' : 'Open backup file'}
                  </BouncyButton>
                </form>
              )}

              {/* Step 3: the VAULT passphrase, which is a different question. */}
              {restoreTables && restoreIdentity && (
                <form onSubmit={handleRestoreVault} className="space-y-3">
                  <div className="p-2.5 rounded-xl bg-emerald-50/70 border border-emerald-100 text-[11px] text-emerald-800 flex items-start gap-2">
                    <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0 mt-0.5" />
                    <span>
                      File opened. It carries a vault identity, so the records inside can be made
                      readable again — with the passphrase <strong>that vault</strong> used.
                    </span>
                  </div>

                  {restoreReplacesVault &&
                    dangerGate(
                      'Restoring this backup adopts the encryption salt inside the file in place of the one this device already uses.'
                    )}

                  {!hasVault && (
                    <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[11px] text-slate-600 leading-relaxed">
                      There is no vault on this device, so nothing here will be overwritten.
                    </div>
                  )}

                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1">
                      The original <em>vault</em> passphrase
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
                      Often the same as the file passphrase — pre-filled with it. It is checked
                      against the backup&apos;s own canary before anything is written, so a wrong
                      one costs you nothing.
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
                    {restoreBusy ? 'Restoring…' : 'Restore this vault'}
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
                <span>Restore from a rescue backup file</span>
              </button>
            </div>
          )}

          {/* Security badge */}
          <div className="mt-5 pt-4 border-t border-blush-100/80 flex items-center justify-center gap-2 text-slate-400 text-[11px]">
            <ShieldCheck className="w-4 h-4 text-emerald-500" />
            <span>AES-GCM 256 Zero-Knowledge • 100% Local Encrypted</span>
          </div>
        </GlassCard>
      </motion.div>
    </div>
  );
}

export default LockScreen;
