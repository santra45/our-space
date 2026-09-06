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
} from 'lucide-react';
import QRCode from 'qrcode';
import { useSync } from '../../context/SyncContext';
import { useVault } from '../../context/VaultContext';
import BouncyButton from '../common/BouncyButton';
import QRScannerModal from './QRScannerModal';
import { useHaptics } from '../../hooks/useHaptics';
import db from '../../db';

export function SyncHubModal({ isOpen, onClose }) {
  const { myPeerId, partnerId, syncStatus, isPartnerConnected, connectToPartner, syncNow } = useSync();
  const [partnerInputId, setPartnerInputId] = useState('');
  const [isScannerOpen, setIsScannerOpen] = useState(false);
  const [copySuccess, setCopySuccess] = useState(false);
  const [backupNotice, setBackupNotice] = useState('');

  const qrCanvasRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const shareUrl = typeof window !== 'undefined'
    ? `${window.location.origin}${window.location.pathname}#connect=${myPeerId}`
    : '';

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
      } catch (err) {
        // user cancelled or share failed
      }
    } else {
      // Fallback: Copy to clipboard
      try {
        await navigator.clipboard.writeText(shareUrl);
        setCopySuccess(true);
        setTimeout(() => setCopySuccess(false), 2500);
      } catch (e) {
        alert('Could not copy link: ' + shareUrl);
      }
    }
  };

  const handleManualConnect = (e) => {
    e.preventDefault();
    if (!partnerInputId.trim()) return;
    tap();
    let target = partnerInputId.trim();
    if (target.includes('#connect=')) {
      target = target.split('#connect=')[1];
    }
    connectToPartner(target);
  };

  const handleScanSuccess = (detectedId) => {
    setIsScannerOpen(false);
    celebration();
    connectToPartner(detectedId);
  };

  // Encrypted Backup Export
  const handleExportBackup = async () => {
    try {
      tap();
      const backup = await db.exportEncryptedVault();
      const json = JSON.stringify(backup, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = url;
      a.download = `OurSpace-Vault-${new Date().toISOString().split('T')[0]}.vault`;
      a.click();
      URL.revokeObjectURL(url);

      setBackupNotice('Encrypted backup exported! You can safely send this file via WhatsApp.');
      celebration();
    } catch (err) {
      alert('Failed to export backup: ' + err.message);
    }
  };

  // Encrypted Backup Import
  const handleImportBackup = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (event) => {
      try {
        tap();
        const data = JSON.parse(event.target.result);
        await db.importEncryptedVault(data);
        setBackupNotice('Backup imported successfully! Memories restored 💕');
        celebration();
      } catch (err) {
        alert('Invalid backup file: ' + err.message);
      }
    };
    reader.readAsText(file);
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
        <div className="mb-4 p-3 rounded-2xl bg-blush-50/60 border border-blush-100 flex items-center justify-between">
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

        {/* My QR Code Card */}
        <div className="text-center bg-slate-50 p-4 rounded-2xl border border-slate-200/70 mb-4">
          <p className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-2">
            Your Device Pairing QR
          </p>
          <div className="inline-block p-2 bg-white rounded-xl shadow-sm border border-slate-200">
            <canvas ref={qrCanvasRef} className="mx-auto block" />
          </div>

          <div className="mt-3 flex items-center justify-center gap-2">
            <span className="text-xs font-mono font-bold text-slate-600 bg-white px-3 py-1 rounded-lg border border-slate-200">
              {myPeerId || 'Generating...'}
            </span>
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
