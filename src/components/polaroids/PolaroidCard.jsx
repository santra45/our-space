import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { decryptBlob } from '../../services/crypto';
import { formatDatePretty } from '../../utils/dateHelpers';
import { useHaptics } from '../../hooks/useHaptics';
import { Trash2, ImageOff } from 'lucide-react';
import db from '../../db';
import peerSync from '../../services/peerSync';

const LEGACY_IMAGE_MIME = 'image/webp';

function PolaroidCardBase({ memory, cryptoKey, onSelect }) {
  const [imageUrl, setImageUrl] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  const { tap } = useHaptics();

  const caption = memory.caption || '';

  const rotation = useMemo(() => {
    const hash = memory.id.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
    return (hash % 5) - 2;
  }, [memory.id]);

  useEffect(() => {
    let cancelled = false;
    let objectUrl = null;

    async function loadImage() {
      if (!cryptoKey) {
        setLoading(false);
        setError('Our Space is locked.');
        return;
      }
      if (!memory.imageBlob) {
        setLoading(false);
        return;
      }

      setLoading(true);
      setError('');

      try {
        const blob = await decryptBlob(memory.imageBlob, cryptoKey, memory.mime || LEGACY_IMAGE_MIME);
        objectUrl = URL.createObjectURL(blob);

        if (cancelled) {
          URL.revokeObjectURL(objectUrl);
          objectUrl = null;
          return;
        }
        setImageUrl(objectUrl);
      } catch {
        if (!cancelled) {
          setImageUrl(null);
          setError('This photo could not be unlocked.');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    loadImage();

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [memory.id, memory.updatedAt, memory.mime, cryptoKey]);

  const handleDelete = async (e) => {
    e.stopPropagation();
    if (deleting) return;
    if (!window.confirm('Delete this precious memory? This cannot be undone.')) return;

    tap();
    setDeleting(true);
    setError('');

    try {
      const tombstone = await db.softDelete('memories', memory.id, cryptoKey);
      if (!tombstone) {
        setDeleting(false);
        setError('That memory was already removed.');
        return;
      }
      peerSync.broadcastLiveRecord('memories', tombstone);
    } catch (err) {
      setDeleting(false);
      setError(err?.message ? `Delete failed: ${err.message}` : 'Delete failed.');
    }
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
      <div className="washi-tape" />

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
          <div className="w-full h-full flex flex-col items-center justify-center gap-1.5 px-3 text-center">
            <ImageOff className="w-5 h-5 text-slate-300" />
            <span className="text-[10px] leading-tight text-slate-400">
              {error || 'No image'}
            </span>
          </div>
        )}

        <button
          onClick={handleDelete}
          disabled={deleting}
          className="absolute top-2 right-2 w-7 h-7 bg-black/40 backdrop-blur-sm text-white rounded-full flex items-center justify-center transition-colors hover:bg-rose-500 active:bg-rose-500 disabled:opacity-40"
          title="Delete memory"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>

      {error && imageUrl && (
        <p role="alert" className="mt-2 text-[10px] leading-tight text-rose-600 text-center">
          {error}
        </p>
      )}

      <div className="mt-3 px-1 text-center">
        <p className="font-handwriting text-xl text-slate-800 leading-tight line-clamp-2 break-words">
          {caption || 'A special moment'}
        </p>
        <p className="text-[10px] text-slate-400 font-mono mt-0.5">
          {formatDatePretty(memory.date)}
        </p>
      </div>
    </motion.div>
  );
}

export const PolaroidCard = React.memo(
  PolaroidCardBase,
  (prev, next) =>
    prev.cryptoKey === next.cryptoKey &&
    prev.onSelect === next.onSelect &&
    prev.memory.id === next.memory.id &&
    prev.memory.updatedAt === next.memory.updatedAt
);

PolaroidCard.displayName = 'PolaroidCard';

export default PolaroidCard;
