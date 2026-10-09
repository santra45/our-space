import React, { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import {
  X,
  Share2,
  Camera,
  RefreshCw,
  AlertTriangle,
  Copy,
  Download,
  Upload,
  ShieldCheck,
  Fingerprint,
  ShieldAlert,
  Zap,
  HelpCircle,
  Eye,
  EyeOff,
  Loader2,
  Trash2,
  Inbox,
} from 'lucide-react';
import QRCode from 'qrcode';
import { useSync } from '../../context/SyncContext';
import { useVault } from '../../context/VaultContext';
import { usePeople } from '../../context/PeopleContext';
import { buildInviteUrl, parseInvite } from '../../utils/invite';
import { formatLastSeen, formatLastConnected } from '../../utils/dateHelpers';
import BouncyButton from '../common/BouncyButton';
import WhoIsWho from '../people/WhoIsWho';
import QRScannerModal from './QRScannerModal';
import { useHaptics } from '../../hooks/useHaptics';
import db, {
  MAX_BACKUP_FILE_BYTES,
  readBackupVaultIdentity,
  compareVaultIdentity,
} from '../../db';
import {
  createEncryptedBackup,
  decryptBackupContainer,
  verifyPassphraseAgainstMeta,
  normalizePassphrase,
  MIN_PASSPHRASE_LENGTH,
} from '../../services/crypto';

const MAX_BACKUP_FILE_MB = Math.round(MAX_BACKUP_FILE_BYTES / (1024 * 1024));

function PassphrasePrompt({
  title,
  description,
  requireConfirm,
  submitLabel,
  busy,
  error,
  onSubmit,
  onCancel,
}) {
  const [value, setValue] = useState('');
  const [confirmValue, setConfirmValue] = useState('');
  const [reveal, setReveal] = useState(false);

  const normalized = normalizePassphrase(value);
  const tooShort = normalized.length < MIN_PASSPHRASE_LENGTH;
  const mismatch = requireConfirm && confirmValue.length > 0 && value !== confirmValue;
  const canSubmit = !busy && !tooShort && (!requireConfirm || (confirmValue.length > 0 && !mismatch));

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!canSubmit) return;
    onSubmit(value);
  };

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <motion.form
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        onSubmit={handleSubmit}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100"
      >
        <h3 className="text-base font-bold text-slate-800">{title}</h3>
        <p className="mt-1 text-[11px] text-slate-500 leading-relaxed">{description}</p>

        <div className="mt-3 relative">
          <input
            type={reveal ? 'text' : 'password'}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            autoFocus
            autoComplete="off"
            spellCheck={false}
            placeholder="Secret passphrase"
            className="w-full px-3 py-2.5 pr-10 text-sm bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
          />
          <button
            type="button"
            onClick={() => setReveal((r) => !r)}
            aria-label={reveal ? 'Hide passphrase' : 'Show passphrase'}
            className="absolute right-2 top-1/2 -translate-y-1/2 w-7 h-7 rounded-lg text-slate-400 hover:text-slate-600 flex items-center justify-center"
          >
            {reveal ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
          </button>
        </div>

        {requireConfirm && (
          <input
            type={reveal ? 'text' : 'password'}
            value={confirmValue}
            onChange={(e) => setConfirmValue(e.target.value)}
            autoComplete="off"
            spellCheck={false}
            placeholder="Type it again to confirm"
            className="mt-2 w-full px-3 py-2.5 text-sm bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
          />
        )}

        {value.length > 0 && tooShort && (
          <p className="mt-2 text-[10px] font-semibold text-amber-600">
            At least {MIN_PASSPHRASE_LENGTH} characters.
          </p>
        )}
        {mismatch && (
          <p className="mt-2 text-[10px] font-semibold text-rose-600">
            The two entries do not match.
          </p>
        )}
        {error && (
          <p className="mt-2 px-3 py-2 text-[10px] font-semibold text-rose-700 bg-rose-50 border border-rose-200 rounded-xl leading-relaxed">
            {error}
          </p>
        )}

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!canSubmit}
            className="py-2.5 rounded-2xl bg-blush-500 text-white text-xs font-bold shadow-sm shadow-blush-300/50 hover:bg-blush-600 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
          >
            {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>{busy ? 'Working...' : submitLabel}</span>
          </button>
        </div>
      </motion.form>
    </div>
  );
}

function ImportPreview({ plan, relation, busy, onConfirm, onCancel }) {
  const t = plan.totals || {};
  const added = t.added || 0;
  const updated = t.updated || 0;
  const deleted = t.deleted || 0;
  const stale = t.stale || 0;
  const invalid = t.invalid || 0;
  const undecryptable = t.undecryptable || 0;
  const tampered = t.tampered || 0;
  const unauthenticated = t.unauthenticated || 0;
  const willWrite = added + updated + deleted;
  const leftOut = stale + invalid + undecryptable + tampered + unauthenticated;
  const destructive = deleted > 0;
  const foreign = relation === 'foreign';
  const [ackDelete, setAckDelete] = useState(false);
  const [showWhy, setShowWhy] = useState(false);

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 max-h-[85vh] overflow-y-auto"
      >
        <h3 className="text-base font-bold text-slate-800">Before we add these</h3>
        <p className="mt-1 text-[11px] text-slate-500 leading-relaxed">
          Nothing has been added yet. Here is what would happen.
        </p>

        {foreign && (
          <div className="mt-3 p-3 rounded-xl bg-rose-50 border-2 border-rose-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-rose-800 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">This is from somewhere else</p>
              <p className="mt-1">
                This file came from a different space, not yours. If you were not expecting it,
                please tap Cancel.
              </p>
            </div>
          </div>
        )}

        {relation === 'unknown' && (
          <div className="mt-3 p-3 rounded-xl bg-amber-50 border-2 border-amber-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-amber-900 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">We are not sure where this is from</p>
              <p className="mt-1">
                This file does not say which space it belongs to. Only things that open with your
                passphrase can be added. If you were not expecting it, please tap Cancel.
              </p>
            </div>
          </div>
        )}

        {relation === 'no-local-vault' && (
          <div className="mt-3 p-2.5 rounded-xl bg-amber-50 border border-amber-200 text-[11px] text-amber-900 leading-relaxed">
            We could not match this file to this phone. Only the things that open with your
            passphrase will be added.
          </div>
        )}

        <div className="mt-3 grid grid-cols-2 gap-2 text-center">
          <div className="p-2.5 rounded-xl bg-emerald-50 border border-emerald-100">
            <p className="text-lg font-extrabold text-emerald-700">{added}</p>
            <p className="text-[10px] font-bold text-emerald-800 uppercase tracking-wide">Added</p>
          </div>
          <div className="p-2.5 rounded-xl bg-indigo-50 border border-indigo-100">
            <p className="text-lg font-extrabold text-indigo-700">{updated}</p>
            <p className="text-[10px] font-bold text-indigo-800 uppercase tracking-wide">Updated</p>
          </div>
        </div>

        <div
          className={`mt-2 p-3 rounded-xl border-2 flex items-start gap-2.5 ${
            destructive ? 'bg-rose-50 border-rose-300' : 'bg-slate-50 border-slate-200'
          }`}
        >
          <Trash2
            className={`w-4 h-4 shrink-0 mt-0.5 ${destructive ? 'text-rose-600' : 'text-slate-400'}`}
          />
          <div className="min-w-0 flex-1">
            <p className="flex items-baseline justify-between gap-2">
              <span
                className={`text-[10px] font-extrabold uppercase tracking-wide ${
                  destructive ? 'text-rose-800' : 'text-slate-500'
                }`}
              >
                Removed for good
              </span>
              <span
                className={`text-lg font-extrabold leading-none ${
                  destructive ? 'text-rose-700' : 'text-slate-400'
                }`}
              >
                {deleted}
              </span>
            </p>
            <p
              className={`mt-1 text-[11px] leading-relaxed ${
                destructive ? 'text-rose-800' : 'text-slate-500'
              }`}
            >
              {destructive
                ? `This will remove ${deleted} ${deleted === 1 ? 'thing' : 'things'} you still ` +
                  `have, here and on the other phone. That cannot be undone.`
                : 'Nothing you still have gets removed.'}
            </p>
          </div>
        </div>

        {leftOut > 0 && (
          <div className="mt-2 px-1">
            <div className="flex items-baseline justify-between gap-2 text-[11px] text-slate-600">
              <span>
                {leftOut} {leftOut === 1 ? 'thing was' : 'things were'} left out
              </span>
              <button
                type="button"
                onClick={() => setShowWhy((v) => !v)}
                className="text-[10px] font-bold text-slate-400 hover:text-slate-600 underline"
              >
                Why?
              </button>
            </div>
            {showWhy && (
              <p className="mt-1 text-[10px] text-slate-500 leading-relaxed">
                Some are older than the copies you already have, and some could not be opened with
                your passphrase.
              </p>
            )}
          </div>
        )}

        {destructive && (
          <label className="mt-3 flex items-start gap-2 p-2.5 rounded-xl bg-rose-50 border border-rose-200 cursor-pointer">
            <input
              type="checkbox"
              checked={ackDelete}
              onChange={(e) => setAckDelete(e.target.checked)}
              disabled={busy}
              className="mt-0.5 w-3.5 h-3.5 shrink-0 accent-rose-600"
            />
            <span className="text-[11px] font-bold text-rose-800 leading-relaxed">
              I understand {deleted} {deleted === 1 ? 'thing' : 'things'} I still have will be gone
              for good.
            </span>
          </label>
        )}

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={busy || willWrite === 0 || (destructive && !ackDelete)}
            className={`py-2.5 rounded-2xl text-white text-xs font-bold shadow-sm disabled:opacity-50 inline-flex items-center justify-center gap-1.5 ${
              destructive
                ? 'bg-rose-600 shadow-rose-300/50 hover:bg-rose-700'
                : 'bg-blush-500 shadow-blush-300/50 hover:bg-blush-600'
            }`}
          >
            {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>
              {willWrite === 0
                ? 'Nothing to add'
                : busy
                  ? 'Adding…'
                  : destructive
                    ? `Add, removing ${deleted}`
                    : `Add ${willWrite}`}
            </span>
          </button>
        </div>
      </motion.div>
    </div>
  );
}

export function SyncHubModal({ isOpen, onClose }) {
  const {
    myPeerId,
    partnerId,
    syncStatus,
    isAuthorized,
    isHandshaking,
    isConnecting,
    syncError,
    syncWarning,
    clearSyncError,
    connectToPartner,
    reconnectToPartner,
    unpairPartner,
    syncNow,
    connectionType,
    mailboxEnabled,
    mailboxState,
    syncMailboxNow,
    lastConnectedAt,
  } = useSync();
  const { partnerName, partnerLastActive } = usePeople();
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!isOpen) return;
    const timer = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(timer);
  }, [isOpen]);

  const {
    vaultSalt,
    vaultConfig,
    cryptoKey,
    quickUnlockAvailable,
    quickUnlockEnrolled,
    enableQuickUnlock,
    disableQuickUnlock,
  } = useVault();
  const [quickUnlockPassphrase, setQuickUnlockPassphrase] = useState('');
  const [quickUnlockOpen, setQuickUnlockOpen] = useState(false);
  const [quickUnlockBusy, setQuickUnlockBusy] = useState(false);
  const [quickUnlockNote, setQuickUnlockNote] = useState('');
  const [quickUnlockProblem, setQuickUnlockProblem] = useState('');
  const [partnerInputId, setPartnerInputId] = useState('');
  const [isScannerOpen, setIsScannerOpen] = useState(false);
  const [copySuccess, setCopySuccess] = useState(false);
  const [codeCopied, setCodeCopied] = useState(false);
  const [backupNotice, setBackupNotice] = useState('');
  const [backupError, setBackupError] = useState('');
  const [pairError, setPairError] = useState('');

  const [passphrasePrompt, setPassphrasePrompt] = useState(null);
  const [promptBusy, setPromptBusy] = useState(false);
  const [promptError, setPromptError] = useState('');

  const [importPreview, setImportPreview] = useState(null);
  const [importBusy, setImportBusy] = useState(false);

  const qrCanvasRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const inviteReady = Boolean(myPeerId) && Boolean(vaultSalt);

  const shareUrl = inviteReady
    ? buildInviteUrl(myPeerId, vaultSalt, {
        startDate: vaultConfig?.startDate,
        coupleNames: vaultConfig?.coupleNames,
      })
    : '';

  useEffect(() => {
    if (!isOpen || !inviteReady || !shareUrl || !qrCanvasRef.current) return;

    QRCode.toCanvas(
      qrCanvasRef.current,
      shareUrl,
      {
        width: 190,
        margin: 2,
        errorCorrectionLevel: 'M',
        color: {
          dark: '#1e293b',
          light: '#ffffff',
        },
      },
      (error) => {
        if (error) console.error('QR code generation error:', error);
      }
    );
  }, [isOpen, inviteReady, shareUrl]);

  const handleShareInvite = async () => {
    tap();
    if (!inviteReady) {
      setPairError('Your invite is not quite ready. Give it a second and try again.');
      return;
    }
    const shareData = {
      title: 'Our Private Space 💕',
      text: 'Connect with me on our private space app! Tap to pair our phones directly:',
      url: shareUrl,
    };

    if (navigator.share) {
      try {
        await navigator.share(shareData);
        celebration();
        return;
      } catch {
      }
    }

    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopySuccess(true);
      setTimeout(() => setCopySuccess(false), 2500);
    } catch {
      setPairError('Could not copy the link. Long-press your pairing code above to copy it instead.');
    }
  };

  const handleCopyCode = async () => {
    if (!myPeerId) return;
    tap();
    try {
      await navigator.clipboard.writeText(myPeerId);
      setCodeCopied(true);
      setTimeout(() => setCodeCopied(false), 2000);
    } catch {
    }
  };

  const handleManualConnect = (e) => {
    e.preventDefault();
    setPairError('');
    const raw = partnerInputId.trim();
    if (!raw) return;

    const parsed = parseInvite(raw);
    if (!parsed || !parsed.partnerPeerId) {
      setPairError(
        'That does not look like a pairing code or invite link. Paste the whole link your partner sent you, or their code.'
      );
      return;
    }

    tap();
    connectToPartner(parsed.partnerPeerId);
  };

  const handleScanSuccess = (scannedPayload) => {
    setIsScannerOpen(false);
    setPairError('');
    const parsed = parseInvite(scannedPayload);
    if (!parsed || !parsed.partnerPeerId) {
      setPairError('That QR code is not an Our Space pairing invite.');
      return;
    }
    celebration();
    connectToPartner(parsed.partnerPeerId);
  };

  const closePrompt = () => {
    setPassphrasePrompt(null);
    setPromptError('');
    setPromptBusy(false);
  };

  const QUICK_UNLOCK_PROBLEMS = {
    'wrong-passphrase': 'That passphrase does not match this space. Have another go.',
    cancelled: 'That got stopped partway, so nothing changed. Try again when you are ready.',
    unsupported: 'This phone will not do the fingerprint trick. Your passphrase still works.',
    'no-prf': 'This phone checked your fingerprint, but its passkeys cannot hold a key for us.',
    'no-vault': 'We could not read your space just now. Try again in a moment.',
    'already-registered':
      'This phone already has a key saved for us. Turn it off first, then set it up again.',
    failed: 'That did not finish. Try again in a moment.',
  };

  const handleTurnOnQuickUnlock = async (e) => {
    e.preventDefault();
    tap();
    setQuickUnlockNote('');
    setQuickUnlockProblem('');
    setQuickUnlockBusy(true);

    const result = await enableQuickUnlock(quickUnlockPassphrase);

    setQuickUnlockBusy(false);
    if (result && result.ok) {
      setQuickUnlockPassphrase('');
      setQuickUnlockOpen(false);
      setQuickUnlockNote('Done. Next time, just a touch. 💕');
      return;
    }

    const code = (result && result.code) || 'failed';
    setQuickUnlockProblem(QUICK_UNLOCK_PROBLEMS[code] || QUICK_UNLOCK_PROBLEMS.failed);
  };

  const handleTurnOffQuickUnlock = () => {
    tap();
    disableQuickUnlock();
    setQuickUnlockPassphrase('');
    setQuickUnlockProblem('');
    setQuickUnlockOpen(false);
    setQuickUnlockNote('Turned off. Your passphrase still opens everything.');
  };

  const handleExportBackup = () => {
    tap();
    setBackupNotice('');
    setBackupError('');
    setPromptError('');
    setPassphrasePrompt({ mode: 'export' });
  };

  const runExport = async (passphrase) => {
    setPromptBusy(true);
    setPromptError('');
    let url = null;
    try {
      const meta = await db.vaultMeta.get('config');
      if (!meta || !meta.salt) {
        setPromptError('Nothing is set up on this phone yet, so there is nothing to save.');
        return;
      }

      const matches = await verifyPassphraseAgainstMeta(passphrase, meta);
      if (!matches) {
        setPromptError(
          'That is not the passphrase you open Our Space with. The copy has to use the same one, or nothing could ever bring it back.'
        );
        return;
      }

      const rawData = await db.exportRawDataForBackup();
      const container = await createEncryptedBackup(rawData, passphrase);
      await decryptBackupContainer(container, passphrase);

      const blob = new Blob([JSON.stringify(container)], { type: 'application/json' });
      url = URL.createObjectURL(blob);

      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `our-space-${new Date().toISOString().split('T')[0]}.vault`;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();

      closePrompt();
      setBackupNotice('Copy saved. Only that passphrase opens it. 💕');
      celebration();
    } catch (err) {
      console.error('Could not create the backup:', err);
      setPromptError('We could not save that copy. Please try again.');
    } finally {
      if (url) setTimeout(() => URL.revokeObjectURL(url), 60000);
      setPromptBusy(false);
    }
  };

  const handleImportBackup = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    setBackupNotice('');
    setBackupError('');
    setPromptError('');

    if (file.size > MAX_BACKUP_FILE_BYTES) {
      setBackupError(
        `That file is ${Math.round(file.size / (1024 * 1024))}MB — a bit big. The most we can take is ${MAX_BACKUP_FILE_MB}MB.`
      );
      return;
    }

    try {
      tap();
      const text = await file.text();
      let container;
      try {
        container = JSON.parse(text);
      } catch {
        setBackupError('That does not look like a file Our Space saved.');
        return;
      }
      if (!container || typeof container !== 'object' || Array.isArray(container)) {
        setBackupError('That does not look like a file Our Space saved.');
        return;
      }
      setPassphrasePrompt({ mode: 'import', container });
    } catch (err) {
      console.error('Could not read that file:', err);
      setBackupError('We could not read that file. Please try another one.');
    }
  };

  const runImport = async (passphrase) => {
    setPromptBusy(true);
    setPromptError('');
    try {
      const decrypted = await decryptBackupContainer(passphrasePrompt.container, passphrase);

      if (!cryptoKey) {
        setPromptError('Our Space is locked right now. Unlock it and try again.');
        return;
      }

      const identity = readBackupVaultIdentity(decrypted.tables);
      const localRead = await db.readVaultIdentity();
      const relation = compareVaultIdentity(identity, localRead);

      if (relation === 'unknown' && !localRead.ok) {
        setPromptError(
          'We could not read what is already on this phone, so we stopped. Nothing changed. Close ' +
            'any other tabs with Our Space open and try again.'
        );
        return;
      }

      const plan = await db.planBackupMerge(decrypted.tables, cryptoKey);
      closePrompt();
      setImportPreview({ plan, relation, identity });
    } catch (err) {
      console.error('Could not open that backup file:', err);
      setPromptError('We could not open that file. Check the passphrase and try again.');
    } finally {
      setPromptBusy(false);
    }
  };

  const confirmImport = async () => {
    if (!importPreview) return;
    const plannedDeletes = importPreview.plan?.totals?.deleted || 0;
    setImportBusy(true);
    setBackupError('');
    try {
      const result = await db.applyBackupMerge(importPreview.plan);
      const written = Object.values(result.written || {}).reduce((sum, n) => sum + n, 0);
      const supersededNote = result.supersededSincePreview
        ? ` ${result.supersededSincePreview} already had a newer copy here, so we left those alone.`
        : '';
      const deleteNote =
        plannedDeletes > 0
          ? result.supersededSincePreview
            ? ` Up to ${plannedDeletes} of them removed something you had.`
            : ` ${plannedDeletes} of them removed something you had — those are gone for good.`
          : '';
      setImportPreview(null);
      setBackupNotice(`Added ${written} ${written === 1 ? 'thing' : 'things'}.${deleteNote}${supersededNote}`);
      if (plannedDeletes > 0) tap();
      else celebration();
    } catch (err) {
      console.error('The backup merge failed:', err);
      setImportPreview(null);
      setBackupError('That did not finish. Please try again.');
    } finally {
      setImportBusy(false);
    }
  };

  if (!isOpen) return null;

  let statusDot = 'bg-amber-400';
  let statusLabel = 'Waiting to connect';
  if (isAuthorized) {
    statusDot = 'bg-emerald-500 animate-pulse';
    statusLabel = 'Connected to Partner';
  } else if (isHandshaking) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Making sure it is them…';
  } else if (isConnecting) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Connecting to Partner...';
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 max-h-[90vh] overflow-y-auto relative"
      >
        <button
          onClick={() => {
            tap();
            onClose();
          }}
          className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
        >
          <X className="w-4 h-4" />
        </button>

        <div className="text-center mb-4">
          <h3 className="text-base font-bold text-slate-800">Pair &amp; Sync Hub</h3>
          <p className="text-xs text-slate-400">Your two phones, straight to each other</p>
        </div>

        <div className="mb-4 p-3.5 rounded-2xl bg-blush-50/60 border border-blush-100 space-y-2.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className={`w-2.5 h-2.5 rounded-full ${statusDot}`} />
              <span className="text-xs font-bold text-slate-700">{statusLabel}</span>
            </div>

            {isAuthorized && (
              <button
                onClick={() => {
                  tap();
                  syncNow();
                }}
                className="text-xs font-semibold text-blush-600 inline-flex items-center gap-1 hover:underline"
              >
                <RefreshCw className="w-3 h-3" />
                <span>Sync Now</span>
              </button>
            )}
          </div>

          {isAuthorized && (
            <div className="pt-2 border-t border-blush-100/70 text-[11px] space-y-1">
              <div className="flex items-center justify-between gap-2">
                <span className="text-slate-500 font-medium shrink-0">How you are connected:</span>
                {connectionType === 'direct' ? (
                  <span className="inline-flex items-center gap-1 font-bold text-emerald-700 bg-emerald-100/80 px-2.5 py-0.5 rounded-full border border-emerald-200 shadow-sm">
                    <Zap className="w-3 h-3 text-amber-500 fill-amber-400" />
                    <span>Phone to phone ⚡</span>
                  </span>
                ) : connectionType === 'relayed' ? (
                  <span className="inline-flex items-center gap-1 font-semibold text-indigo-700 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200">
                    <ShieldCheck className="w-3 h-3 text-indigo-500" />
                    <span>Via a helper 🛡️</span>
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full border border-slate-200">
                    <HelpCircle className="w-3 h-3 text-slate-400" />
                    <span>Not sure</span>
                  </span>
                )}
              </div>
              {connectionType !== 'direct' && connectionType !== 'relayed' && (
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  Connected. We cannot tell exactly how it routed, but your things are still
                  private.
                </p>
              )}
            </div>
          )}

          {partnerId && (
            <div className="pt-2 border-t border-blush-100/70 text-[11px] flex items-center justify-between">
              <div className="flex items-center gap-1.5 overflow-hidden">
                <span className="text-slate-500 font-medium">Partner:</span>
                <span className="font-mono text-slate-700 font-bold truncate max-w-[130px]">
                  {partnerId}
                </span>
              </div>
              <div className="flex items-center gap-2">
                {!isAuthorized && (
                  <button
                    type="button"
                    onClick={() => {
                      tap();
                      reconnectToPartner();
                    }}
                    className="inline-flex items-center gap-1 font-bold text-blush-600 hover:text-blush-700 underline text-xs"
                  >
                    <RefreshCw className="w-3 h-3" />
                    <span>Reconnect</span>
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => {
                    if (window.confirm('Unpair from this partner device?')) {
                      unpairPartner();
                    }
                  }}
                  className="text-slate-400 hover:text-slate-600 text-[10px]"
                >
                  Unpair
                </button>
              </div>
            </div>
          )}

          <div className="pt-2 border-t border-blush-100/70 grid grid-cols-2 gap-2">
            <div className="bg-white/80 rounded-xl p-2.5 border border-blush-100/60 shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
              <div className="flex items-center justify-between mb-1">
                <span className="text-[10px] text-slate-500 font-medium truncate">
                  {partnerName ? `${partnerName}'s App` : 'Partner App'}
                </span>
                <span
                  className={`w-2 h-2 rounded-full shrink-0 ${
                    isAuthorized
                      ? 'bg-emerald-500 animate-pulse'
                      : partnerLastActive
                        ? 'bg-slate-400'
                        : 'bg-slate-300'
                  }`}
                />
              </div>
              <p className="text-[11px] font-bold text-slate-700 truncate">
                {isAuthorized
                  ? 'Active now'
                  : partnerLastActive
                    ? `Active ${formatLastSeen(partnerLastActive, now)}`
                    : 'Waiting for sync'}
              </p>
            </div>

            <div className="bg-white/80 rounded-xl p-2.5 border border-blush-100/60 shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
              <div className="flex items-center justify-between mb-1">
                <span className="text-[10px] text-slate-500 font-medium truncate">Last Connected</span>
                <span
                  className={`w-2 h-2 rounded-full shrink-0 ${
                    isAuthorized
                      ? 'bg-emerald-500 animate-pulse'
                      : lastConnectedAt
                        ? 'bg-indigo-400'
                        : 'bg-slate-300'
                  }`}
                />
              </div>
              <p className="text-[11px] font-bold text-slate-700 truncate">
                {isAuthorized
                  ? 'Connected now'
                  : lastConnectedAt
                    ? formatLastConnected(lastConnectedAt, now)
                    : 'Not yet paired'}
              </p>
            </div>
          </div>

          {syncError && (
            <div className="pt-1.5">
              <div className="flex items-start gap-2 p-2.5 rounded-xl bg-rose-50 border border-rose-200">
                <AlertTriangle className="w-3.5 h-3.5 text-rose-500 mt-0.5 shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-[11px] font-bold text-rose-700 leading-relaxed">
                    {syncError.text}
                  </p>
                  {syncError.code === 'passphrase_mismatch' && (
                    <p className="text-[10px] text-rose-600 mt-1 leading-relaxed">
                      Both phones must use the exact same secret passphrase. Re-enter it on one
                      device from the lock screen, then pair again.
                    </p>
                  )}
                  <div className="flex items-center gap-3 mt-1.5">
                    {partnerId && (
                      <button
                        type="button"
                        onClick={() => {
                          tap();
                          reconnectToPartner();
                        }}
                        className="text-[10px] font-bold text-rose-700 underline"
                      >
                        Try again
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => {
                        tap();
                        clearSyncError();
                      }}
                      className="text-[10px] font-bold text-rose-600 underline"
                    >
                      Dismiss
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {!syncError && syncWarning && (
            <div className="pt-1.5 flex items-start gap-2 text-[10px] text-amber-700 bg-amber-50 p-2 rounded-xl border border-amber-200/60 leading-relaxed">
              <ShieldAlert className="w-3 h-3 mt-0.5 shrink-0 text-amber-500" />
              <span>{syncWarning.text}</span>
            </div>
          )}

          {syncStatus.state === 'syncing' && (
            <p className="text-[10px] text-slate-500 font-medium">Syncing with your partner...</p>
          )}
        </div>

        {mailboxEnabled && (
          <div className="mb-4 p-3.5 rounded-2xl bg-indigo-50/60 border border-indigo-100">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Inbox className="w-3.5 h-3.5 text-indigo-500 shrink-0" />
                <span className="text-xs font-bold text-slate-700">
                  {mailboxState.state === 'syncing'
                    ? 'Checking for things…'
                    : mailboxState.state === 'failed'
                      ? 'Could not check just now'
                      : 'Works even when you are apart'}
                </span>
              </div>
              <button
                type="button"
                disabled={mailboxState.state === 'syncing'}
                onClick={() => {
                  tap();
                  syncMailboxNow();
                }}
                className="text-xs font-semibold text-indigo-600 inline-flex items-center gap-1 hover:underline disabled:opacity-40 shrink-0"
              >
                <RefreshCw className="w-3 h-3" />
                <span>Check now</span>
              </button>
            </div>
            <p className="text-[10px] text-slate-500 leading-relaxed mt-1.5">
              {mailboxState.state === 'failed'
                ? 'No connection right now. It will try again on its own.'
                : 'Anything either of you writes is waiting for the other next time they open this, even if you are never here at the same time.'}
            </p>
          </div>
        )}

        <WhoIsWho />

        <div className="text-center bg-slate-50 p-4 rounded-2xl border border-slate-200/70 mb-4">
          <p className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-2">
            Your Device Pairing QR
          </p>
          {inviteReady ? (
            <div className="inline-block p-2 bg-white rounded-xl shadow-sm border border-slate-200">
              <canvas ref={qrCanvasRef} className="mx-auto block" />
            </div>
          ) : (
            <div className="inline-flex flex-col items-center justify-center gap-2 w-[206px] h-[206px] bg-white rounded-xl shadow-sm border border-slate-200 px-4">
              <Loader2 className="w-5 h-5 text-slate-300 animate-spin" />
              <p className="text-[10px] text-slate-400 leading-relaxed">Preparing your invite…</p>
            </div>
          )}

          <div className="mt-3 flex items-center justify-center gap-2">
            <button
              onClick={handleCopyCode}
              type="button"
              className="inline-flex items-center gap-1.5 text-xs font-mono font-bold text-slate-600 bg-white px-3 py-1.5 rounded-lg border border-slate-200 hover:bg-slate-50 transition"
              title="Click to copy your Device ID"
            >
              <span>{myPeerId || 'Generating...'}</span>
              <Copy className="w-3.5 h-3.5 text-slate-400" />
            </button>
            {codeCopied && <span className="text-[10px] text-emerald-600 font-bold">Copied ID!</span>}
          </div>

          <div className="mt-3">
            <BouncyButton
              onClick={handleShareInvite}
              disabled={!inviteReady}
              className="w-full py-2.5 text-xs gap-1.5 font-bold shadow-sm disabled:opacity-50"
            >
              <Share2 className="w-4 h-4" />
              <span>
                {copySuccess
                  ? 'Link Copied to Clipboard!'
                  : inviteReady
                    ? 'Share Pairing Link (WhatsApp)'
                    : 'Preparing invite…'}
              </span>
            </BouncyButton>
          </div>
        </div>

        <div className="space-y-3 mb-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-700">Connect to Partner's Phone</span>
            <button
              onClick={() => {
                tap();
                setPairError('');
                setIsScannerOpen(true);
              }}
              className="inline-flex items-center gap-1 text-xs font-bold text-blush-600 hover:text-blush-700"
            >
              <Camera className="w-3.5 h-3.5" />
              <span>Scan Partner's QR</span>
            </button>
          </div>

          <form onSubmit={handleManualConnect} className="flex gap-2">
            <input
              type="text"
              value={partnerInputId}
              onChange={(e) => setPartnerInputId(e.target.value)}
              placeholder="Paste Partner's ID or Link..."
              className="flex-1 px-3 py-2 text-xs bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
            />
            <BouncyButton type="submit" className="py-2 px-4 text-xs font-bold">
              Pair
            </BouncyButton>
          </form>

          {pairError && (
            <p className="text-[10px] text-rose-600 font-semibold leading-relaxed">{pairError}</p>
          )}

          <p className="text-[10px] text-slate-400 leading-relaxed">
            Only pair with a code you recognise.
          </p>
        </div>

        {quickUnlockAvailable && (
          <div className="pt-3 border-t border-slate-100 mb-4">
            <p className="text-[11px] font-bold text-slate-600 mb-2 flex items-center gap-1.5">
              <Fingerprint className="w-3.5 h-3.5 text-blush-500" />
              <span>Open with a touch</span>
            </p>

            {quickUnlockEnrolled ? (
              <div className="flex items-center justify-between gap-3">
                <p className="text-[10px] text-slate-500 leading-relaxed flex-1">
                  This phone opens your space with your fingerprint or face.
                </p>
                <button
                  type="button"
                  onClick={handleTurnOffQuickUnlock}
                  className="text-[11px] font-bold text-slate-500 hover:text-rose-600 underline shrink-0"
                >
                  Turn off
                </button>
              </div>
            ) : quickUnlockOpen ? (
              <form onSubmit={handleTurnOnQuickUnlock} className="space-y-2">
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  Type your passphrase once more and this phone will remember it for you.
                  Anyone who can unlock this phone will be able to open your space.
                </p>
                <input
                  type="password"
                  value={quickUnlockPassphrase}
                  onChange={(e) => setQuickUnlockPassphrase(e.target.value)}
                  placeholder="Your passphrase"
                  autoComplete="current-password"
                  className="w-full px-3 py-2 text-xs bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => {
                      setQuickUnlockOpen(false);
                      setQuickUnlockPassphrase('');
                      setQuickUnlockProblem('');
                    }}
                    className="py-2 rounded-xl border border-slate-200 text-[11px] font-bold text-slate-600 hover:bg-slate-50"
                  >
                    Not now
                  </button>
                  <BouncyButton
                    type="submit"
                    disabled={quickUnlockBusy || !quickUnlockPassphrase.trim()}
                    className="py-2 text-[11px] font-bold disabled:opacity-50"
                  >
                    {quickUnlockBusy ? 'Setting up…' : 'Set it up'}
                  </BouncyButton>
                </div>
              </form>
            ) : (
              <div className="flex items-center justify-between gap-3">
                <p className="text-[10px] text-slate-500 leading-relaxed flex-1">
                  Skip typing the passphrase on this phone every time.
                </p>
                <button
                  type="button"
                  onClick={() => {
                    tap();
                    setQuickUnlockNote('');
                    setQuickUnlockProblem('');
                    setQuickUnlockOpen(true);
                  }}
                  className="text-[11px] font-bold text-blush-600 hover:text-blush-700 underline shrink-0"
                >
                  Set it up
                </button>
              </div>
            )}

            {quickUnlockNote && (
              <p className="text-[10px] text-emerald-600 font-semibold mt-2">{quickUnlockNote}</p>
            )}

            {quickUnlockProblem && (
              <p role="alert" className="text-[10px] text-rose-600 font-semibold mt-2 leading-relaxed">
                {quickUnlockProblem}
              </p>
            )}
          </div>
        )}

        <div className="pt-3 border-t border-slate-100">
          <p className="text-[11px] font-bold text-slate-600 mb-2 flex items-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            <span>Keep a copy, just in case</span>
          </p>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={handleExportBackup}
              className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Save a copy</span>
            </button>

            <label className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
              <Upload className="w-3.5 h-3.5" />
              <span>Bring in a copy</span>
              <input
                type="file"
                accept=".vault,.json,application/json"
                onChange={handleImportBackup}
                className="hidden"
              />
            </label>
          </div>

          {backupError && (
            <p className="text-[10px] text-rose-600 font-semibold text-center mt-2 leading-relaxed">
              {backupError}
            </p>
          )}
          {backupNotice && (
            <p className="text-[10px] text-emerald-600 font-medium text-center mt-2 leading-relaxed">
              {backupNotice}
            </p>
          )}
        </div>
      </motion.div>

      <QRScannerModal
        isOpen={isScannerOpen}
        onClose={() => setIsScannerOpen(false)}
        onScanSuccess={handleScanSuccess}
      />

      {passphrasePrompt?.mode === 'export' && (
        <PassphrasePrompt
          title="Lock this copy"
          description="Use the same passphrase you open Our Space with. We check it before writing the file, so a typo cannot leave you with a copy nobody can open."
          requireConfirm
          submitLabel="Save the copy"
          busy={promptBusy}
          error={promptError}
          onSubmit={runExport}
          onCancel={closePrompt}
        />
      )}

      {passphrasePrompt?.mode === 'import' && (
        <PassphrasePrompt
          title="Open this copy"
          description="Enter the passphrase this file was saved with. Nothing is added yet — you will see exactly what would change first."
          requireConfirm={false}
          submitLabel="Take a look"
          busy={promptBusy}
          error={promptError}
          onSubmit={runImport}
          onCancel={closePrompt}
        />
      )}

      {importPreview && (
        <ImportPreview
          plan={importPreview.plan}
          relation={importPreview.relation}
          busy={importBusy}
          onConfirm={confirmImport}
          onCancel={() => setImportPreview(null)}
        />
      )}
    </div>
  );
}

export default SyncHubModal;
