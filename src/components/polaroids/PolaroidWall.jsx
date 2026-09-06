/**
 * src/components/polaroids/PolaroidWall.jsx
 * Aesthetic scrapbook wall displaying interactive polaroids
 */
import React, { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import PolaroidCard from './PolaroidCard';
import AddMemoryModal from './AddMemoryModal';
import BouncyButton from '../common/BouncyButton';
import { Camera, Plus, Sparkles, X } from 'lucide-react';
import { useHaptics } from '../../hooks/useHaptics';

export function PolaroidWall() {
  const { cryptoKey } = useVault();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [activePreview, setActivePreview] = useState(null);
  const { tap } = useHaptics();

  const memories = useLiveQuery(
    () => db.memories.filter((m) => !m.deleted).toArray(),
    []
  );

  const sortedMemories = React.useMemo(() => {
    if (!memories) return [];
    return [...memories].sort((a, b) => new Date(b.date) - new Date(a.date));
  }, [memories]);

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
            {sortedMemories.length} {sortedMemories.length === 1 ? 'polaroid' : 'polaroids'} preserved
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

      {/* Grid of polaroids */}
      {sortedMemories.length === 0 ? (
        <div className="text-center py-16 px-4 bg-white/50 rounded-3xl border-2 border-dashed border-blush-200">
          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-blush-100 text-blush-400 flex items-center justify-center">
            <Camera className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-slate-700">No Polaroids Yet</h3>
          <p className="text-xs text-slate-500 max-w-xs mx-auto mt-1 mb-5">
            Add your first photo together! It will be compressed, encrypted locally, and synced directly to your partner.
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
          {sortedMemories.map((memory) => (
            <PolaroidCard
              key={memory.id}
              memory={memory}
              cryptoKey={cryptoKey}
              onSelect={(item) => setActivePreview(item)}
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
                className="w-full h-full object-cover"
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
