/**
 * src/components/layout/LockScreen.jsx
 * Zero-knowledge vault unlock, partner pairing, and initial setup screen
 */
import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Heart,
  Lock,
  KeyRound,
  Sparkles,
  Eye,
  EyeOff,
  ShieldCheck,
  Users,
  Link2,
  UserCheck,
} from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { MIN_PASSPHRASE_LENGTH } from '../../services/crypto';
import { parseInvite } from '../../utils/invite';
import GlassCard from '../common/GlassCard';
import BouncyButton from '../common/BouncyButton';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

export function LockScreen() {
  const {
    isVaultInitialized,
    unlockVault,
    initializeVault,
    initializeFromPartnerInvite,
    vaultSalt,
    error: vaultError,
  } = useVault();

  const [passphrase, setPassphrase] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [coupleNames, setCoupleNames] = useState('');
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0]);
  const [partnerInviteInput, setPartnerInviteInput] = useState('');
  const [inviteData, setInviteData] = useState(null);
  const [mode, setMode] = useState('unlock'); // 'unlock' | 'setup' | 'join'
  const [loading, setLoading] = useState(false);
  const [localError, setLocalError] = useState(null);
  const { celebration, tap } = useHaptics();

  // Detect invite link in URL hash on mount and on hash change
  useEffect(() => {
    const handleHash = () => {
      const invite = parseInvite(window.location.hash);
      if (invite && (invite.partnerPeerId || invite.salt)) {
        setInviteData(invite);
        if (invite.salt) {
          setMode('join');
        }
      }
    };

    handleHash();
    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, []);

  // Update default mode once vault initialization state is known
  useEffect(() => {
    if (isVaultInitialized === false) {
      if (!inviteData?.salt) {
        setMode((prev) => (prev === 'join' ? 'join' : 'setup'));
      } else {
        setMode('join');
      }
    } else if (isVaultInitialized === true) {
      if (!inviteData?.salt) {
        setMode('unlock');
      } else {
        setMode('join');
      }
    }
  }, [isVaultInitialized, inviteData]);

  const handleUnlock = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (!passphrase.trim() || passphrase.length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`);
      return;
    }
    setLoading(true);
    tap();

    const success = await unlockVault(passphrase);
    setLoading(false);
    if (success) {
      if (inviteData?.partnerPeerId) {
        try {
          sessionStorage.setItem('pending_partner_connect', inviteData.partnerPeerId);
          localStorage.setItem('sweetheart_paired_partner_id', inviteData.partnerPeerId);
        } catch {}
      }
      setPassphrase('');
      celebration();
      fireHeartConfetti();
    }
  };

  const handleSetup = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (!passphrase.trim() || passphrase.length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(`Please choose a memorable secret passphrase of at least ${MIN_PASSPHRASE_LENGTH} characters.`);
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
      setPassphrase('');
      celebration();
      fireHeartConfetti();
    }
  };

  const handleJoin = async (e) => {
    e.preventDefault();
    setLocalError(null);
    if (!passphrase.trim() || passphrase.length < MIN_PASSPHRASE_LENGTH) {
      setLocalError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters.`);
      return;
    }

    let saltToUse = inviteData?.salt;
    let partnerIdToConnect = inviteData?.partnerPeerId;
    let startDateFromInvite = inviteData?.startDate;
    let coupleNamesFromInvite = inviteData?.coupleNames;

    // If invite data was not from URL hash, parse user's manual input
    if (!saltToUse) {
      const parsed = parseInvite(partnerInviteInput);
      if (!parsed || !parsed.salt) {
        setLocalError(
          'Please paste a valid invite link containing your partner\'s vault salt (e.g. copied from WhatsApp or QR code).'
        );
        return;
      }
      saltToUse = parsed.salt;
      partnerIdToConnect = parsed.partnerPeerId;
      startDateFromInvite = parsed.startDate;
      coupleNamesFromInvite = parsed.coupleNames;
    }

    setLoading(true);
    tap();

    const success = await initializeFromPartnerInvite(passphrase, saltToUse, {
      startDate: startDateFromInvite,
      coupleNames: coupleNamesFromInvite,
    });
    setLoading(false);

    if (success) {
      if (partnerIdToConnect) {
        try {
          sessionStorage.setItem('pending_partner_connect', partnerIdToConnect);
          localStorage.setItem('sweetheart_paired_partner_id', partnerIdToConnect);
        } catch {}
      }
      setPassphrase('');
      celebration();
      fireHeartConfetti();
    }
  };

  const displayError = localError || vaultError;

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
          {/* Mode Switcher for Uninitialized Devices */}
          {!isVaultInitialized && (
            <div className="flex bg-slate-100/80 p-1 rounded-2xl mb-5">
              <button
                type="button"
                onClick={() => {
                  tap();
                  setMode('setup');
                  setLocalError(null);
                }}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition flex items-center justify-center gap-1.5 ${
                  mode === 'setup'
                    ? 'bg-white text-slate-800 shadow-sm'
                    : 'text-slate-500 hover:text-slate-700'
                }`}
              >
                <Sparkles className="w-3.5 h-3.5 text-blush-500" />
                <span>Create New Space</span>
              </button>
              <button
                type="button"
                onClick={() => {
                  tap();
                  setMode('join');
                  setLocalError(null);
                }}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition flex items-center justify-center gap-1.5 ${
                  mode === 'join'
                    ? 'bg-white text-slate-800 shadow-sm'
                    : 'text-slate-500 hover:text-slate-700'
                }`}
              >
                <Users className="w-3.5 h-3.5 text-indigo-500" />
                <span>Join Partner's Space</span>
              </button>
            </div>
          )}

          {/* MODE 1: UNLOCK EXISTING VAULT */}
          {mode === 'unlock' && (
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
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                    }}
                    placeholder="Enter your secret passphrase (min 16 chars)..."
                    required
                    minLength={16}
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

              {displayError && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
                  {displayError}
                </div>
              )}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim()}
                className="w-full py-3.5 text-base font-bold shadow-md shadow-blush-300/40"
              >
                {loading ? 'Deriving Key...' : 'Unlock Our Space 💕'}
              </BouncyButton>

              <div className="pt-2 flex flex-col gap-1.5 text-center">
                <button
                  type="button"
                  onClick={() => {
                    tap();
                    setMode('join');
                    setLocalError(null);
                  }}
                  className="text-xs text-indigo-600 hover:text-indigo-700 underline font-medium"
                >
                  Joining partner's space with an invite link?
                </button>
                <button
                  type="button"
                  onClick={() => {
                    tap();
                    setMode('setup');
                    setLocalError(null);
                  }}
                  className="text-xs text-slate-400 hover:text-slate-600 underline"
                >
                  Create a fresh new space instead
                </button>
              </div>
            </form>
          )}

          {/* MODE 2: JOIN PARTNER'S SPACE (Via Link or Manual Code) */}
          {mode === 'join' && (
            <form onSubmit={handleJoin} className="space-y-4">
              <div className="text-center mb-3">
                <div className="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-xs font-bold">
                  <UserCheck className="w-3.5 h-3.5 text-indigo-500" />
                  <span>Join Partner's Space 💕</span>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  {inviteData?.partnerPeerId
                    ? `Partner device (${inviteData.partnerPeerId}) invited you!`
                    : 'Pair your device directly with your partner using their invite link.'}
                </p>
              </div>

              {/* If no salt was found in URL, show manual invite input */}
              {!inviteData?.salt && (
                <div>
                  <label className="block text-xs font-semibold text-slate-600 mb-1">
                    Partner's Invite Link or Code
                  </label>
                  <div className="relative">
                    <input
                      type="text"
                      value={partnerInviteInput}
                      onChange={(e) => {
                        setPartnerInviteInput(e.target.value);
                        if (localError) setLocalError(null);
                      }}
                      placeholder="Paste link (e.g. https://...#connect=...)"
                      required
                      className="w-full px-4 py-2.5 pl-10 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-400 placeholder:text-slate-400 transition"
                    />
                    <Link2 className="w-4 h-4 text-slate-400 absolute left-3.5 top-3" />
                  </div>
                  <p className="text-[11px] text-slate-400 mt-1">
                    Ask your partner to tap "Share Pairing Link" in their Sync Hub and paste the link here.
                  </p>
                </div>
              )}

              {inviteData?.salt && (
                <div className="p-2.5 bg-emerald-50/70 border border-emerald-100 rounded-xl text-[11px] text-emerald-800 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  <span>Partner's encryption salt verified! Enter your shared passphrase to pair.</span>
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Shared Secret Passphrase
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={passphrase}
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                    }}
                    placeholder="Enter the secret phrase you both agreed on..."
                    required
                    minLength={16}
                    autoFocus
                    className="w-full px-4 py-3 pl-10 pr-11 bg-white/70 border border-blush-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 placeholder:text-slate-400 transition"
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
                  Must match partner's passphrase exactly to derive the identical 256-bit AES key.
                </p>
              </div>

              {displayError && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
                  {displayError}
                </div>
              )}

              <BouncyButton
                type="submit"
                disabled={loading || !passphrase.trim()}
                className="w-full py-3.5 text-base font-bold bg-indigo-600 hover:bg-indigo-700 text-white shadow-md shadow-indigo-300/40"
              >
                {loading ? 'Deriving Key & Pairing...' : 'Pair & Enter Our Space 💕'}
              </BouncyButton>

              {isVaultInitialized && (
                <div className="pt-1 text-center">
                  <button
                    type="button"
                    onClick={() => {
                      tap();
                      setMode('unlock');
                      setLocalError(null);
                    }}
                    className="text-xs text-slate-500 hover:text-slate-700 underline"
                  >
                    Cancel and return to unlock
                  </button>
                </div>
              )}
            </form>
          )}

          {/* MODE 3: CREATE NEW SPACE (Initiator First-Time Setup) */}
          {mode === 'setup' && (
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
                    onChange={(e) => {
                      setPassphrase(e.target.value);
                      if (localError) setLocalError(null);
                    }}
                    placeholder="Create a shared secret phrase (min 16 chars)..."
                    required
                    minLength={16}
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
                  Must be at least 16 characters (e.g. a memorable secret sentence only you two know).
                </p>
              </div>

              {displayError && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-xs font-medium text-center">
                  {displayError}
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
                    onClick={() => {
                      tap();
                      setMode('unlock');
                      setLocalError(null);
                    }}
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
