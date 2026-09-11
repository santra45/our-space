/**
 * src/components/polaroids/PolaroidCard.jsx
 * Realistic Polaroid photo card with washi tape, handwritten caption, and 3D interactive tilt.
 *
 * SCHEMA v2: `memory` arrives ALREADY DECRYPTED from PolaroidWall - caption, date
 * and mime come out of the record envelope up there, where they are needed for
 * sorting anyway. The only thing left for this card to unseal is the image blob,
 * which is the expensive part and is deliberately not done twice.
 *
 * WHY THIS COMPONENT IS MEMOIZED
 * The wall reads memories through useLiveQuery, which hands back brand-new object
 * identities on EVERY write to the memories table. With `[memory]` as an effect
 * dependency, adding one photo re-decrypted every other photo on the wall. The
 * memo comparator and the effect both key on (id, updatedAt) instead: updatedAt
 * is bumped by every write path, so an unchanged pair provably means unchanged
 * bytes and there is nothing to redo.
 */
import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { decryptBlob } from '../../services/crypto';
import { formatDatePretty } from '../../utils/dateHelpers';
import { useHaptics } from '../../hooks/useHaptics';
import { Trash2, ImageOff } from 'lucide-react';
import db from '../../db';
import peerSync from '../../services/peerSync';

/** Rows written before the mime was stored were always canvas-encoded WebP. */
const LEGACY_IMAGE_MIME = 'image/webp';

function PolaroidCardBase({ memory, cryptoKey, onSelect }) {
  const [imageUrl, setImageUrl] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  const { tap } = useHaptics();

  const caption = memory.caption || '';

  // Subtle deterministic rotation for scrapbook aesthetic (-2deg to +2deg)
  const rotation = useMemo(() => {
    const hash = memory.id.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
    return (hash % 5) - 2;
  }, [memory.id]);

  useEffect(() => {
    let cancelled = false;
    // Assigned inside the async body. The old cleanup read this binding when it
    // was still null - the URL was minted a moment later and orphaned forever.
    // It is now revoked at the point of creation when the effect has already
    // been torn down, so there is no window in which it can escape.
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
        // A photo that will not decrypt is worth saying out loud - it means a
        // wrong key, a corrupt row, or bytes from a peer that were tampered with.
        if (!cancelled) {
          // Drop the previous render's URL too: the cleanup already revoked it,
          // so leaving it in state would paint a dead <img> next to the error.
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
    // memory.imageBlob is intentionally absent: a stable (id, updatedAt) pair
    // guarantees identical bytes, so re-running on a fresh useLiveQuery object
    // identity would only re-decrypt the same photo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [memory.id, memory.updatedAt, memory.mime, cryptoKey]);

  const handleDelete = async (e) => {
    e.stopPropagation();
    if (deleting) return;
    if (!window.confirm('Delete this precious memory? This cannot be undone.')) return;

    tap();
    setDeleting(true);
    setError('');

    try {
      // softDelete re-seals a tombstone that keeps only the id and a bumped
      // updatedAt. A blind put() of this decrypted object would write `date` and
      // `caption` back to disk in PLAINTEXT.
      const tombstone = await db.softDelete('memories', memory.id, cryptoKey);
      if (!tombstone) {
        // Nothing was written, so no live query will fire and this card would
        // otherwise sit here with a permanently disabled button.
        setDeleting(false);
        setError('That memory was already removed.');
        return;
      }
      peerSync.broadcastLiveRecord('memories', tombstone);
      // On success the row leaves the wall's query and this card unmounts.
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
          <div className="w-full h-full flex flex-col items-center justify-center gap-1.5 px-3 text-center">
            <ImageOff className="w-5 h-5 text-slate-300" />
            <span className="text-[10px] leading-tight text-slate-400">
              {error || 'No image'}
            </span>
          </div>
        )}

        {/*
          Always visible, never hover-gated. `group-hover` never fires on a
          phone, and opacity-0 does not stop clicks - so this was an invisible
          delete sitting on the corner of every photo, firing on a tap that was
          meant to open it. active: is here because hover: is dead on touch.
        */}
        <button
          onClick={handleDelete}
          disabled={deleting}
          className="absolute top-2 right-2 w-7 h-7 bg-black/40 backdrop-blur-sm text-white rounded-full flex items-center justify-center transition-colors hover:bg-rose-500 active:bg-rose-500 disabled:opacity-40"
          title="Delete memory"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>

      {/* Inline failure detail for a card that DID render an image but failed to delete */}
      {error && imageUrl && (
        <p role="alert" className="mt-2 text-[10px] leading-tight text-rose-600 text-center">
          {error}
        </p>
      )}

      {/* Handwritten caption and date stamp */}
      <div className="mt-3 px-1 text-center">
        {/* Two lines, not one. `truncate` cut every caption on the wall to about
            eleven characters - "the night you stayed up till 4am with me" came
            out as "the night y..." - and the caption is the point of a polaroid.
            The lightbox still shows it whole. */}
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

/**
 * Re-render only when the record actually changed. `updatedAt` moves on every
 * write, so comparing it against the record id is a complete change test and
 * costs one number comparison instead of a full photo decrypt.
 */
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
