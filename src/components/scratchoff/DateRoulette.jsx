/**
 * src/components/scratchoff/DateRoulette.jsx
 * Interactive digital scratch-off card and roulette for romantic date ideas.
 *
 * P7 decision: the `dateIdeas` table is KEPT and is now actually used, rather than
 * being dropped from the schema and the sync allowlist.
 *
 * What is stored is deliberately not the idea catalogue. The catalogue below is
 * app content - identical in every install, shipped in the bundle - so writing ten
 * copies of it into every vault and replicating them over the wire would buy
 * nothing and would recreate the duplicate-defaults problem that S4 was about.
 * What IS stored is a single record: which idea is currently on the card, which
 * category filter produced it, and whether it has been scratched open. That one
 * row survives a reload (the old component held all of it in component state and
 * lost it on refresh) and replicates, so a roll on one phone shows up on the
 * other - which is the point of a shared date roulette.
 *
 * The row uses a fixed id, so both devices converge on one record instead of
 * accumulating a history of rolls.
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { Sparkles, RefreshCw, Home, Trees, Utensils, PiggyBank, Heart } from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import { decryptRecord } from '../../services/crypto';
import peerSync from '../../services/peerSync';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

/** The one and only roulette row. Fixed so both devices write the same record. */
const ROULETTE_STATE_ID = 'roulette-current';

/** Strokes between two full-canvas progress scans. */
const STROKES_PER_PROGRESS_CHECK = 24;

/** Strokes between two haptic ticks. */
const STROKES_PER_TICK = 4;

/** Fraction of the coating that has to be gone before the card pops open. */
const REVEAL_THRESHOLD = 0.4;

const CATEGORIES = [
  { id: 'all', label: 'All', icon: Sparkles },
  { id: 'athome', label: 'At-Home', icon: Home },
  { id: 'outdoor', label: 'Outdoor', icon: Trees },
  { id: 'food', label: 'Foodie', icon: Utensils },
  { id: 'budget', label: 'Budget', icon: PiggyBank },
];

const DEFAULT_IDEAS = [
  { id: 'd1', title: 'Living Room Pillow Fort Movie Night', category: 'athome', desc: 'Build an epic cozy blanket fort, string fairy lights, pop fresh buttered popcorn, and watch childhood cartoons.' },
  { id: 'd2', title: 'Stargazing with Warm Hot Chocolate', category: 'outdoor', desc: 'Drive or walk to a quiet spot away from city lights with a thick quilt, thermos of hot cocoa, and a cozy playlist.' },
  { id: 'd3', title: 'Blind Taste Test Challenge', category: 'food', desc: 'Buy 5 different snacks or treats and take turns wearing a blindfold guessing the mystery flavors.' },
  { id: 'd4', title: '$10 Dollar Tree / Thrift Challenge', category: 'budget', desc: 'Give each other a strict $10 budget to buy the funniest, sweetest, or most thoughtful gift within 20 minutes.' },
  { id: 'd5', title: 'Homemade Pasta Cooking Battle', category: 'food', desc: 'Roll up your sleeves, put on an Italian playlist, and make fresh fettuccine or gnocchi completely from scratch.' },
  { id: 'd6', title: 'Sunrise Breakfast Picnic', category: 'outdoor', desc: 'Wake up before dawn, grab warm pastries and coffee, and watch the sun come up together wrapped in one big jacket.' },
  { id: 'd7', title: 'At-Home Spa & Foot Massage Night', category: 'athome', desc: 'Light scented candles, put on relaxing lofi tunes, wear sheet masks, and give each other long shoulder and foot rubs.' },
  { id: 'd8', title: 'Sunset Bicycle or Scooting Adventure', category: 'outdoor', desc: 'Rent bikes or electric scooters and explore an unfamiliar neighborhood or waterfront park as the sun sets.' },
  { id: 'd9', title: 'Fondue & Storytelling by Candlelight', category: 'food', desc: 'Melt warm chocolate with strawberries, pretzels, and marshmallows while sharing your favorite memories together.' },
  { id: 'd10', title: 'Photo Scavenger Hunt in the City', category: 'budget', desc: 'Create a list of 10 silly photo prompts (e.g. funny hat, stray cat, heart-shaped object) and snap polaroids!' },
];

const IDEAS_BY_ID = new Map(DEFAULT_IDEAS.map((idea) => [idea.id, idea]));
const CATEGORY_IDS = new Set(CATEGORIES.map((c) => c.id));

/** Monotonic write stamp, so a skewed device clock cannot permanently win or lose. */
function nextTimestamp() {
  try {
    return peerSync.getSyncSafeTimestamp();
  } catch {
    return Date.now();
  }
}

/** The ideas matching a category filter. */
function ideasIn(categoryId) {
  if (categoryId === 'all') return DEFAULT_IDEAS;
  return DEFAULT_IDEAS.filter((idea) => idea.category === categoryId);
}

export function DateRoulette() {
  const { cryptoKey } = useVault();
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [currentIdea, setCurrentIdea] = useState(DEFAULT_IDEAS[0]);
  const [isRevealed, setIsRevealed] = useState(false);
  const [cardKey, setCardKey] = useState(0);

  const canvasRef = useRef(null);
  const { tap, tick, celebration } = useHaptics();

  /**
   * `isRevealed` also lives in a ref because the canvas listeners are registered
   * once per card and would otherwise close over the value from the render that
   * registered them - which is how the old build ended up running a full
   * getImageData on every single pointer move for the life of the card.
   */
  const revealedRef = useRef(false);

  /**
   * The updatedAt of the roulette row this component has already applied.
   * It is bumped by our own writes too, so the useLiveQuery echo of a local roll
   * is ignored instead of resetting the card a second time.
   */
  const appliedAtRef = useRef(0);

  const storedState = useLiveQuery(() => db.dateIdeas.get(ROULETTE_STATE_ID), []);

  /* --------------------------------------------------------------------- *
   * Persistence
   * --------------------------------------------------------------------- */

  const persist = useCallback(
    async (next) => {
      if (!cryptoKey) return;

      // Claimed BEFORE the write, not after: the live query can fire between the
      // put resolving and this line, and a late claim would let our own echo
      // through and reset a card the user has already started scratching.
      const updatedAt = nextTimestamp();
      appliedAtRef.current = updatedAt;

      try {
        const row = await db.putEncrypted(
          'dateIdeas',
          {
            id: ROULETTE_STATE_ID,
            ideaId: next.ideaId,
            category: next.category,
            revealed: next.revealed === true,
            updatedAt,
            deleted: false,
          },
          cryptoKey
        );
        peerSync.broadcastLiveRecord('dateIdeas', row);
      } catch {
        // Persisting a roll is a nicety, not the feature. The card is already
        // showing the new idea locally; the next roll will try again.
      }
    },
    [cryptoKey]
  );

  /* --------------------------------------------------------------------- *
   * Adopt stored / partner state
   * --------------------------------------------------------------------- */

  useEffect(() => {
    let active = true;

    async function adopt() {
      if (!cryptoKey || !storedState) return;
      if (storedState.deleted === true) return;
      if (!Number.isFinite(storedState.updatedAt)) return;
      // Our own echo, or a row we have already applied.
      if (storedState.updatedAt <= appliedAtRef.current) return;

      let record;
      try {
        // The table is REQUIRED here. Without it decryptRecord has no expected
        // table to compare the sealed `_tbl` against, so a row sealed for a
        // different one is never flagged and renders as ordinary content.
        record = await decryptRecord(storedState, cryptoKey, { table: 'dateIdeas' });
      } catch {
        return;
      }
      if (!active) return;
      if (record._headerTampered || record.deleted === true) return;

      // Marked processed either way, so a row we cannot use is not re-decrypted
      // on every subsequent write to the table.
      appliedAtRef.current = record.updatedAt;

      const idea = IDEAS_BY_ID.get(record.ideaId);
      // An unknown ideaId means the peer is running a build with a different
      // catalogue. Keep whatever is on screen rather than blanking the card.
      if (!idea) return;

      const revealed = record.revealed === true;
      revealedRef.current = revealed;

      setCurrentIdea(idea);
      if (typeof record.category === 'string' && CATEGORY_IDS.has(record.category)) {
        setSelectedCategory(record.category);
      }
      setIsRevealed(revealed);
      // Fresh coating for the newly adopted idea.
      setCardKey((prev) => prev + 1);
    }

    adopt();
    return () => {
      active = false;
    };
  }, [storedState, cryptoKey]);

  /* --------------------------------------------------------------------- *
   * Rolling and revealing
   * --------------------------------------------------------------------- */

  /**
   * Rolls a new idea.
   *
   * The category is an ARGUMENT, not read from state. The category pills used to
   * call setSelectedCategory() and then pickRandomIdea() in the same handler,
   * where the latter still saw the previous render's filter - so tapping
   * "Foodie" rolled an idea from whatever category had been selected before it.
   *
   * @param {string} [categoryId] Defaults to the current filter.
   */
  const pickRandomIdea = useCallback(
    (categoryId = selectedCategory) => {
      tap();

      const pool = ideasIn(categoryId);
      if (pool.length === 0) return;

      const available =
        pool.length > 1 ? pool.filter((idea) => idea.id !== currentIdea?.id) : pool;
      const picked = available[Math.floor(Math.random() * available.length)] || pool[0];

      revealedRef.current = false;
      setCurrentIdea(picked);
      setIsRevealed(false);
      setCardKey((prev) => prev + 1);

      persist({ ideaId: picked.id, category: categoryId, revealed: false });
    },
    [selectedCategory, currentIdea, tap, persist]
  );

  const handleRevealed = useCallback(() => {
    if (revealedRef.current) return;
    revealedRef.current = true;

    setIsRevealed(true);
    celebration();
    fireHeartConfetti();

    persist({ ideaId: currentIdea?.id, category: selectedCategory, revealed: true });
  }, [currentIdea, selectedCategory, celebration, persist]);

  /**
   * The canvas effect must not re-run when handleRevealed's identity changes -
   * that would wipe a half-scratched card - so it reads the callback through a
   * ref instead of taking it as a dependency.
   */
  const revealCallbackRef = useRef(handleRevealed);
  useEffect(() => {
    revealCallbackRef.current = handleRevealed;
  }, [handleRevealed]);

  /* --------------------------------------------------------------------- *
   * Scratch surface
   * --------------------------------------------------------------------- */

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;

    // willReadFrequently keeps the surface CPU-side, which is what the periodic
    // getImageData progress check wants; without it Chrome warns and each
    // readback pulls the bitmap back off the GPU.
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const width = canvas.width;
    const height = canvas.height;

    // Draw shimmering pastel scratch-off coating
    const grad = ctx.createLinearGradient(0, 0, width, height);
    grad.addColorStop(0, '#ffd1dc');
    grad.addColorStop(0.5, '#ffe8ed');
    grad.addColorStop(1, '#cdbeff');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, height);

    // Add cute pattern and instructions on the scratch surface
    ctx.fillStyle = '#ff5480';
    ctx.font = 'bold 16px "Plus Jakarta Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('✨ Scratch Here With Your Finger ✨', width / 2, height / 2 - 10);
    ctx.fillStyle = '#94a3b8';
    ctx.font = '12px "Plus Jakarta Sans", sans-serif';
    ctx.fillText('to reveal your romantic date idea 💕', width / 2, height / 2 + 14);

    // Scratching state is per-card and per-gesture, so it lives here rather than
    // in React state: nothing renders from it, and a setState per pointer move
    // would re-render the whole card mid-gesture.
    let isScratching = false;
    let strokes = 0;

    const checkScratchProgress = () => {
      if (revealedRef.current) return;
      try {
        const imgData = ctx.getImageData(0, 0, width, height);
        const data = imgData.data;
        let clearCount = 0;
        let sampled = 0;
        // Alpha channel of every 16th pixel.
        for (let i = 3; i < data.length; i += 64) {
          if (data[i] === 0) clearCount += 1;
          sampled += 1;
        }
        if (sampled > 0 && clearCount / sampled > REVEAL_THRESHOLD) {
          revealCallbackRef.current();
        }
      } catch {
        // getImageData can throw on a tainted canvas; the card is still usable.
      }
    };

    const scratch = (clientX, clientY) => {
      if (revealedRef.current) return;

      const rect = canvas.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return;

      const x = (clientX - rect.left) * (width / rect.width);
      const y = (clientY - rect.top) * (height / rect.height);

      ctx.globalCompositeOperation = 'destination-out';
      ctx.beginPath();
      ctx.arc(x, y, 24, 0, Math.PI * 2);
      ctx.fill();

      strokes += 1;
      if (strokes % STROKES_PER_TICK === 0) tick();
      // A full-canvas getImageData is ~347KB per call. Running one per pointer
      // move pinned a phone at a few frames a second; once per two dozen strokes
      // is still well inside a single swipe.
      if (strokes % STROKES_PER_PROGRESS_CHECK === 0) checkScratchProgress();
    };

    const handleTouchStart = (e) => {
      isScratching = true;
      const touch = e.touches[0];
      if (touch) scratch(touch.clientX, touch.clientY);
    };

    const handleTouchMove = (e) => {
      if (!isScratching) return;
      if (e.cancelable) e.preventDefault();
      const touch = e.touches[0];
      if (touch) scratch(touch.clientX, touch.clientY);
    };

    const handleTouchEnd = () => {
      if (!isScratching) return;
      isScratching = false;
      checkScratchProgress();
    };

    const handleMouseDown = (e) => {
      isScratching = true;
      scratch(e.clientX, e.clientY);
    };

    const handleMouseMove = (e) => {
      if (!isScratching) return;
      scratch(e.clientX, e.clientY);
    };

    const handleMouseUp = () => {
      if (!isScratching) return;
      isScratching = false;
      checkScratchProgress();
    };

    canvas.addEventListener('touchstart', handleTouchStart, { passive: false });
    canvas.addEventListener('touchmove', handleTouchMove, { passive: false });
    canvas.addEventListener('touchend', handleTouchEnd);
    canvas.addEventListener('touchcancel', handleTouchEnd);
    canvas.addEventListener('mousedown', handleMouseDown);
    // Move and release go on the window so dragging off the card mid-scratch
    // neither stops painting nor leaves the gesture stuck open.
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      canvas.removeEventListener('touchstart', handleTouchStart);
      canvas.removeEventListener('touchmove', handleTouchMove);
      canvas.removeEventListener('touchend', handleTouchEnd);
      canvas.removeEventListener('touchcancel', handleTouchEnd);
      canvas.removeEventListener('mousedown', handleMouseDown);
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [cardKey, tick]);

  return (
    <div className="space-y-4">
      {/* Title */}
      <div className="text-center">
        <h2 className="text-2xl font-extrabold text-slate-800 tracking-tight flex items-center justify-center gap-2">
          <span>Date Night Scratch-Off</span>
          <Sparkles className="w-5 h-5 text-amber-500" />
        </h2>
        <p className="text-xs text-slate-500 mt-0.5">
          Scratch with your finger to reveal what we are doing next!
        </p>
      </div>

      {/* Category Pills */}
      <div className="flex items-center justify-center gap-1.5 overflow-x-auto py-1 px-2 no-scrollbar">
        {CATEGORIES.map((cat) => {
          const Icon = cat.icon;
          const isSelected = selectedCategory === cat.id;

          return (
            <button
              key={cat.id}
              onClick={() => {
                setSelectedCategory(cat.id);
                pickRandomIdea(cat.id);
              }}
              className={`inline-flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-semibold transition whitespace-nowrap ${
                isSelected
                  ? 'bg-blush-500 text-white shadow-sm shadow-blush-300'
                  : 'bg-white/80 text-slate-600 border border-blush-100 hover:bg-blush-50'
              }`}
            >
              <Icon className="w-3 h-3" />
              <span>{cat.label}</span>
            </button>
          );
        })}
      </div>

      {/* Interactive Scratch Card */}
      <div className="relative max-w-sm mx-auto aspect-[4/3] rounded-3xl overflow-hidden shadow-2xl border-4 border-white bg-gradient-to-tr from-blush-100 via-white to-lavender-100 p-5 flex flex-col justify-center text-center">
        {/* Underneath: The Revealed Date Idea */}
        <motion.div
          key={currentIdea?.id}
          initial={{ opacity: 0, scale: 0.96 }}
          animate={{ opacity: 1, scale: 1 }}
          className="space-y-2 select-none"
        >
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blush-200/60 text-blush-700 text-[11px] font-bold uppercase tracking-wider mx-auto">
            <Heart className="w-3 h-3 fill-blush-600" />
            <span>Date Idea</span>
          </div>

          <h3 className="text-lg font-black text-slate-800 leading-snug px-2">
            {currentIdea?.title}
          </h3>

          <p className="text-xs text-slate-600 leading-relaxed max-w-xs mx-auto px-2">
            {currentIdea?.desc}
          </p>
        </motion.div>

        {/* Scratch-Off Canvas Layer on Top */}
        <canvas
          key={cardKey}
          ref={canvasRef}
          width={340}
          height={255}
          className={`absolute inset-0 w-full h-full cursor-crosshair transition-opacity duration-500 ${
            isRevealed ? 'opacity-0 pointer-events-none' : 'opacity-100'
          }`}
        />
      </div>

      {/* Control Actions */}
      <div className="flex justify-center gap-3 pt-2">
        <BouncyButton
          onClick={() => pickRandomIdea()}
          className="py-3 px-6 text-sm font-bold gap-2 rounded-2xl"
        >
          <RefreshCw className="w-4 h-4" />
          <span>Roll Another Date Idea</span>
        </BouncyButton>
      </div>
    </div>
  );
}

export default DateRoulette;
