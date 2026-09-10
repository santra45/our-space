/**
 * src/components/polaroids/PolaroidWall.jsx
 * Aesthetic scrapbook wall displaying interactive polaroids.
 *
 * SCHEMA v2: `date` is no longer a plaintext IndexedDB index, so it cannot be
 * sorted on before decryption. The wall therefore opens each record's envelope
 * here - cheap, it is one AES-GCM pass over a small JSON payload - and sorts the
 * results in memory. The photo BYTES are not touched at this level; each card
 * unseals its own image exactly once, keyed on (id, updatedAt).
 *
 * The Dexie query is kept pure - raw rows only, no foreign awaits inside the
 * querier - so useLiveQuery's change subscription registers cleanly, and the
 * decryption happens in a separate effect. Same shape the rest of the app uses.
 *
 * Rows that refuse to decrypt are counted, not swallowed. A silent gap in the
 * wall is indistinguishable from having lost the photos, which is exactly the
 * moment a user deserves to be told something.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { decryptRecord } from '../../services/crypto';
import { parseLocalDate } from '../../utils/dateHelpers';
import { useVault } from '../../context/VaultContext';
import PolaroidCard from './PolaroidCard';
import AddMemoryModal from './AddMemoryModal';
import BouncyButton from '../common/BouncyButton';
import { Camera, Plus, Sparkles, X, AlertTriangle } from 'lucide-react';
import { useHaptics } from '../../hooks/useHaptics';

const EMPTY_WALL = { items: [], unreadable: 0, error: '', ready: false };

/** Sort key for a decrypted record: local midnight of its date. Undated sinks. */
function dateSortKey(record) {
  if (!record.date) return 0;
  const ms = parseLocalDate(record.date).getTime();
  return Number.isFinite(ms) ? ms : 0;
}

export function PolaroidWall() {
  const { cryptoKey } = useVault();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [activePreview, setActivePreview] = useState(null);
  const [wall, setWall] = useState(EMPTY_WALL);
  const { tap } = useHaptics();

  // Raw encrypted rows. Pure Dexie so the live subscription is reliable.
  const storedRows = useLiveQuery(() => db.memories.toArray(), []);

  useEffect(() => {
    if (!storedRows) return;

    let cancelled = false;

    async function decryptWall() {
      if (!cryptoKey) {
        setWall({ items: [], unreadable: 0, error: '', ready: true });
        return;
      }

      const items = [];
      let unreadable = 0;

      for (const row of storedRows) {
        if (row.deleted === true) continue;
        try {
          // The table is REQUIRED here. Without it decryptRecord has no expected
          // table to compare the sealed `_tbl` against, so a row sealed for a
          // different one is never flagged and renders as ordinary content.
          const record = await decryptRecord(row, cryptoKey, { table: 'memories' });
          if (record.deleted === true) continue;
          // A rewritten plaintext header means a peer edited fields that AES-GCM
          // authenticates. Refuse to render forged metadata.
          if (record._headerTampered) {
            unreadable += 1;
            continue;
          }
          items.push(record);
        } catch {
          unreadable += 1;
        }
      }

      if (cancelled) return;

      items.sort(
        (a, b) => dateSortKey(b) - dateSortKey(a) || (b.updatedAt || 0) - (a.updatedAt || 0)
      );
      setWall({ items, unreadable, error: '', ready: true });
    }

    decryptWall().catch((err) => {
      if (cancelled) return;
      console.error('Could not decrypt the polaroid wall:', err);
      setWall({
        items: [],
        unreadable: 0,
        error: 'We could not open your scrapbook just now. Please try again.',
        ready: true,
      });
    });

    return () => {
      cancelled = true;
    };
  }, [storedRows, cryptoKey]);

  const { items: memories, unreadable, error: wallError } = wall;
  const isLoading = storedRows === undefined || !wall.ready;

  // A record can vanish underneath an open lightbox (partner deleted it), which
  // would leave it pointing at an ObjectURL its card has already revoked.
  useEffect(() => {
    if (!activePreview) return;
    if (!memories.some((m) => m.id === activePreview.id)) setActivePreview(null);
  }, [memories, activePreview]);

  const handleSelect = useCallback((item) => setActivePreview(item), []);

  return (
    <div className="space-y-4">
      {/* Header bar */}
      <div className="flex items-center justify-between px-1">
        <div>
          <h2 className="text-xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
            <span>Our Scrapbook</span>
            <Sparkles className="w-4 h-4 text-amber-500" />
          </h2>
          <p className="text-xs text-slate-500">
            {isLoading
              ? 'Opening your scrapbook...'
              : `${memories.length} ${memories.length === 1 ? 'polaroid' : 'polaroids'} preserved`}
          </p>
        </div>

        <BouncyButton
          onClick={() => {
            tap();
            setIsModalOpen(true);
          }}
          className="py-2 px-3.5 text-xs gap-1.5 rounded-full"
        >
          <Plus className="w-4 h-4" />
          <span>Snap Memory</span>
        </BouncyButton>
      </div>

      {/* Read failures are reported, never silently dropped from the grid */}
      {(wallError || unreadable > 0) && (
        <div
          role="alert"
          className="flex items-start gap-2 rounded-2xl border border-amber-200 bg-amber-50 px-3.5 py-3"
        >
          <AlertTriangle className="w-4 h-4 text-amber-500 shrink-0 mt-0.5" />
          <p className="text-[11px] leading-relaxed text-amber-800">
            {wallError ||
              `${unreadable} ${unreadable === 1 ? 'polaroid' : 'polaroids'} could not be opened with your passphrase, so ${unreadable === 1 ? 'it is' : 'they are'} hidden for now.`}
          </p>
        </div>
      )}

      {/* Grid of polaroids */}
      {isLoading ? (
        <div className="grid grid-cols-2 gap-4 pt-2">
          {[0, 1].map((i) => (
            <div
              key={i}
              className="aspect-[3/4] rounded-2xl bg-white/60 border border-slate-100 animate-pulse"
            />
          ))}
        </div>
      ) : memories.length === 0 ? (
        <div className="text-center py-16 px-4 bg-white/50 rounded-3xl border-2 border-dashed border-blush-200">
          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-blush-100 text-blush-400 flex items-center justify-center">
            <Camera className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-slate-700">No Polaroids Yet</h3>
          <p className="text-xs text-slate-500 max-w-xs mx-auto mt-1 mb-5">
            Add your first photo together! It will be saved safely here and shared with your partner.
          </p>
          <BouncyButton
            onClick={() => setIsModalOpen(true)}
            className="text-xs py-2.5 px-5 rounded-full"
          >
            Create First Polaroid 💕
          </BouncyButton>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-4 pt-2">
          {memories.map((memory) => (
            <PolaroidCard
              key={memory.id}
              memory={memory}
              cryptoKey={cryptoKey}
              onSelect={handleSelect}
            />
          ))}
        </div>
      )}

      {/* Add Memory Modal */}
      <AddMemoryModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        cryptoKey={cryptoKey}
      />

      {/* Lightbox full-size view */}
      {activePreview && (
        <div
          onClick={() => setActivePreview(null)}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="max-w-sm w-full bg-white p-4 pb-6 rounded-3xl shadow-2xl relative"
          >
            <button
              onClick={() => setActivePreview(null)}
              className="absolute -top-3 -right-3 w-8 h-8 bg-white text-slate-700 rounded-full flex items-center justify-center shadow-lg font-bold"
            >
              <X className="w-4 h-4" />
            </button>
            <div className="aspect-[4/5] rounded-2xl overflow-hidden bg-black/5 mb-3">
              <img
                src={activePreview.imageUrl}
                alt="Full polaroid"
                // Opened deliberately to look at the photo, so show all of it.
                className="w-full h-full object-contain"
              />
            </div>
            <p className="font-handwriting text-2xl text-center text-slate-800">
              {activePreview.caption}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

export default PolaroidWall;
