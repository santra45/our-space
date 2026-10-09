import React, { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, Camera, Image as ImageIcon, Sparkles, AlertTriangle } from 'lucide-react';
import { compressImage } from '../../utils/imageCompression';
import { encryptBlob, generateUrlSafeNonce } from '../../services/crypto';
import db, { MAX_IMAGE_BLOB_BYTES } from '../../db';
import peerSync from '../../services/peerSync';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

function todayLocalISO() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

const MAX_IMAGE_MB = Math.round(MAX_IMAGE_BLOB_BYTES / (1024 * 1024));

export function AddMemoryModal({ isOpen, onClose, cryptoKey }) {
  const [selectedFile, setSelectedFile] = useState(null);
  const [previewUrl, setPreviewUrl] = useState(null);
  const [caption, setCaption] = useState('');
  const [date, setDate] = useState(todayLocalISO);
  const [saving, setSaving] = useState(false);
  const [statusText, setStatusText] = useState('');
  const [error, setError] = useState('');

  const fileInputRef = useRef(null);
  const cameraInputRef = useRef(null);
  const previewUrlRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const setPreview = (url) => {
    if (previewUrlRef.current && previewUrlRef.current !== url) {
      URL.revokeObjectURL(previewUrlRef.current);
    }
    previewUrlRef.current = url;
    setPreviewUrl(url);
  };

  useEffect(() => {
    return () => {
      if (previewUrlRef.current) {
        URL.revokeObjectURL(previewUrlRef.current);
        previewUrlRef.current = null;
      }
    };
  }, []);

  const handleFileChange = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    tap();
    setError('');
    setSelectedFile(file);
    setPreview(URL.createObjectURL(file));
  };

  const clearPhoto = () => {
    setSelectedFile(null);
    setPreview(null);
    setError('');
  };

  const handleSave = async (e) => {
    e.preventDefault();
    if (saving || !selectedFile) return;

    if (!cryptoKey) {
      setError('Our Space is locked. Unlock it and try again.');
      return;
    }

    setError('');

    try {
      setSaving(true);
      tap();

      setStatusText('Getting it ready...');
      const { blob, mime } = await compressImage(selectedFile, {
        maxWidth: 1440,
        maxHeight: 1440,
        quality: 0.85,
      });

      setStatusText('Tucking it away safely...');
      const imageBlob = await encryptBlob(blob, cryptoKey);

      if (imageBlob.byteLength > MAX_IMAGE_BLOB_BYTES) {
        const mb = (imageBlob.byteLength / (1024 * 1024)).toFixed(1);
        throw new Error(
          `the compressed photo is still ${mb}MB, over the ${MAX_IMAGE_MB}MB limit, so it would never reach your partner. Try a smaller image.`
        );
      }

      setStatusText('Saving to your scrapbook...');
      const row = await db.putEncrypted(
        'memories',
        {
          id: `mem-${Date.now().toString(36)}-${generateUrlSafeNonce(6)}`,
          date,
          caption: caption.trim() || 'Precious moment 💕',
          mime,
          imageBlob,
          updatedAt: peerSync.getSyncSafeTimestamp(),
          deleted: false,
        },
        cryptoKey
      );

      peerSync.broadcastLiveRecord('memories', row);

      celebration();
      fireHeartConfetti();
      handleClose();
    } catch (err) {
      setError(
        err?.message
          ? `Could not save this memory: ${err.message}`
          : 'Could not save this memory. Please try again.'
      );
    } finally {
      setSaving(false);
      setStatusText('');
    }
  };

  const handleClose = () => {
    setPreview(null);
    setSelectedFile(null);
    setCaption('');
    setDate(todayLocalISO());
    setError('');
    onClose();
  };

  if (!isOpen) return null;

  return (
    <AnimatePresence>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-sm">
        <motion.div
          initial={{ opacity: 0, scale: 0.9, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.9, y: 20 }}
          className="w-full max-h-[90vh] max-w-sm overflow-y-auto overscroll-contain bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 relative"
        >
          <button
            onClick={handleClose}
            disabled={saving}
            className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200 disabled:opacity-40"
          >
            <X className="w-4 h-4" />
          </button>

          <div className="flex items-center gap-2 mb-4">
            <div className="w-8 h-8 rounded-full bg-blush-100 text-blush-500 flex items-center justify-center">
              <Sparkles className="w-4 h-4" />
            </div>
            <div>
              <h3 className="text-base font-bold text-slate-800">Add New Polaroid</h3>
              <p className="text-[11px] text-slate-400">Kept just between you two</p>
            </div>
          </div>

          <form onSubmit={handleSave} className="space-y-4">
            {previewUrl ? (
              <div className="relative aspect-[4/5] rounded-2xl overflow-hidden bg-slate-100 border-2 border-blush-200">
                <img src={previewUrl} alt="Preview" className="w-full h-full object-contain" />
                <button
                  type="button"
                  onClick={clearPhoto}
                  disabled={saving}
                  className="absolute bottom-3 right-3 px-3 py-1.5 bg-black/60 text-white rounded-xl text-xs font-semibold backdrop-blur-sm hover:bg-black/80 disabled:opacity-40"
                >
                  Change Photo
                </button>
              </div>
            ) : (
              <div className="border-2 border-dashed border-blush-200 rounded-2xl p-6 text-center bg-blush-50/50">
                <p className="text-xs text-slate-600 font-semibold mb-3">
                  Capture or choose a photo together
                </p>
                <div className="flex justify-center gap-3">
                  <BouncyButton
                    onClick={() => cameraInputRef.current?.click()}
                    variant="primary"
                    className="py-2.5 px-4 text-xs gap-1.5"
                  >
                    <Camera className="w-4 h-4" />
                    <span>Camera</span>
                  </BouncyButton>
                  <BouncyButton
                    onClick={() => fileInputRef.current?.click()}
                    variant="secondary"
                    className="py-2.5 px-4 text-xs gap-1.5"
                  >
                    <ImageIcon className="w-4 h-4" />
                    <span>Gallery</span>
                  </BouncyButton>
                </div>

                <input
                  type="file"
                  ref={cameraInputRef}
                  accept="image/*"
                  capture="environment"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <input
                  type="file"
                  ref={fileInputRef}
                  accept="image/*"
                  onChange={handleFileChange}
                  className="hidden"
                />
              </div>
            )}

            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">
                Polaroid Caption
              </label>
              <input
                type="text"
                value={caption}
                onChange={(e) => setCaption(e.target.value)}
                placeholder="Write a sweet note or memory..."
                required
                maxLength={280}
                className="w-full px-3 py-2.5 bg-white border border-blush-200 rounded-xl text-sm font-handwriting text-lg focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-300 placeholder:font-sans placeholder:text-xs"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">
                Date Taken
              </label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                required
                className="w-full px-3 py-2 bg-white border border-blush-200 rounded-xl text-xs focus:outline-none focus:ring-2 focus:ring-blush-400"
              />
            </div>

            {error && (
              <div
                role="alert"
                className="flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5"
              >
                <AlertTriangle className="w-4 h-4 text-rose-500 shrink-0 mt-0.5" />
                <p className="text-[11px] leading-relaxed text-rose-700">{error}</p>
              </div>
            )}

            <BouncyButton
              type="submit"
              disabled={saving || !selectedFile}
              className="w-full py-3 text-sm font-bold shadow-md shadow-blush-300/40"
            >
              {saving ? statusText || 'Developing Polaroid...' : 'Pin it up 💕'}
            </BouncyButton>
          </form>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}

export default AddMemoryModal;
