import React, { useCallback, useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { Plus, Check, Trophy, Trash2, AlertTriangle, Pencil } from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import { encryptRecord, decryptRecord, generateUrlSafeNonce } from '../../services/crypto';
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

export function defaultItemId(index) {
  return `bkt-default-${index + 1}`;
}

function newItemId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `bkt-${crypto.randomUUID()}`;
  }
  return `bkt-${generateUrlSafeNonce(12)}`;
}

function nextTimestamp() {
  try {
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

function stripInternalFields(record) {
  const out = {};
  for (const [field, value] of Object.entries(record)) {
    if (field.startsWith('_')) continue;
    out[field] = value;
  }
  return out;
}

let seedInFlight = null;

export async function seedDefaultItems(key) {
  const rows = [];
  for (let index = 0; index < DEFAULT_BUCKET_ITEMS.length; index += 1) {
    const item = DEFAULT_BUCKET_ITEMS[index];
    rows.push(
      await encryptRecord(
        {
          id: defaultItemId(index),
          text: item.text,
          category: item.category,
          completed: false,
          completedAt: null,
          createdAt: index,
          updatedAt: nextTimestamp(),
          deleted: false,
        },
        key,
        { table: 'bucketList' }
      )
    );
  }

  await db.transaction('rw', db.bucketList, async () => {
    if ((await db.bucketList.where('_del').equals(0).count()) > 0) return;

    const collisions = await db.bucketList.bulkGet(rows.map((row) => row.id));
    const fresh = rows.filter((_, index) => !collisions[index]);
    if (fresh.length === 0) return;
    await db.bucketList.bulkAdd(fresh.map((row) => ({ ...row, _del: row.deleted === true ? 1 : 0 })));
  });
}

export function BucketList() {
  const { cryptoKey } = useVault();
  const [newItemText, setNewItemText] = useState('');
  const [category, setCategory] = useState('Romance');
  const [isAdding, setIsAdding] = useState(false);
  const [items, setItems] = useState([]);
  const [skippedCount, setSkippedCount] = useState(0);
  const [error, setError] = useState('');
  const [editingId, setEditingId] = useState(null);
  const [editText, setEditText] = useState('');
  const [editCategory, setEditCategory] = useState('Romance');
  const { tap, celebration } = useHaptics();

  const storedItems = useLiveQuery(() => db.bucketList.toArray(), []);

  const decryptCache = useRef(new Map());

  useEffect(() => {
    if (!cryptoKey) return undefined;
    let cancelled = false;

    async function run() {
      try {
        if ((await db.bucketList.where('_del').equals(0).count()) > 0) return;
        if (!seedInFlight) {
          seedInFlight = seedDefaultItems(cryptoKey).finally(() => {
            seedInFlight = null;
          });
        }
        await seedInFlight;
      } catch (err) {
        console.error('Could not seed the starter bucket-list items:', err);
        if (!cancelled) {
          setError(
            'Could not add the starter bucket list items to this device. Anything you add ' +
              'yourself still saves normally — reopen this screen to try again.'
          );
        }
      }
    }

    run();
    return () => {
      cancelled = true;
    };
  }, [cryptoKey]);

  useEffect(() => {
    decryptCache.current = new Map();
  }, [cryptoKey]);

  useEffect(() => {
    let active = true;

    async function decryptAll() {
      if (!cryptoKey) {
        setItems([]);
        setSkippedCount(0);
        return;
      }
      if (!storedItems) return;

      const cache = decryptCache.current;
      const seen = new Set();
      const next = [];
      let skipped = 0;

      for (const row of storedItems) {
        if (!row || typeof row !== 'object') continue;
        if (row.deleted === true) continue;

        const fingerprint = row.iv || row.textIv || '';
        const cacheKey = `${row.id}::${row.updatedAt}::${fingerprint}`;
        seen.add(cacheKey);

        let record = cache.get(cacheKey);
        if (!record) {
          let decrypted;
          try {
            decrypted = await decryptRecord(row, cryptoKey, { table: 'bucketList' });
          } catch {
            skipped += 1;
            continue;
          }
          if (decrypted._headerTampered) {
            skipped += 1;
            continue;
          }
          record = stripInternalFields(decrypted);
          cache.set(cacheKey, record);
        }

        if (record.deleted === true) continue;
        next.push(record);
      }

      for (const key of Array.from(cache.keys())) {
        if (!seen.has(key)) cache.delete(key);
      }

      if (!active) return;

      next.sort((a, b) => {
        if (a.completed !== b.completed) return a.completed ? 1 : -1;
        const byCreated = (a.createdAt || 0) - (b.createdAt || 0);
        if (byCreated !== 0) return byCreated;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
      });
      setItems(next);
      setSkippedCount(skipped);
    }

    decryptAll();
    return () => {
      active = false;
    };
  }, [storedItems, cryptoKey]);

  const toggleComplete = useCallback(
    async (item) => {
      if (!cryptoKey) return;
      tap();

      const isNowCompleted = !item.completed;
      try {
        const row = await db.putEncrypted(
          'bucketList',
          {
            ...stripInternalFields(item),
            completed: isNowCompleted,
            completedAt: isNowCompleted ? Date.now() : null,
            updatedAt: nextTimestamp(),
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('bucketList', row);
        setError('');

        if (isNowCompleted) {
          celebration();
          fireCelebrationBurst();
        }
      } catch {
        setError('Could not save that change. Our Space may have locked.');
      }
    },
    [cryptoKey, tap, celebration]
  );

  const handleDeleteItem = useCallback(
    async (e, id) => {
      e.stopPropagation();
      if (!window.confirm('Delete this dream from your bucket list?')) return;
      tap();

      try {
        const row = await db.softDelete('bucketList', id, cryptoKey);
        if (row) peerSync.broadcastLiveRecord('bucketList', row);
        setError('');
      } catch {
        setError('Could not delete that item. Our Space may have locked.');
      }
    },
    [cryptoKey, tap]
  );

  const handleStartEdit = useCallback(
    (e, item) => {
      e.stopPropagation();
      tap();
      setEditingId(item.id);
      setEditText(item.text);
      setEditCategory(item.category || 'Romance');
    },
    [tap]
  );

  const handleCancelEdit = useCallback(
    (e) => {
      if (e) e.stopPropagation();
      tap();
      setEditingId(null);
      setEditText('');
    },
    [tap]
  );

  const handleSaveEdit = useCallback(
    async (e, item) => {
      e.preventDefault();
      e.stopPropagation();
      const text = editText.trim();
      if (!text || !cryptoKey) return;
      tap();

      try {
        const row = await db.putEncrypted(
          'bucketList',
          {
            ...stripInternalFields(item),
            text,
            category: editCategory,
            updatedAt: nextTimestamp(),
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('bucketList', row);
        setEditingId(null);
        setError('');
      } catch {
        setError('Could not save that dream. Our Space may have locked.');
      }
    },
    [editText, editCategory, cryptoKey, tap]
  );

  const handleAddItem = useCallback(
    async (e) => {
      e.preventDefault();
      const text = newItemText.trim();
      if (!text || !cryptoKey) return;

      tap();
      try {
        const row = await db.putEncrypted(
          'bucketList',
          {
            id: newItemId(),
            text,
            category,
            completed: false,
            completedAt: null,
            createdAt: Date.now(),
            updatedAt: nextTimestamp(),
            deleted: false,
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('bucketList', row);

        setNewItemText('');
        setIsAdding(false);
        setError('');
        celebration();
        fireHeartConfetti();
      } catch {
        setError('Could not save that dream. Our Space may have locked.');
      }
    },
    [newItemText, category, cryptoKey, tap, celebration]
  );

  const completedCount = items.filter((i) => i.completed).length;
  const progressPercent =
    items.length > 0 ? Math.round((completedCount / items.length) * 100) : 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between px-1">
        <div>
          <h2 className="text-xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
            <span>Our Bucket List</span>
            <Trophy className="w-4 h-4 text-amber-500" />
          </h2>
          <p className="text-xs text-slate-500">
            {completedCount} of {items.length} adventures completed ({progressPercent}%)
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

      {(error || skippedCount > 0) && (
        <div className="flex items-start gap-2 p-3 rounded-2xl bg-amber-50 border border-amber-200 text-amber-800">
          <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <p className="text-xs font-medium leading-snug">
            {error ||
              `${skippedCount} item${skippedCount === 1 ? '' : 's'} could not be opened with your passphrase, so ${
                skippedCount === 1 ? 'it is' : 'they are'
              } hidden for now.`}
          </p>
        </div>
      )}

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

      {isAdding && (
        <form onSubmit={handleAddItem} className="p-4 bg-white rounded-3xl border border-blush-200 shadow-lg space-y-3">
          <div>
            <label className="block text-xs font-semibold text-slate-600 mb-1">
              New Dream or Adventure
            </label>
            <textarea
              value={newItemText}
              onChange={(e) => setNewItemText(e.target.value)}
              placeholder="e.g. Visit the Northern Lights..."
              required
              autoFocus
              rows={2}
              className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400 resize-none"
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

      <div className="space-y-2.5">
        {items.map((item) => (
          <motion.div
            key={item.id}
            layout
            onClick={() => {
              if (editingId !== item.id) {
                toggleComplete(item);
              }
            }}
            className={`p-3.5 rounded-2xl border transition relative overflow-hidden group ${
              editingId === item.id
                ? 'bg-white border-blush-300 shadow-md cursor-default'
                : item.completed
                ? 'bg-matcha-50/70 border-matcha-200/80 cursor-pointer select-none'
                : 'bg-white/80 border-blush-100 hover:border-blush-300 cursor-pointer select-none'
            }`}
          >
            {editingId === item.id ? (
              <form
                onSubmit={(e) => handleSaveEdit(e, item)}
                onClick={(e) => e.stopPropagation()}
                className="space-y-2.5 w-full"
              >
                <div>
                  <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                    Edit Dream or Goal
                  </label>
                  <textarea
                    value={editText}
                    onChange={(e) => setEditText(e.target.value)}
                    rows={2}
                    required
                    autoFocus
                    className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400 resize-none"
                    placeholder="e.g. Visit the Northern Lights..."
                  />
                </div>
                <div className="flex items-center justify-between gap-2">
                  <select
                    value={editCategory}
                    onChange={(e) => setEditCategory(e.target.value)}
                    className="px-2.5 py-1.5 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                  >
                    <option value="Romance">Romance 💕</option>
                    <option value="Travel">Travel ✈️</option>
                    <option value="Adventures">Adventures 🌲</option>
                    <option value="Silly">Silly & Fun 🤪</option>
                  </select>

                  <div className="flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={handleCancelEdit}
                      className="py-1 px-2.5 text-xs text-slate-500 hover:text-slate-700 rounded-xl border border-slate-200 hover:bg-slate-50 transition font-medium"
                    >
                      Cancel
                    </button>
                    <BouncyButton type="submit" className="py-1 px-3 text-xs font-bold">
                      Save
                    </BouncyButton>
                  </div>
                </div>
              </form>
            ) : (
              <div className="flex items-start justify-between gap-2 w-full">
                <div className="flex items-start gap-3 pr-2 flex-1 min-w-0">
                  <div
                    className={`w-6 h-6 rounded-xl flex items-center justify-center transition flex-shrink-0 mt-0.5 ${
                      item.completed
                        ? 'bg-matcha-300 text-emerald-900 shadow-sm'
                        : 'border-2 border-blush-300 bg-white'
                    }`}
                  >
                    {item.completed && <Check className="w-3.5 h-3.5 stroke-[3]" />}
                  </div>

                  <div className="min-w-0 flex-1">
                    <span
                      className={`text-xs font-semibold leading-snug transition-all block break-all whitespace-pre-wrap min-w-0 ${
                        item.completed ? 'line-through text-slate-400' : 'text-slate-700'
                      }`}
                    >
                      {item.text}
                    </span>
                    <span className="block text-[10px] text-slate-400 font-medium mt-1">
                      {item.category}
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-1 flex-shrink-0 mt-0.5">
                  {item.completed && (
                    <motion.div
                      initial={{ scale: 2, rotate: -20, opacity: 0 }}
                      animate={{ scale: 1, rotate: -8, opacity: 0.85 }}
                      className="border-2 border-emerald-600 text-emerald-700 uppercase font-black text-[10px] px-2 py-0.5 rounded-md tracking-wider pointer-events-none mr-1"
                    >
                      COMPLETED
                    </motion.div>
                  )}

                  <button
                    type="button"
                    onClick={(e) => handleStartEdit(e, item)}
                    className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-300 hover:text-blush-500 hover:bg-blush-50 transition"
                    title="Edit dream"
                  >
                    <Pencil className="w-3.5 h-3.5" />
                  </button>

                  <button
                    type="button"
                    onClick={(e) => handleDeleteItem(e, item.id)}
                    className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-300 hover:text-rose-500 hover:bg-rose-50 transition"
                    title="Delete dream"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            )}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

export default BucketList;
