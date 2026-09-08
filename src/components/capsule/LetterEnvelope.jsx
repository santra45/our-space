/**
 * src/components/capsule/LetterEnvelope.jsx
 * Interactive envelope opening animation with wax seal and handwritten love letter.
 *
 * By the time a letter reaches this component its body has already been
 * unsealed by SecretCapsule (crypto.unsealTimeLocked), which refuses before the
 * unlock date. Nothing here gates access - breaking the wax seal is animation,
 * not security - so the footer states plainly what the time lock did and did not
 * guarantee rather than implying this modal enforced anything.
 */
import React, { useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { Heart, X, Sparkles, Trash2, Lock } from 'lucide-react';
import { formatDatePretty } from '../../utils/dateHelpers';
import { useHaptics } from '../../hooks/useHaptics';
import { fireHeartConfetti } from '../common/ConfettiBurst';

export function LetterEnvelope({ letter, onClose, onDelete, onOpened }) {
  const [isOpen, setIsOpen] = useState(false);
  const hasReportedOpen = useRef(false);
  const { tap, celebration } = useHaptics();

  const writtenAt = letter.writtenAt || letter.updatedAt;
  const wasTimeLocked = Boolean(letter.lockDate);

  const handleOpenEnvelope = () => {
    if (isOpen) return;
    tap();
    setIsOpen(true);
    if (!hasReportedOpen.current) {
      hasReportedOpen.current = true;
      if (onOpened) onOpened();
    }
    setTimeout(() => {
      celebration();
      fireHeartConfetti();
    }, 400);
  };

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm select-none"
    >
      <div onClick={(e) => e.stopPropagation()} className="w-full max-w-sm relative">
        {/* Close button */}
        <button
          onClick={onClose}
          className="absolute -top-12 right-0 w-8 h-8 rounded-full bg-white/80 text-slate-600 flex items-center justify-center hover:bg-white transition"
        >
          <X className="w-4 h-4" />
        </button>

        {!isOpen ? (
          /* Sealed Envelope state */
          <motion.div
            initial={{ scale: 0.9, y: 20 }}
            animate={{ scale: 1, y: 0 }}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={handleOpenEnvelope}
            className="cursor-pointer bg-gradient-to-tr from-cream-100 to-blush-100 rounded-3xl p-6 shadow-2xl border-2 border-blush-200 text-center relative overflow-hidden"
          >
            {/* Envelope flap line design */}
            <div className="w-24 h-24 mx-auto rounded-full bg-blush-200/50 flex items-center justify-center mb-3">
              <div className="w-14 h-14 rounded-full bg-rose-500 text-white flex items-center justify-center shadow-lg shadow-rose-400/40 border-2 border-white/60">
                <Heart className="w-7 h-7 fill-white" />
              </div>
            </div>

            <h3 className="text-xl font-black text-slate-800 tracking-tight">{letter.title}</h3>

            <p className="text-xs text-slate-500 mt-1 mb-5">
              A private letter written on {formatDatePretty(writtenAt)}
            </p>

            {wasTimeLocked && (
              <p className="text-[11px] text-slate-500 mb-4 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-white/70 border border-slate-200">
                <Lock className="w-3 h-3" />
                <span>Time lock lifted on {formatDatePretty(letter.lockDate)}</span>
              </p>
            )}

            <div className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-blush-500 text-white text-xs font-bold shadow-md shadow-blush-300 animate-pulse">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Tap to Break Wax Seal</span>
            </div>
          </motion.div>
        ) : (
          /* Opened Letter Paper */
          <motion.div
            initial={{ opacity: 0, y: 30, scale: 0.9 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ type: 'spring', stiffness: 350, damping: 25 }}
            className="bg-[#fefcf8] rounded-3xl p-6 shadow-2xl border border-amber-100 relative max-h-[80vh] overflow-y-auto"
          >
            {/* Decorative stationary lines */}
            <div className="border-b border-blush-200/70 pb-3 mb-4 flex items-center justify-between">
              <div>
                <span className="text-[10px] font-bold text-blush-500 uppercase tracking-widest block">
                  Secret Love Letter
                </span>
                <h3 className="text-xl font-bold text-slate-800">{letter.title}</h3>
              </div>
              <Heart className="w-5 h-5 text-blush-400 fill-blush-200" />
            </div>

            {/* Handwritten body text */}
            <div className="font-handwriting text-2xl text-slate-800 leading-relaxed whitespace-pre-wrap py-2">
              {letter.content}
            </div>

            {wasTimeLocked && (
              <p className="mt-5 text-[10px] leading-relaxed text-slate-400 bg-slate-50 border border-slate-200 rounded-2xl px-3 py-2">
                This one was sealed until {formatDatePretty(letter.lockDate)} 💕 The app would
                not open it early — though it was always a promise, not a padlock.
              </p>
            )}

            <div className="mt-6 pt-4 border-t border-amber-200/50 flex justify-between items-center text-xs text-slate-400 font-sans">
              <span>With all my love forever 💕</span>
              <div className="flex items-center gap-3">
                <span>{formatDatePretty(writtenAt)}</span>
                {onDelete && (
                  <button
                    type="button"
                    onClick={onDelete}
                    className="inline-flex items-center gap-1 text-xs text-slate-400 hover:text-rose-500 transition px-2 py-1 rounded-lg hover:bg-rose-50"
                    title="Delete letter"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                    <span>Delete</span>
                  </button>
                )}
              </div>
            </div>
          </motion.div>
        )}
      </div>
    </div>
  );
}

export default LetterEnvelope;
