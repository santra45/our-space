/**
 * src/components/sync/SyncHubModal.jsx
 * P2P WebRTC connection hub: QR code generation, WhatsApp share link, sync
 * controls, and encrypted vault backup/restore.
 *
 * Connection indicators here are driven by `isAuthorized` only. peerSync reports
 * `handshaking` for a data channel that opened but has not proved it holds the
 * vault key; rendering that as "Connected to Partner" told the user a stranger
 * was their partner.
 *
 * The backup passphrase is collected through a masked in-app prompt with a
 * confirm field and is verified against the live vault canary before a single
 * byte is written. A typo used to produce a .vault file that nobody, including
 * its owner, could ever open.
 */
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
  ShieldAlert,
  Zap,
  HelpCircle,
  Eye,
  EyeOff,
  Loader2,
} from 'lucide-react';
import QRCode from 'qrcode';
import { useSync } from '../../context/SyncContext';
import { useVault } from '../../context/VaultContext';
import { buildInviteUrl, parseInvite } from '../../utils/invite';
import BouncyButton from '../common/BouncyButton';
import QRScannerModal from './QRScannerModal';
import { useHaptics } from '../../hooks/useHaptics';
import db, { MAX_BACKUP_FILE_BYTES } from '../../db';
import {
  createEncryptedBackup,
  decryptBackupContainer,
  verifyPassphraseAgainstMeta,
  normalizePassphrase,
  MIN_PASSPHRASE_LENGTH,
} from '../../services/crypto';

const MAX_BACKUP_FILE_MB = Math.round(MAX_BACKUP_FILE_BYTES / (1024 * 1024));

/**
 * Masked passphrase prompt. Replaces window.prompt, which rendered the vault
 * passphrase as plain text on screen and offered no way to confirm it.
 */
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
  } = useSync();
  const { vaultSalt, vaultConfig } = useVault();
  const [partnerInputId, setPartnerInputId] = useState('');
  const [isScannerOpen, setIsScannerOpen] = useState(false);
  const [copySuccess, setCopySuccess] = useState(false);
  const [codeCopied, setCodeCopied] = useState(false);
  const [backupNotice, setBackupNotice] = useState('');
  const [backupError, setBackupError] = useState('');
  const [pairError, setPairError] = useState('');

  // { mode: 'export' | 'import', container?: Object }
  const [passphrasePrompt, setPassphrasePrompt] = useState(null);
  const [promptBusy, setPromptBusy] = useState(false);
  const [promptError, setPromptError] = useState('');

  const qrCanvasRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const shareUrl = buildInviteUrl(myPeerId, vaultSalt, {
    startDate: vaultConfig?.startDate,
    coupleNames: vaultConfig?.coupleNames,
  });

  // Render QR Code on canvas
  useEffect(() => {
    if (!isOpen || !myPeerId || !qrCanvasRef.current) return;

    QRCode.toCanvas(
      qrCanvasRef.current,
      shareUrl || myPeerId,
      {
        width: 190,
        margin: 1,
        color: {
          dark: '#1e293b',
          light: '#ffffff',
        },
      },
      (error) => {
        if (error) console.error('QR code generation error:', error);
      }
    );
  }, [isOpen, myPeerId, shareUrl]);

  // WhatsApp / Native Web Share API trigger
  const handleShareInvite = async () => {
    tap();
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
        // user cancelled or share failed, fallback to copy
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
      // clipboard blocked; the id is visible on the button anyway
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
        'That does not look like a pairing code or invite link. Paste the whole link your partner shared, or their code from the hub.'
      );
      return;
    }

    tap();
    connectToPartner(parsed.partnerPeerId);
  };

  /** Receives the RAW scanned payload; parseInvite is the only parser. */
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

  /* --------------------------------------------------------------------- *
   * Encrypted backup
   * --------------------------------------------------------------------- */

  const closePrompt = () => {
    setPassphrasePrompt(null);
    setPromptError('');
    setPromptBusy(false);
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
      // D3: prove the typed passphrase actually opens THIS vault before writing
      // anything. Without this, one typo produces an undecryptable .vault.
      const meta = await db.vaultMeta.get('config');
      if (!meta || !meta.salt) {
        setPromptError('This vault has no key material on this device, so a backup cannot be verified.');
        return;
      }

      const matches = await verifyPassphraseAgainstMeta(passphrase, meta);
      if (!matches) {
        setPromptError(
          'That is not this vault’s passphrase. The backup must use the same passphrase you unlock with, otherwise nothing could ever restore it.'
        );
        return;
      }

      const rawData = await db.exportRawDataForBackup();
      const container = await createEncryptedBackup(rawData, passphrase);
      // Round-trip the container before handing it over.
      await decryptBackupContainer(container, passphrase);

      const blob = new Blob([JSON.stringify(container)], { type: 'application/json' });
      url = URL.createObjectURL(blob);

      // P5: Firefox aborts a download whose anchor was never in the document,
      // and aborts it again if the object URL is revoked in the same tick.
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `OurSpace-Encrypted-${new Date().toISOString().split('T')[0]}.vault`;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();

      closePrompt();
      setBackupNotice('Encrypted .vault backup created and verified. Only that passphrase can open it.');
      celebration();
    } catch (err) {
      setPromptError('Could not create the backup: ' + (err?.message || 'unknown error'));
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

    // P5: without a cap, readAsText on a multi-GB file pulls it all into a
    // string and hangs the tab before anything is even validated.
    if (file.size > MAX_BACKUP_FILE_BYTES) {
      setBackupError(
        `That file is ${Math.round(file.size / (1024 * 1024))}MB. Backups are capped at ${MAX_BACKUP_FILE_MB}MB.`
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
        setBackupError('That file is not a valid .vault backup (it is not readable JSON).');
        return;
      }
      if (!container || typeof container !== 'object' || Array.isArray(container)) {
        setBackupError('That file is not a valid .vault backup.');
        return;
      }
      setPassphrasePrompt({ mode: 'import', container });
    } catch (err) {
      setBackupError('Could not read that file: ' + (err?.message || 'unknown error'));
    }
  };

  const runImport = async (passphrase) => {
    setPromptBusy(true);
    setPromptError('');
    try {
      // Decrypt and verify the 128-bit GCM tag. Wrong key or tampering throws.
      const decrypted = await decryptBackupContainer(passphrasePrompt.container, passphrase);
      const result = await db.importRawDataFromBackup(decrypted.tables);

      const total = Object.values(result.imported || {}).reduce((sum, n) => sum + n, 0);
      const skippedNote = result.skipped
        ? ` ${result.skipped} unreadable record(s) were skipped.`
        : '';
      // vaultMeta is deliberately not importable: restoring it would replace the
      // live salt and orphan everything created since the backup was taken.
      const metaNote = (result.skippedTables || []).includes('vaultMeta')
        ? ' Your vault key was left untouched, so records made since this backup still open.'
        : '';

      closePrompt();
      setBackupNotice(`Backup verified and restored: ${total} record(s).${skippedNote}${metaNote}`);
      celebration();
    } catch (err) {
      setPromptError(
        'Backup rejected: ' + (err?.message || 'incorrect passphrase or corrupted backup file')
      );
    } finally {
      setPromptBusy(false);
    }
  };

  if (!isOpen) return null;

  /* --------------------------------------------------------------------- *
   * Status rendering
   * --------------------------------------------------------------------- */

  let statusDot = 'bg-amber-400';
  let statusLabel = 'Awaiting Connection';
  if (isAuthorized) {
    statusDot = 'bg-emerald-500 animate-pulse';
    statusLabel = 'Connected to Partner';
  } else if (isHandshaking) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Verifying partner (not trusted yet)...';
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
          <p className="text-xs text-slate-400">Direct peer-to-peer connection</p>
        </div>

        {/* Live Status */}
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

          {/* X3: the route badge reports what was actually measured. */}
          {isAuthorized && (
            <div className="pt-2 border-t border-blush-100/70 text-[11px] space-y-1">
              <div className="flex items-center justify-between gap-2">
                <span className="text-slate-500 font-medium shrink-0">Connection Route:</span>
                {connectionType === 'direct' ? (
                  <span className="inline-flex items-center gap-1 font-bold text-emerald-700 bg-emerald-100/80 px-2.5 py-0.5 rounded-full border border-emerald-200 shadow-sm">
                    <Zap className="w-3 h-3 text-amber-500 fill-amber-400" />
                    <span>Direct P2P ⚡</span>
                  </span>
                ) : connectionType === 'relayed' ? (
                  <span className="inline-flex items-center gap-1 font-semibold text-indigo-700 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200">
                    <ShieldCheck className="w-3 h-3 text-indigo-500" />
                    <span>Relayed 🛡️</span>
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full border border-slate-200">
                    <HelpCircle className="w-3 h-3 text-slate-400" />
                    <span>Unknown</span>
                  </span>
                )}
              </div>
              {connectionType !== 'direct' && connectionType !== 'relayed' && (
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  The browser has not reported which network path this connection took. Your data is
                  end-to-end encrypted either way, but this app cannot honestly claim the link is
                  phone-to-phone right now.
                </p>
              )}
            </div>
          )}

          {/* Paired Partner Info & Reconnect Button */}
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

          {/* X4: fatal sync problems. peerSync emits these as auth_failed /
              ice_failed / error, none of which the old gate ever matched. */}
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

          {/* Non-fatal problem alongside a live connection. */}
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

        {/* My QR Code Card */}
        <div className="text-center bg-slate-50 p-4 rounded-2xl border border-slate-200/70 mb-4">
          <p className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-2">
            Your Device Pairing QR
          </p>
          <div className="inline-block p-2 bg-white rounded-xl shadow-sm border border-slate-200">
            <canvas ref={qrCanvasRef} className="mx-auto block" />
          </div>

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

          {/* 1-Tap Share via WhatsApp / Messaging */}
          <div className="mt-3">
            <BouncyButton
              onClick={handleShareInvite}
              className="w-full py-2.5 text-xs gap-1.5 font-bold shadow-sm"
            >
              <Share2 className="w-4 h-4" />
              <span>
                {copySuccess ? 'Link Copied to Clipboard!' : 'Share Pairing Link (WhatsApp)'}
              </span>
            </BouncyButton>
          </div>
        </div>

        {/* Connect to Partner Section */}
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
              <span>Scan Her QR</span>
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
            Pairing opens a direct link, which shares your IP address with that device. Only pair
            with a code you recognise.
          </p>
        </div>

        {/* Encrypted Backup & Restore section */}
        <div className="pt-3 border-t border-slate-100">
          <p className="text-[11px] font-bold text-slate-600 mb-2 flex items-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            <span>Encrypted Vault Backup (Failsafe)</span>
          </p>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={handleExportBackup}
              className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export .vault</span>
            </button>

            <label className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
              <Upload className="w-3.5 h-3.5" />
              <span>Import .vault</span>
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

      {/* In-app camera scanner modal */}
      <QRScannerModal
        isOpen={isScannerOpen}
        onClose={() => setIsScannerOpen(false)}
        onScanSuccess={handleScanSuccess}
      />

      {/* D3: masked passphrase entry, verified before anything is written. */}
      {passphrasePrompt?.mode === 'export' && (
        <PassphrasePrompt
          title="Encrypt this backup"
          description="Use the same passphrase you unlock this vault with. It is checked against your vault before the file is written, so a typo cannot produce a backup nobody can open."
          requireConfirm
          submitLabel="Create backup"
          busy={promptBusy}
          error={promptError}
          onSubmit={runExport}
          onCancel={closePrompt}
        />
      )}

      {passphrasePrompt?.mode === 'import' && (
        <PassphrasePrompt
          title="Unlock this backup"
          description="Enter the passphrase this .vault file was encrypted with. Your current vault key is never replaced by a restore."
          requireConfirm={false}
          submitLabel="Restore backup"
          busy={promptBusy}
          error={promptError}
          onSubmit={runImport}
          onCancel={closePrompt}
        />
      )}
    </div>
  );
}

export default SyncHubModal;
