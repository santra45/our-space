/**
 * src/components/common/AmbientParticles.jsx
 * Floating gentle pastel hearts and sparkles drifting in the background
 */
import React, { useMemo } from 'react';
import { motion } from 'framer-motion';

export function AmbientParticles() {
  const particles = useMemo(() => {
    return Array.from({ length: 14 }).map((_, i) => ({
      id: i,
      x: Math.random() * 100,
      size: Math.random() * 12 + 10,
      duration: Math.random() * 15 + 12,
      delay: Math.random() * 8,
      type: i % 3 === 0 ? 'sparkle' : 'heart',
      opacity: Math.random() * 0.35 + 0.15,
    }));
  }, []);

  return (
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
      {particles.map((p) => (
        <motion.div
          key={p.id}
          className="absolute text-blush-400 select-none"
          style={{
            left: `${p.x}vw`,
            fontSize: `${p.size}px`,
            opacity: p.opacity,
          }}
          initial={{ y: '105vh', rotate: 0 }}
          animate={{
            y: '-10vh',
            rotate: [0, 15, -15, 0],
            x: [`${p.x}vw`, `${p.x + (Math.random() * 6 - 3)}vw`],
          }}
          transition={{
            duration: p.duration,
            delay: p.delay,
            repeat: Infinity,
            ease: 'linear',
          }}
        >
          {p.type === 'heart' ? '♥' : '✦'}
        </motion.div>
      ))}
    </div>
  );
}

export default AmbientParticles;
