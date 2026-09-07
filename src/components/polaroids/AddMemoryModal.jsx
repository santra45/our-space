/**
 * src/components/polaroids/AddMemoryModal.jsx
 * Upload modal with camera capture, client-side compression, and AES-GCM encryption.
 *
 * SCHEMA v2: the record is written through db.putEncrypted(), so `date`, `caption`
 * and the blob's `mime` all travel inside the single encrypted envelope. Only
 * `id`, `updatedAt` and `deleted` remain readable without the vault key. The
 * image bytes stay a top-level Uint8Array - they are independently sealed by
 * encryptBlob() and must not be inflated through JSON.
 */
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

/**
 * Today in the user's OWN timezone.
 * `new Date().toISOString().split('T')[0]` is UTC, so east of Greenwich it
 * returns yesterday for the entire early morning - IST users adding a photo at
 * 2am would have it filed under the previous day.
 */
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
  // Single owner of the live preview ObjectURL. Every path that replaces or
  // clears the preview goes through setPreview(), so a URL can never be
  // overwritten without first being revoked (P4).
  const previewUrlRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const setPreview = (url) => {
    if (previewUrlRef.current && previewUrlRef.current !== url) {
      URL.revokeObjectURL(previewUrlRef.current);
    }
    previewUrlRef.current = url;
    setPreviewUrl(url);
  };

  // Last line of defence: if this modal is ever unmounted while a preview is
  // open, the URL still gets released.
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
    // Clear the input so picking the SAME file twice still fires a change event.
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
      setError('Your vault is locked. Unlock it and try again.');
      return;
    }

    setError('');

    try {
      setSaving(true);
      tap();

      // Step 1: shrink on the canvas. Throws (rather than passing the raw
      // original through) if the browser cannot re-encode it.
      setStatusText('Optimizing photo...');
      const { blob, mime } = await compressImage(selectedFile, {
        maxWidth: 1440,
        maxHeight: 1440,
        quality: 0.85,
      });

      // Step 2: zero-knowledge AES-GCM 256 on the image bytes.
      setStatusText('Encrypting with AES-GCM 256...');
      const imageBlob = await encryptBlob(blob, cryptoKey);

      // Anything over this is refused by the sync layer on both ends, so catch it
      // here where we can still tell the user something useful.
      if (imageBlob.byteLength > MAX_IMAGE_BLOB_BYTES) {
        const mb = (imageBlob.byteLength / (1024 * 1024)).toFixed(1);
        throw new Error(
          `the compressed photo is still ${mb}MB, over the ${MAX_IMAGE_MB}MB limit, so it would never reach your partner. Try a smaller image.`
        );
      }

      // Step 3: seal the whole record. date/caption/mime go inside the envelope.
      setStatusText('Saving to your vault...');
      const row = await db.putEncrypted(
        'memories',
        {
          id: `mem-${Date.now().toString(36)}-${generateUrlSafeNonce(6)}`,
          date,
          caption: caption.trim() || 'Precious moment 💕',
          mime,
          imageBlob,
          // Monotonic, and never behind what the partner has issued - a skewed
          // device clock otherwise loses (or wins) every merge forever.
          updatedAt: peerSync.getSyncSafeTimestamp(),
          deleted: false,
        },
        cryptoKey
      );

      // Step 4: push to the partner. Never rejects; a failure surfaces as a sync
      // warning and the record is picked up by the next manifest exchange.
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
          className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 relative overflow-hidden"
        >
          {/* Close button */}
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
              <p className="text-[11px] text-slate-400">Encrypted before saving</p>
            </div>
          </div>

          <form onSubmit={handleSave} className="space-y-4">
            {/* Image Picker / Preview */}
            {previewUrl ? (
              <div className="relative aspect-[4/5] rounded-2xl overflow-hidden bg-slate-100 border-2 border-blush-200">
                <img src={previewUrl} alt="Preview" className="w-full h-full object-cover" />
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

            {/* Handwritten Caption */}
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

            {/* Date */}
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

            {/* Failure detail - the old code swallowed this into a bare alert() */}
            {error && (
              <div
                role="alert"
                className="flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5"
              >
                <AlertTriangle className="w-4 h-4 text-rose-500 shrink-0 mt-0.5" />
                <p className="text-[11px] leading-relaxed text-rose-700">{error}</p>
              </div>
            )}

            {/* Submit */}
            <BouncyButton
              type="submit"
              disabled={saving || !selectedFile}
              className="w-full py-3 text-sm font-bold shadow-md shadow-blush-300/40"
            >
              {saving ? statusText || 'Developing Polaroid...' : 'Develop Polaroid & Save 💕'}
            </BouncyButton>
          </form>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}

export default AddMemoryModal;
