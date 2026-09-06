/**
 * src/components/common/BouncyButton.jsx
 * Spring animated button with Android haptic tick
 */
import React from 'react';
import { motion } from 'framer-motion';
import { useHaptics } from '../../hooks/useHaptics';

export function BouncyButton({
  children,
  onClick,
  variant = 'primary', // 'primary' | 'secondary' | 'ghost' | 'matcha' | 'lavender'
  className = '',
  disabled = false,
  type = 'button',
  ...props
}) {
  const { tick } = useHaptics();

  const handleClick = (e) => {
    if (disabled) return;
    tick();
    if (onClick) onClick(e);
  };

  const variantClasses = {
    primary:
      'bg-gradient-to-r from-blush-400 to-blush-500 text-white shadow-md shadow-blush-300/40 hover:from-blush-500 hover:to-blush-600',
    secondary:
      'bg-white/80 text-blush-600 border border-blush-200 shadow-sm hover:bg-blush-50',
    matcha:
      'bg-gradient-to-r from-matcha-200 to-matcha-300 text-emerald-800 shadow-sm hover:from-matcha-300 hover:to-matcha-400',
    lavender:
      'bg-gradient-to-r from-lavender-200 to-lavender-300 text-indigo-900 shadow-sm hover:from-lavender-300 hover:to-lavender-400',
    ghost:
      'bg-transparent text-slate-600 hover:bg-blush-100/50 hover:text-blush-600',
  };

  return (
    <motion.button
      type={type}
      disabled={disabled}
      onClick={handleClick}
      whileTap={!disabled ? { scale: 0.94 } : undefined}
      whileHover={!disabled ? { scale: 1.02 } : undefined}
      transition={{ type: 'spring', stiffness: 400, damping: 17 }}
      className={`inline-flex items-center justify-center font-semibold rounded-2xl px-5 py-3 transition-colors select-none disabled:opacity-50 disabled:pointer-events-none text-sm active:shadow-inner ${variantClasses[variant] || variantClasses.primary} ${className}`}
      {...props}
    >
      {children}
    </motion.button>
  );
}

export default BouncyButton;
