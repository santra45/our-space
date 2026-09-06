/**
 * src/components/bucketlist/BucketList.jsx
 * Shared couple's bucket list with progress bar, completion stamps, and confetti
 */
import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { CheckSquare, Square, Plus, Check, Sparkles, Trophy, X, Trash2 } from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import { encryptText, decryptText } from '../../services/crypto';
import peerSync from '../../services/peerSync';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti, fireCelebrationBurst } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

const DEFAULT_BUCKET_ITEMS = [
  { text: 'Watch the sunrise on a beach wrapped in a warm blanket', category: 'Romance' },
  { text: 'Take a midnight road trip with no destination', category: 'Adventures' },
  { text: 'Bake an overly ambitious tiered cake together', category: 'Silly' },
  { text: 'Fly to Japan during cherry blossom season', category: 'Travel' },
  { text: 'Camp under the stars and cook s’mores over a fire', category: 'Adventures' },
  { text: 'Get matching silly holiday pajamas', category: 'Silly' },
];

export function BucketList() {
  const { cryptoKey } = useVault();
  const [newItemText, setNewItemText] = useState('');
  const [category, setCategory] = useState('Romance');
  const [isAdding, setIsAdding] = useState(false);
  const { tap, celebration } = useHaptics();

  const storedItems = useLiveQuery(
    () => db.bucketList.filter((b) => !b.deleted).toArray(),
    []
  );

  const [decryptedItems, setDecryptedItems] = useState([]);

  // Populate default bucket items if completely empty on first visit
  useEffect(() => {
    async function seedInitial() {
      if (!cryptoKey) return;
      const count = await db.bucketList.count();
      if (count === 0) {
        for (let i = 0; i < DEFAULT_BUCKET_ITEMS.length; i++) {
          const item = DEFAULT_BUCKET_ITEMS[i];
          const { ciphertext, iv } = await encryptText(item.text, cryptoKey);
          await db.bucketList.put({
            id: 'bkt-' + (Date.now() + i),
            textCipher: ciphertext,
            textIv: iv,
            category: item.category,
            completed: false,
            completedAt: null,
            updatedAt: Date.now(),
            deleted: false,
          });
        }
      }
    }
    seedInitial();
  }, [cryptoKey]);

  // Decrypt items
  useEffect(() => {
    async function decryptAll() {
      if (!storedItems || !cryptoKey) return;
      const list = [];
      for (const item of storedItems) {
        try {
          const text = await decryptText(item.textCipher, item.textIv, cryptoKey);
          list.push({ ...item, text });
        } catch {
          list.push({ ...item, text: 'Encrypted Goal' });
        }
      }
      setDecryptedItems(list.sort((a, b) => (a.completed === b.completed ? 0 : a.completed ? 1 : -1)));
    }
    decryptAll();
  }, [storedItems, cryptoKey]);

  const toggleComplete = async (item) => {
    tap();
    const isNowCompleted = !item.completed;
    const updated = {
      ...item,
      completed: isNowCompleted,
      completedAt: isNowCompleted ? Date.now() : null,
      updatedAt: Date.now(),
    };
    // remove decrypted plain field before storing
    delete updated.text;

    await db.bucketList.put(updated);
    peerSync.broadcastLiveRecord('bucketList', updated);

    if (isNowCompleted) {
      celebration();
      fireCelebrationBurst();
    }
  };

  const handleDeleteItem = async (e, id) => {
    e.stopPropagation();
    if (!window.confirm('Delete this dream from your bucket list?')) return;
    tap();
    const existing = await db.bucketList.get(id);
    if (existing) {
      const updated = { ...existing, deleted: true, updatedAt: Date.now() };
      await db.bucketList.put(updated);
      peerSync.broadcastLiveRecord('bucketList', updated);
    }
  };

  const handleAddItem = async (e) => {
    e.preventDefault();
    if (!newItemText.trim() || !cryptoKey) return;

    tap();
    const { ciphertext, iv } = await encryptText(newItemText.trim(), cryptoKey);
    const newRecord = {
      id: 'bkt-' + Date.now(),
      textCipher: ciphertext,
      textIv: iv,
      category,
      completed: false,
      completedAt: null,
      updatedAt: Date.now(),
      deleted: false,
    };

    await db.bucketList.put(newRecord);
    peerSync.broadcastLiveRecord('bucketList', newRecord);

    setNewItemText('');
    setIsAdding(false);
    celebration();
    fireHeartConfetti();
  };

  const completedCount = decryptedItems.filter((i) => i.completed).length;
  const progressPercent = decryptedItems.length > 0
    ? Math.round((completedCount / decryptedItems.length) * 100)
    : 0;

  return (
    <div className="space-y-4">
      {/* Header bar */}
      <div className="flex items-center justify-between px-1">
        <div>
          <h2 className="text-xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
            <span>Our Bucket List</span>
            <Trophy className="w-4 h-4 text-amber-500" />
          </h2>
          <p className="text-xs text-slate-500">
            {completedCount} of {decryptedItems.length} adventures completed ({progressPercent}%)
          </p>
        </div>

        <BouncyButton
          onClick={() => {
            tap();
            setIsAdding(!isAdding);
          }}
          className="py-2 px-3.5 text-xs gap-1.5 rounded-full"
        >
          <Plus className="w-4 h-4" />
          <span>Add Dream</span>
        </BouncyButton>
      </div>

      {/* Progress Bar Card */}
      <GlassCard className="p-4 bg-gradient-to-r from-blush-50 to-cream-50">
        <div className="flex items-center justify-between text-xs font-bold text-slate-700 mb-2">
          <span>Adventures Conquered Together</span>
          <span className="text-blush-600 font-extrabold">{progressPercent}%</span>
        </div>
        <div className="w-full h-3 bg-white rounded-full overflow-hidden border border-blush-200/80 p-0.5 shadow-inner">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${progressPercent}%` }}
            transition={{ type: 'spring', stiffness: 100, damping: 15 }}
            className="h-full bg-gradient-to-r from-blush-400 to-blush-500 rounded-full"
          />
        </div>
      </GlassCard>

      {/* Add Item Form */}
      {isAdding && (
        <form onSubmit={handleAddItem} className="p-4 bg-white rounded-3xl border border-blush-200 shadow-lg space-y-3">
          <div>
            <label className="block text-xs font-semibold text-slate-600 mb-1">
              New Dream or Adventure
            </label>
            <input
              type="text"
              value={newItemText}
              onChange={(e) => setNewItemText(e.target.value)}
              placeholder="e.g. Visit the Northern Lights..."
              required
              autoFocus
              className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
            />
          </div>

          <div className="flex items-center gap-2">
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
            >
              <option value="Romance">Romance 💕</option>
              <option value="Travel">Travel ✈️</option>
              <option value="Adventures">Adventures 🌲</option>
              <option value="Silly">Silly & Fun 🤪</option>
            </select>

            <BouncyButton type="submit" className="py-1.5 px-4 text-xs font-bold">
              Add Goal
            </BouncyButton>
          </div>
        </form>
      )}

      {/* Checklist items */}
      <div className="space-y-2.5">
        {decryptedItems.map((item) => (
          <motion.div
            key={item.id}
            layout
            onClick={() => toggleComplete(item)}
            className={`p-3.5 rounded-2xl border transition flex items-center justify-between cursor-pointer select-none relative overflow-hidden group ${
              item.completed
                ? 'bg-matcha-50/70 border-matcha-200/80'
                : 'bg-white/80 border-blush-100 hover:border-blush-300'
            }`}
          >
            <div className="flex items-center gap-3 pr-2 flex-1 min-w-0">
              <div
                className={`w-6 h-6 rounded-xl flex items-center justify-center transition flex-shrink-0 ${
                  item.completed
                    ? 'bg-matcha-300 text-emerald-900 shadow-sm'
                    : 'border-2 border-blush-300 bg-white'
                }`}
              >
                {item.completed && <Check className="w-3.5 h-3.5 stroke-[3]" />}
              </div>

              <div className="min-w-0">
                <span
                  className={`text-xs font-semibold leading-snug transition-all block truncate ${
                    item.completed ? 'line-through text-slate-400' : 'text-slate-700'
                  }`}
                >
                  {item.text}
                </span>
                <span className="block text-[10px] text-slate-400 font-medium mt-0.5">
                  {item.category}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-2 flex-shrink-0">
              {/* Completed Stamp Effect */}
              {item.completed && (
                <motion.div
                  initial={{ scale: 2, rotate: -20, opacity: 0 }}
                  animate={{ scale: 1, rotate: -8, opacity: 0.85 }}
                  className="border-2 border-emerald-600 text-emerald-700 uppercase font-black text-[10px] px-2 py-0.5 rounded-md tracking-wider pointer-events-none"
                >
                  COMPLETED
                </motion.div>
              )}

              {/* Delete Button */}
              <button
                type="button"
                onClick={(e) => handleDeleteItem(e, item.id)}
                className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-300 hover:text-rose-500 hover:bg-rose-50 transition"
                title="Delete dream"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

export default BucketList;
