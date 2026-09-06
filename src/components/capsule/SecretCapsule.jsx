/**
 * src/components/capsule/SecretCapsule.jsx
 * Time-locked love letters and digital time capsule
 */
import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Mail, Lock, Unlock, Plus, Clock, Sparkles, X, Heart } from 'lucide-react';
import { useLiveQuery } from 'dexie-react-hooks';
import db from '../../db';
import { useVault } from '../../context/VaultContext';
import { encryptText, decryptText } from '../../services/crypto';
import peerSync from '../../services/peerSync';
import { isDateLocked, formatTimeRemaining, formatDatePretty } from '../../utils/dateHelpers';
import LetterEnvelope from './LetterEnvelope';
import BouncyButton from '../common/BouncyButton';
import GlassCard from '../common/GlassCard';
import { fireHeartConfetti } from '../common/ConfettiBurst';
import { useHaptics } from '../../hooks/useHaptics';

export function SecretCapsule() {
  const { cryptoKey } = useVault();
  const [isWriteModalOpen, setIsWriteModalOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [unlockDate, setUnlockDate] = useState('');
  const [activeReadingLetter, setActiveReadingLetter] = useState(null);
  const [saving, setSaving] = useState(false);
  const { tap, celebration } = useHaptics();

  // Load letters from IndexedDB
  const storedLetters = useLiveQuery(
    () => db.letters.filter((l) => !l.deleted).toArray(),
    []
  );

  const [decryptedLetters, setDecryptedLetters] = useState([]);

  useEffect(() => {
    async function decryptList() {
      if (!storedLetters || !cryptoKey) return;
      const list = [];
      for (const item of storedLetters) {
        const locked = isDateLocked(item.unlockDate);
        try {
          const decryptedTitle = await decryptText(item.titleCipher, item.titleIv, cryptoKey);
          let decryptedContent = '';
          // Only decrypt content if unlocked!
          if (!locked) {
            decryptedContent = await decryptText(item.contentCipher, item.contentIv, cryptoKey);
          }
          list.push({
            ...item,
            title: decryptedTitle,
            content: decryptedContent,
            isLocked: locked,
          });
        } catch {
          list.push({
            ...item,
            title: 'Encrypted Letter',
            content: '',
            isLocked: locked,
          });
        }
      }
      setDecryptedLetters(list.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt)));
    }
    decryptList();
  }, [storedLetters, cryptoKey]);

  const handleSaveLetter = async (e) => {
    e.preventDefault();
    if (!title.trim() || !content.trim() || !cryptoKey) return;

    try {
      setSaving(true);
      tap();

      const { ciphertext: titleCipher, iv: titleIv } = await encryptText(title.trim(), cryptoKey);
      const { ciphertext: contentCipher, iv: contentIv } = await encryptText(content.trim(), cryptoKey);

      const newRecord = {
        id: 'let-' + Date.now(),
        titleCipher,
        titleIv,
        contentCipher,
        contentIv,
        unlockDate: unlockDate ? new Date(unlockDate).toISOString() : null,
        isOpened: false,
        updatedAt: Date.now(),
        deleted: false,
      };

      await db.letters.put(newRecord);
      peerSync.broadcastLiveRecord('letters', newRecord);

      celebration();
      fireHeartConfetti();
      setTitle('');
      setContent('');
      setUnlockDate('');
      setIsWriteModalOpen(false);
    } catch {
      alert('Error saving letter. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header bar */}
      <div className="flex items-center justify-between px-1">
        <div>
          <h2 className="text-xl font-extrabold text-slate-800 tracking-tight flex items-center gap-2">
            <span>Secret Capsule</span>
            <Sparkles className="w-4 h-4 text-amber-500" />
          </h2>
          <p className="text-xs text-slate-500">Time-locked letters & sweet notes</p>
        </div>

        <BouncyButton
          onClick={() => {
            tap();
            setIsWriteModalOpen(true);
          }}
          className="py-2 px-3.5 text-xs gap-1.5 rounded-full"
        >
          <Plus className="w-4 h-4" />
          <span>Write Letter</span>
        </BouncyButton>
      </div>

      {/* Letters List */}
      {decryptedLetters.length === 0 ? (
        <div className="text-center py-16 px-4 bg-white/50 rounded-3xl border-2 border-dashed border-blush-200">
          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-blush-100 text-blush-400 flex items-center justify-center">
            <Mail className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-slate-700">No Letters Yet</h3>
          <p className="text-xs text-slate-500 max-w-xs mx-auto mt-1 mb-5">
            Leave a surprise letter for your partner, or seal a time capsule to open on your next anniversary!
          </p>
          <BouncyButton
            onClick={() => setIsWriteModalOpen(true)}
            className="text-xs py-2.5 px-5 rounded-full"
          >
            Write First Love Letter 💌
          </BouncyButton>
        </div>
      ) : (
        <div className="space-y-3">
          {decryptedLetters.map((letter) => (
            <GlassCard
              key={letter.id}
              hoverEffect={!letter.isLocked}
              onClick={() => {
                if (!letter.isLocked) {
                  tap();
                  setActiveReadingLetter(letter);
                } else {
                  tap();
                  alert(`This letter is time-locked until ${formatDatePretty(letter.unlockDate)}! No peeking! 🙈`);
                }
              }}
              className={`p-4 transition cursor-pointer border ${
                letter.isLocked
                  ? 'bg-slate-50/70 border-slate-200 opacity-80 cursor-not-allowed'
                  : 'bg-white/80 border-blush-100 hover:border-blush-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div
                    className={`w-10 h-10 rounded-2xl flex items-center justify-center shadow-sm ${
                      letter.isLocked
                        ? 'bg-slate-200 text-slate-500'
                        : 'bg-blush-100 text-blush-600'
                    }`}
                  >
                    {letter.isLocked ? <Lock className="w-5 h-5" /> : <Mail className="w-5 h-5" />}
                  </div>
                  <div>
                    <h4 className="text-sm font-bold text-slate-800">{letter.title}</h4>
                    <p className="text-[11px] text-slate-400">
                      Written on {formatDatePretty(letter.updatedAt)}
                    </p>
                  </div>
                </div>

                <div>
                  {letter.isLocked ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-slate-200/80 text-slate-600 text-[10px] font-bold">
                      <Clock className="w-3 h-3" />
                      <span>{formatTimeRemaining(letter.unlockDate)}</span>
                    </div>
                  ) : (
                    <span className="text-xs font-semibold text-blush-600 hover:underline">
                      Read Letter 💌
                    </span>
                  )}
                </div>
              </div>
            </GlassCard>
          ))}
        </div>
      )}

      {/* Reading modal */}
      {activeReadingLetter && (
        <LetterEnvelope
          letter={activeReadingLetter}
          onClose={() => setActiveReadingLetter(null)}
        />
      )}

      {/* Write Letter Modal */}
      {isWriteModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 relative"
          >
            <button
              onClick={() => setIsWriteModalOpen(false)}
              className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
            >
              <X className="w-4 h-4" />
            </button>

            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 rounded-full bg-blush-100 text-blush-500 flex items-center justify-center">
                <Heart className="w-4 h-4 fill-blush-400" />
              </div>
              <div>
                <h3 className="text-base font-bold text-slate-800">Write Love Letter</h3>
                <p className="text-[11px] text-slate-400">AES-GCM 256 Encrypted</p>
              </div>
            </div>

            <form onSubmit={handleSaveLetter} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Envelope Title / Prompt
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. Open when you miss me, or 1st Anniversary"
                  required
                  className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Letter Body
                </label>
                <textarea
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  placeholder="Write your heart out..."
                  required
                  rows={6}
                  className="w-full px-3 py-2 text-sm font-handwriting text-lg bg-amber-50/30 border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">
                  Time-Lock Until (Optional)
                </label>
                <input
                  type="date"
                  value={unlockDate}
                  onChange={(e) => setUnlockDate(e.target.value)}
                  className="w-full px-3 py-2 text-xs bg-white border border-blush-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
                />
                <p className="text-[10px] text-slate-400 mt-0.5">
                  Leave blank to allow opening immediately.
                </p>
              </div>

              <BouncyButton
                type="submit"
                disabled={saving || !title.trim() || !content.trim()}
                className="w-full py-3 text-sm font-bold shadow-md shadow-blush-300/40"
              >
                {saving ? 'Encrypting & Sealing...' : 'Seal with Wax Stamp 💌'}
              </BouncyButton>
            </form>
          </motion.div>
        </div>
      )}
    </div>
  );
}

export default SecretCapsule;
