/**
 * src/components/common/GlassCard.jsx
 * Frosted pastel glass container with rounded-3xl corners and smooth border glow
 */
import React from 'react';
import { motion } from 'framer-motion';

export function GlassCard({ children, className = '', hoverEffect = false, ...props }) {
  return (
    <motion.div
      whileHover={hoverEffect ? { y: -3, transition: { duration: 0.2 } } : undefined}
      className={`glass-panel rounded-3xl p-5 shadow-cozy ${className}`}
      {...props}
    >
      {children}
    </motion.div>
  );
}

export default GlassCard;
