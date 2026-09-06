/**
 * src/components/polaroids/AddMemoryModal.jsx
 * Upload modal with Android camera capture, client-side WebP compression, and AES-GCM encryption
 */
import React, { useState, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, Camera, Image as ImageIcon, Sparkles } from 'lucide-react';
import { compressImage } from '../../utils/imageCompression';
import { encryptText, encryptBlob } from '../../services/crypto';
import db from '../../db';
import peerSync from '../../services/peerSync';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

export function AddMemoryModal({ isOpen, onClose, cryptoKey }) {
  const [selectedFile, setSelectedFile] = useState(null);
  const [previewUrl, setPreviewUrl] = useState(null);
  const [caption, setCaption] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
  const [saving, setSaving] = useState(false);
  const [statusText, setStatusText] = useState('');

  const fileInputRef = useRef(null);
  const cameraInputRef = useRef(null);
  const { tap, celebration } = useHaptics();

  const handleFileChange = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    tap();
    setSelectedFile(file);
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
  };

  const handleSave = async (e) => {
    e.preventDefault();
    if (!selectedFile || !cryptoKey) return;

    try {
      setSaving(true);
      tap();

      // Step 1: Compress on mobile canvas to retina WebP
      setStatusText('Optimizing photo for mobile...');
      const { fullBlob } = await compressImage(selectedFile, {
        maxWidth: 1440,
        maxHeight: 1440,
        quality: 0.85,
      });

      // Step 2: Zero-Knowledge AES-GCM 256 Encryption
      setStatusText('Encrypting with AES-GCM 256...');
      const encryptedImageBytes = await encryptBlob(fullBlob, cryptoKey);
      const { ciphertext: captionCipher, iv: captionIv } = await encryptText(
        caption.trim() || 'Precious moment 💕',
        cryptoKey
      );

      // Step 3: Store in local IndexedDB
      setStatusText('Saving to your vault...');
      const newMemory = {
        id: 'mem-' + Date.now(),
        date,
        captionCipher,
        captionIv,
        imageBlob: encryptedImageBytes,
        updatedAt: Date.now(),
        deleted: false,
      };

      await db.memories.put(newMemory);

      // Step 4: Broadcast live to partner if connected
      peerSync.broadcastLiveRecord('memories', newMemory);

      celebration();
      fireHeartConfetti();
      handleClose();
    } catch (err) {
      console.error('Failed to save memory:', err);
      alert('Error saving memory: ' + err.message);
    } finally {
      setSaving(false);
      setStatusText('');
    }
  };

  const handleClose = () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setSelectedFile(null);
    setPreviewUrl(null);
    setCaption('');
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
            className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
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
                  onClick={() => {
                    setSelectedFile(null);
                    setPreviewUrl(null);
                  }}
                  className="absolute bottom-3 right-3 px-3 py-1.5 bg-black/60 text-white rounded-xl text-xs font-semibold backdrop-blur-sm hover:bg-black/80"
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
