/**
 * src/components/layout/LockScreen.jsx
 * Zero-knowledge vault unlock and initial pair/setup screen
 */
import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Heart, Lock, KeyRound, Sparkles, Eye, EyeOff, ShieldCheck } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

export function LockScreen() {
  const { isVaultInitialized, unlockVault, initializeVault, error } = useVault();
  const [passphrase, setPassphrase] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [coupleNames, setCoupleNames] = useState('');
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0]);
  const [isSettingUp, setIsSettingUp] = useState(!isVaultInitialized);
  const [loading, setLoading] = useState(false);
  const { celebration, tap } = useHaptics();

  const handleUnlock = async (e) => {
    e.preventDefault();
    if (!passphrase.trim()) return;
    setLoading(true);
    tap();

    const success = await unlockVault(passphrase);
    setLoading(false);
    if (success) {
      celebration();
      fireHeartConfetti();
    }
  };

  const handleSetup = async (e) => {
    e.preventDefault();
    if (!passphrase.trim() || passphrase.length < 4) {
      alert('Please choose a memorable secret passphrase of at least 4 characters.');
      return;
    }
    setLoading(true);
    tap();

    const success = await initializeVault(passphrase, {
      coupleNames: coupleNames.trim() || 'Us',
      startDate,
    });
    setLoading(false);
    if (success) {
      celebration();
      fireHeartConfetti();
    }
  };

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-4 relative z-10">
      <motion.div
        initial={{ opacity: 0, y: 20, scale: 0.95 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.5, ease: 'easeOut' }}
        className="w-full max-w-md"
      >
        {/* Cute Icon Avatar */}
        <div className="text-center mb-6">
          <motion.div
            animate={{
              scale: [1, 1.08, 1],
              rotate: [0, -3, 3, 0],
            }}
            transition={{
              repeat: Infinity,
              duration: 3,
              ease: 'easeInOut',
            }}
            className="w-20 h-20 mx-auto rounded-full bg-gradient-to-tr from-blush-300 via-blush-200 to-lavender-200 flex items-center justify-center shadow-lg shadow-blush-200/50 border-4 border-white"
          >
            <Heart className="w-10 h-10 text-blush-500 fill-blush-400" />
          </motion.div>
          <h1 className="text-3xl font-extrabold text-slate-800 mt-4 tracking-tight">
            Our Space 💕
          </h1>
          <p className="text-sm text-slate-500 mt-1 font-medium">
            Private, Encrypted Sanctuary For Two
          </p>
        </div>

        <GlassCard className="border-2 border-blush-100 shadow-xl shadow-blush-200/30">
          {/* Form */}
          {isVaultInitialized && !isSettingUp ? (
            <form onSubmit={handleUnlock} className="space-y-4">
              <div className="text-center mb-4">
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blush-100/70 text-blush-600 text-xs font-semibold">
                  <Lock className="w-3.5 h-3.5" />
                  <span>Vault Locked</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Enter your shared secret passphrase to unlock your private memories and notes.
                </p>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => setPassphrase(e.target.value)}
                    placeholder="Enter your shared passphrase..."
                    required
                    autoFocus
                    className="w-full px-4 py-3 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                  />
                  <KeyRound className="w-4 h-4 text-slate-400 absolute left-3.5 top-3.5" />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-slate-400 hover:text-slate-600"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {error && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
                  {error}
                </div>
              )}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim()}
                className="w-full py-3.5 text-base font-bold shadow-md shadow-blush-300/40"
              >
                {loading ? 'Deriving Key...' : 'Unlock Our Space 💕'}
              </BouncyButton>

              <div className="pt-2 text-center">
                <button
                  type="button"
                  onClick={() => setIsSettingUp(true)}
                  className="text-xs text-blush-600 hover:text-blush-700 underline font-medium"
                >
                  Need to re-initialize or setup fresh vault?
                </button>
              </div>
            </form>
          ) : (
            <form onSubmit={handleSetup} className="space-y-4">
              <div className="text-center mb-2">
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-lavender-100 text-lavender-700 text-xs font-semibold">
                  <Sparkles className="w-3.5 h-3.5 text-lavender-500" />
                  <span>Setup Your Private Space</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Choose a passphrase only the two of you know. It derives your AES-GCM 256 encryption key.
                </p>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Your Nicknames / Couple Name
                </label>
                <input
                  type="text"
                  value={coupleNames}
                  onChange={(e) => setCoupleNames(e.target.value)}
                  placeholder="e.g. Romeo & Juliet"
                  className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  When Did Your Story Begin?
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  required
                  className="w-full px-4 py-2.5 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 transition"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Shared Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => setPassphrase(e.target.value)}
                    placeholder="Shared secret between the two of you..."
                    required
                    minLength={4}
                    className="w-full px-4 py-2.5 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-blush-400 placeholder:text-slate-400 transition"
                  />
                  <KeyRound className="w-4 h-4 text-slate-400 absolute left-3.5 top-3.5" />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-slate-400 hover:text-slate-600"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
                <p className="text-[11px] text-slate-400 mt-1">
                  Give this exact same passphrase to your partner so she can unlock or pair.
                </p>
              </div>

              {error && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
                  {error}
                </div>
              )}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim()}
                className="w-full py-3.5 text-base font-bold"
              >
                {loading ? 'Deriving 256-bit Key...' : 'Create Vault & Start 💕'}
              </BouncyButton>

              {isVaultInitialized && (
                <div className="pt-1 text-center">
                  <button
                    type="button"
                    onClick={() => setIsSettingUp(false)}
                    className="text-xs text-slate-500 hover:text-slate-700 underline"
                  >
                    Cancel and return to unlock
                  </button>
                </div>
              )}
            </form>
          )}

          {/* Security badge */}
          <div className="mt-5 pt-4 border-t border-blush-100/80 flex items-center justify-center gap-2 text-slate-400 text-[11px]">
            <ShieldCheck className="w-4 h-4 text-emerald-500" />
            <span>AES-GCM 256 Zero-Knowledge • 100% Local Encrypted</span>
          </div>
        </GlassCard>
      </motion.div>
    </div>
  );
}

export default LockScreen;
