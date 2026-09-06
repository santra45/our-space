/**
 * src/components/layout/BottomNav.jsx
 * Mobile thumb-friendly bottom navigation bar with pastel active indicators
 */
import React from 'react';
import { motion } from 'framer-motion';
import { Heart, Camera, Sparkles, Mail, CheckSquare } from 'lucide-react';
import { useHaptics } from '../../hooks/useHaptics';

const NAV_ITEMS = [
  { id: 'countdown', label: 'Love', icon: Heart },
  { id: 'polaroids', label: 'Memories', icon: Camera },
  { id: 'roulette', label: 'Dates', icon: Sparkles },
  { id: 'capsule', label: 'Letters', icon: Mail },
  { id: 'bucketlist', label: 'Bucket', icon: CheckSquare },
];

export function BottomNav({ activeTab, onSelectTab }) {
  const { tick } = useHaptics();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-40 px-3 pb-[calc(env(safe-area-inset-bottom,8px)+6px)] pt-2 bg-white/85 backdrop-blur-lg border-t border-blush-100 shadow-[0_-8px_25px_rgba(255,182,193,0.2)]">
      <div className="max-w-md mx-auto flex items-center justify-around">
        {NAV_ITEMS.map((item) => {
          const Icon = item.icon;
          const isActive = activeTab === item.id;

          return (
            <button
              key={item.id}
              onClick={() => {
                tick();
                onSelectTab(item.id);
              }}
              className="relative flex flex-col items-center justify-center py-1 px-3 select-none transition-colors"
            >
              {isActive && (
                <motion.div
                  layoutId="activePill"
                  className="absolute inset-0 bg-blush-100 rounded-2xl -z-10"
                  transition={{ type: 'spring', stiffness: 450, damping: 30 }}
                />
              )}
              <motion.div
                animate={isActive ? { scale: 1.15, y: -2 } : { scale: 1, y: 0 }}
                transition={{ type: 'spring', stiffness: 350, damping: 20 }}
              >
                <Icon
                  className={`w-5 h-5 transition-colors ${
                    isActive
                      ? 'text-blush-500 fill-blush-200'
                      : 'text-slate-400 hover:text-slate-600'
                  }`}
                />
              </motion.div>
              <span
                className={`text-[10px] mt-1 font-semibold transition-colors ${
                  isActive ? 'text-blush-600' : 'text-slate-400'
                }`}
              >
                {item.label}
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}

export default BottomNav;
