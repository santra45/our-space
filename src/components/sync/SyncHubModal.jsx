/**
 * src/components/sync/SyncHubModal.jsx
 * P2P WebRTC connection hub: QR code generation, WhatsApp share link, and sync controls
 */
import React, { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import {
  X,
  Share2,
  QrCode,
  Camera,
  RefreshCw,
  CheckCircle2,
  AlertCircle,
  Copy,
  Download,
  Upload,
  ShieldCheck,
  Zap,
} from 'lucide-react';
import QRCode from 'qrcode';
import { useSync } from '../../context/SyncContext';
import { useVault } from '../../context/VaultContext';
import { buildInviteUrl, parseInvite } from '../../utils/invite';
import BouncyButton from '../common/BouncyButton';
import QRScannerModal from './QRScannerModal';
import { useHaptics } from '../../hooks/useHaptics';
import db from '../../db';
import {
  createEncryptedBackup,
  decryptBackupContainer,
  MIN_PASSPHRASE_LENGTH,
} from '../../services/crypto';

export function SyncHubModal({ isOpen, onClose }) {
  const {
    myPeerId,
    partnerId,
    syncStatus,
    isPartnerConnected,
    connectToPartner,
    syncNow,
    isDirectP2P,
    connectionType,
  } = useSync();
  const { vaultSalt } = useVault();
  const [partnerInputId, setPartnerInputId] = useState('');
  const [isScannerOpen, setIsScannerOpen] = useState(false);
  const [copySuccess, setCopySuccess] = useState(false);
  const [codeCopied, setCodeCopied] = useState(false);
  const [backupNotice, setBackupNotice] = useState('');

  const qrCanvasRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const shareUrl = buildInviteUrl(myPeerId, vaultSalt);

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
      } catch (err) {
        // user cancelled or share failed, fallback to copy
      }
    }

    // Fallback: Copy to clipboard
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopySuccess(true);
      setTimeout(() => setCopySuccess(false), 2500);
    } catch (e) {
      alert('Could not copy link: ' + shareUrl);
    }
  };

  const handleCopyCode = async () => {
    if (!myPeerId) return;
    tap();
    try {
      await navigator.clipboard.writeText(myPeerId);
      setCodeCopied(true);
      setTimeout(() => setCodeCopied(false), 2000);
    } catch {}
  };

  const handleManualConnect = (e) => {
    e.preventDefault();
    const raw = partnerInputId.trim();
    if (!raw) return;

    const parsed = parseInvite(raw);
    if (!parsed || !parsed.partnerPeerId) {
      alert('Invalid Partner Peer ID or Invite Link. Please enter a valid ID (e.g. love-xxxx) or paste the full invite link.');
      return;
    }

    tap();
    connectToPartner(parsed.partnerPeerId);
  };

  const handleScanSuccess = (detectedId) => {
    setIsScannerOpen(false);
    const parsed = parseInvite(detectedId);
    if (!parsed || !parsed.partnerPeerId) {
      alert('Invalid QR code: no valid partner ID detected.');
      return;
    }
    celebration();
    connectToPartner(parsed.partnerPeerId);
  };

  // Encrypted Backup Export: Encrypts the entire backup with user's passphrase as a single AES-GCM container
  const handleExportBackup = async () => {
    try {
      tap();
      const passphrase = window.prompt(`Enter your secret passphrase to encrypt this backup (min ${MIN_PASSPHRASE_LENGTH} chars):`);
      if (!passphrase) return;
      if (passphrase.length < MIN_PASSPHRASE_LENGTH) {
        alert(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`);
        return;
      }

      const rawData = await db.exportRawDataForBackup();
      const encryptedContainer = await createEncryptedBackup(rawData, passphrase);

      const json = JSON.stringify(encryptedContainer, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = url;
      a.download = `OurSpace-Encrypted-${new Date().toISOString().split('T')[0]}.vault`;
      a.click();
      URL.revokeObjectURL(url);

      setBackupNotice('Encrypted .vault backup created! Only your passphrase can decrypt it.');
      celebration();
    } catch {
      alert('Failed to create encrypted backup.');
    }
  };

  // Encrypted Backup Import: Genuinely decrypts and verifies container before modifying IndexedDB
  const handleImportBackup = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (event) => {
      try {
        tap();
        let container;
        try {
          container = JSON.parse(event.target.result);
        } catch {
          alert('Invalid file: not valid JSON.');
          return;
        }

        const passphrase = window.prompt('Enter the passphrase used to encrypt this .vault backup:');
        if (!passphrase) return;

        // Decrypt and verify 128-bit GCM authentication tag. If tampered or wrong key, throws error!
        const decryptedData = await decryptBackupContainer(container, passphrase);
        await db.importRawDataFromBackup(decryptedData.tables);

        setBackupNotice('Backup verified & restored successfully! 💕');
        celebration();
      } catch (err) {
        alert('Backup import rejected: ' + (err.message || 'Incorrect passphrase or corrupted backup file'));
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  if (!isOpen) return null;

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
          <h3 className="text-base font-bold text-slate-800">Pair & Sync Hub</h3>
          <p className="text-xs text-slate-400">Direct peer-to-peer connection</p>
        </div>

        {/* Live Status */}
        <div className="mb-4 p-3.5 rounded-2xl bg-blush-50/60 border border-blush-100 space-y-2.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span
                className={`w-2.5 h-2.5 rounded-full ${
                  isPartnerConnected ? 'bg-emerald-500 animate-pulse' : 'bg-amber-400'
                }`}
              />
              <span className="text-xs font-bold text-slate-700">
                {isPartnerConnected ? 'Connected to Partner' : 'Awaiting Connection'}
              </span>
            </div>

            {isPartnerConnected && (
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

          {/* Direct P2P vs Relayed Indicator Badge */}
          {isPartnerConnected && (
            <div className="flex items-center justify-between pt-2 border-t border-blush-100/70 text-[11px]">
              <span className="text-slate-500 font-medium">Connection Route:</span>
              {isDirectP2P || connectionType === 'direct' ? (
                <span className="inline-flex items-center gap-1 font-bold text-emerald-700 bg-emerald-100/80 px-2.5 py-0.5 rounded-full border border-emerald-200 shadow-sm">
                  <Zap className="w-3 h-3 text-amber-500 fill-amber-400" />
                  <span>Direct P2P ⚡ (Phone-to-Phone)</span>
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 font-semibold text-indigo-700 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200">
                  <ShieldCheck className="w-3 h-3 text-indigo-500" />
                  <span>Relayed 🛡️ (Encrypted E2EE)</span>
                </span>
              )}
            </div>
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
            {codeCopied && (
              <span className="text-[10px] text-emerald-600 font-bold">Copied ID!</span>
            )}
          </div>

          {/* 1-Tap Share via WhatsApp / Messaging */}
          <div className="mt-3">
            <BouncyButton
              onClick={handleShareInvite}
              className="w-full py-2.5 text-xs gap-1.5 font-bold shadow-sm"
            >
              <Share2 className="w-4 h-4" />
              <span>{copySuccess ? 'Link Copied to Clipboard!' : 'Share Pairing Link (WhatsApp)'}</span>
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
              <input type="file" accept=".vault,.json" onChange={handleImportBackup} className="hidden" />
            </label>
          </div>

          {backupNotice && (
            <p className="text-[10px] text-emerald-600 font-medium text-center mt-2">
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
    </div>
  );
}

export default SyncHubModal;
