/**
 * src/components/polaroids/PolaroidCard.jsx
 * Realistic Polaroid photo card with washi tape, handwritten caption, and 3D interactive tilt
 */
import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { decryptBlob, decryptText } from '../../services/crypto';
import { formatDatePretty } from '../../utils/dateHelpers';
import { useHaptics } from '../../hooks/useHaptics';
import { Trash2 } from 'lucide-react';
import db from '../../db';
import peerSync from '../../services/peerSync';

export function PolaroidCard({ memory, cryptoKey, onSelect }) {
  const [imageUrl, setImageUrl] = useState(null);
  const [caption, setCaption] = useState('');
  const [loading, setLoading] = useState(true);
  const { tap } = useHaptics();

  // Subtle random rotation for scrapbook aesthetic (-2deg to +2deg)
  const rotation = React.useMemo(() => {
    const hash = memory.id.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
    return (hash % 5) - 2;
  }, [memory.id]);

  useEffect(() => {
    let active = true;
    let url = null;

    async function loadContent() {
      if (!cryptoKey || !memory) return;
      try {
        setLoading(true);
        // Decrypt caption
        if (memory.captionCipher && memory.captionIv) {
          const text = await decryptText(memory.captionCipher, memory.captionIv, cryptoKey);
          if (active) setCaption(text);
        }

        // Decrypt image blob
        if (memory.imageBlob) {
          const blob = await decryptBlob(memory.imageBlob, cryptoKey, 'image/webp');
          url = URL.createObjectURL(blob);
          if (active) setImageUrl(url);
        }
      } catch {
        // Suppress decryption failure error details
      } finally {
        if (active) setLoading(false);
      }
    }

    loadContent();

    return () => {
      active = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [memory, cryptoKey]);

  const handleDelete = async (e) => {
    e.stopPropagation();
    if (!window.confirm('Delete this precious memory?')) return;
    tap();
    const updated = { ...memory, deleted: true, updatedAt: Date.now() };
    await db.memories.put(updated);
    peerSync.broadcastLiveRecord('memories', updated);
  };

  return (
    <motion.div
      style={{ rotate: `${rotation}deg` }}
      whileHover={{ scale: 1.03, rotate: 0, zIndex: 10 }}
      whileTap={{ scale: 0.97 }}
      onClick={() => {
        tap();
        if (onSelect && imageUrl) onSelect({ ...memory, imageUrl, caption });
      }}
      className="relative bg-white p-3 pb-5 rounded-2xl shadow-polaroid border border-slate-100 cursor-pointer transition-shadow hover:shadow-xl group"
    >
      {/* Washi tape header */}
      <div className="washi-tape" />

      {/* Photo viewport */}
      <div className="w-full aspect-[4/5] bg-blush-50 rounded-xl overflow-hidden relative border border-slate-100/80">
        {loading ? (
          <div className="w-full h-full flex items-center justify-center text-xs text-blush-400 font-medium animate-pulse">
            Developing... 💕
          </div>
        ) : imageUrl ? (
          <img
            src={imageUrl}
            alt={caption || 'Polaroid Memory'}
            className="w-full h-full object-cover select-none"
            loading="lazy"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-xs text-slate-300">
            No image
          </div>
        )}

        {/* Delete button (visible on hover / tap) */}
        <button
          onClick={handleDelete}
          className="absolute top-2 right-2 w-7 h-7 bg-black/40 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-rose-500"
          title="Delete memory"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>

      {/* Handwritten caption and date stamp */}
      <div className="mt-3 px-1 text-center">
        <p className="font-handwriting text-xl text-slate-800 leading-tight truncate">
          {caption || 'A special moment'}
        </p>
        <p className="text-[10px] text-slate-400 font-mono mt-0.5">
          {formatDatePretty(memory.date)}
        </p>
      </div>
    </motion.div>
  );
}

export default PolaroidCard;
