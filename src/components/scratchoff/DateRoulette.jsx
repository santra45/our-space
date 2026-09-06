/**
 * src/components/scratchoff/DateRoulette.jsx
 * Interactive digital scratch-off card and roulette for romantic date ideas
 */
import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Sparkles, RefreshCw, Plus, Home, Trees, Utensils, PiggyBank, Heart } from 'lucide-react';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireCelebrationBurst, fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

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

export function DateRoulette() {
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [currentIdea, setCurrentIdea] = useState(DEFAULT_IDEAS[0]);
  const [isRevealed, setIsRevealed] = useState(false);
  const [isScratching, setIsScratching] = useState(false);
  const [cardKey, setCardKey] = useState(0);

  const canvasRef = useRef(null);
  const { tap, tick, celebration } = useHaptics();

  // Filter ideas
  const filteredIdeas = selectedCategory === 'all'
    ? DEFAULT_IDEAS
    : DEFAULT_IDEAS.filter((i) => i.category === selectedCategory);

  // Pick a random idea
  const pickRandomIdea = () => {
    tap();
    const available = filteredIdeas.length > 1
      ? filteredIdeas.filter((i) => i.id !== currentIdea?.id)
      : filteredIdeas;
    const picked = available[Math.floor(Math.random() * available.length)];
    setCurrentIdea(picked);
    setIsRevealed(false);
    setCardKey((prev) => prev + 1);
  };

  // Initialize Canvas scratch-off surface
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
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

    // Track percentage scratched
    let scratchedPixels = 0;
    const totalPixels = width * height;

    const scratch = (clientX, clientY) => {
      const rect = canvas.getBoundingClientRect();
      const x = (clientX - rect.left) * (canvas.width / rect.width);
      const y = (clientY - rect.top) * (canvas.height / rect.height);

      ctx.globalCompositeOperation = 'destination-out';
      ctx.beginPath();
      ctx.arc(x, y, 24, 0, Math.PI * 2);
      ctx.fill();

      tick();

      scratchedPixels += 1;
      if (scratchedPixels > 25 && !isRevealed) {
        // Quick check
        checkScratchProgress();
      }
    };

    const checkScratchProgress = () => {
      try {
        const imgData = ctx.getImageData(0, 0, width, height);
        let clearCount = 0;
        // Sample every 16th pixel for high mobile performance
        for (let i = 3; i < imgData.data.length; i += 64) {
          if (imgData.data[i] === 0) clearCount++;
        }
        const ratio = clearCount / (imgData.data.length / 64);
        if (ratio > 0.4) {
          setIsRevealed(true);
          celebration();
          fireHeartConfetti();
        }
      } catch (e) {
        // ignore
      }
    };

    // Touch events for Android mobile
    const handleTouchStart = (e) => {
      setIsScratching(true);
      const touch = e.touches[0];
      scratch(touch.clientX, touch.clientY);
    };

    const handleTouchMove = (e) => {
      if (e.cancelable) e.preventDefault();
      const touch = e.touches[0];
      scratch(touch.clientX, touch.clientY);
    };

    const handleTouchEnd = () => {
      setIsScratching(false);
      checkScratchProgress();
    };

    // Mouse events for desktop testing
    const handleMouseDown = (e) => {
      setIsScratching(true);
      scratch(e.clientX, e.clientY);
    };

    const handleMouseMove = (e) => {
      if (!isScratching) return;
      scratch(e.clientX, e.clientY);
    };

    const handleMouseUp = () => {
      setIsScratching(false);
      checkScratchProgress();
    };

    canvas.addEventListener('touchstart', handleTouchStart, { passive: false });
    canvas.addEventListener('touchmove', handleTouchMove, { passive: false });
    canvas.addEventListener('touchend', handleTouchEnd);
    canvas.addEventListener('mousedown', handleMouseDown);
    canvas.addEventListener('mousemove', handleMouseMove);
    canvas.addEventListener('mouseup', handleMouseUp);

    return () => {
      canvas.removeEventListener('touchstart', handleTouchStart);
      canvas.removeEventListener('touchmove', handleTouchMove);
      canvas.removeEventListener('touchend', handleTouchEnd);
      canvas.removeEventListener('mousedown', handleMouseDown);
      canvas.removeEventListener('mousemove', handleMouseMove);
      canvas.removeEventListener('mouseup', handleMouseUp);
    };
  }, [cardKey]);

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
                tap();
                setSelectedCategory(cat.id);
                pickRandomIdea();
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
        <div className="space-y-2 select-none">
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blush-200/60 text-blush-700 text-[11px] font-bold uppercase tracking-wider mx-auto">
            <Heart className="w-3 h-3 fill-blush-600" />
            <span>Date Idea</span>
          </div>

          <h3 className="text-lg font-black text-slate-800 leading-snug px-2">
            {currentIdea.title}
          </h3>

          <p className="text-xs text-slate-600 leading-relaxed max-w-xs mx-auto px-2">
            {currentIdea.desc}
          </p>
        </div>

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
          onClick={pickRandomIdea}
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
