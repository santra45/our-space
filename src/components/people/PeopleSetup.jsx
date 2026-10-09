import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { Heart } from 'lucide-react';
import { usePeople } from '../../context/PeopleContext';
import { useSync } from '../../context/SyncContext';
import { MAX_NAME_LENGTH, PRONOUNS } from '../../services/people';
import BouncyButton from '../common/BouncyButton';
import { useHaptics } from '../../hooks/useHaptics';

const NAMES_WAIT_MS = 12000;

const STILL_SYNCING = new Set(['connecting', 'handshaking', 'authorized', 'syncing']);

const PRONOUN_LABELS = {
  she: 'she / her',
  he: 'he / him',
  they: 'they / them',
};

function PronounPicker({ value, onChange, idPrefix }) {
  return (
    <div className="flex gap-1.5 mt-2">
      {PRONOUNS.map((pronoun) => (
        <button
          key={pronoun}
          type="button"
          id={`${idPrefix}-${pronoun}`}
          onClick={() => onChange(pronoun)}
          className={`flex-1 py-1.5 rounded-xl text-[11px] font-bold transition-colors ${
            value === pronoun
              ? 'bg-lavender-500 text-white'
              : 'bg-lavender-50 text-lavender-600 hover:bg-lavender-100'
          }`}
        >
          {PRONOUN_LABELS[pronoun]}
        </button>
      ))}
    </div>
  );
}

function Shell({ children }) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, y: 24, scale: 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.25, ease: 'easeOut' }}
        className="w-full max-w-sm bg-white rounded-3xl p-6 shadow-2xl border border-lavender-100"
      >
        {children}
      </motion.div>
    </div>
  );
}

export function PeopleSetup() {
  const { status, people, busy, createCouple, claimPerson, refresh } = usePeople();
  const { mailboxEnabled, mailboxState, syncStatus } = useSync();
  const { tap, celebration } = useHaptics();

  const [myName, setMyName] = useState('');
  const [myPronoun, setMyPronoun] = useState('they');
  const [theirName, setTheirName] = useState('');
  const [theirPronoun, setTheirPronoun] = useState('they');
  const [dismissed, setDismissed] = useState(false);
  const [error, setError] = useState('');
  const [waitedOut, setWaitedOut] = useState(false);

  useEffect(() => {
    if (status !== 'empty') {
      setWaitedOut(false);
      return undefined;
    }
    const timer = setTimeout(() => setWaitedOut(true), NAMES_WAIT_MS);
    return () => clearTimeout(timer);
  }, [status]);

  const mailboxSettled =
    !mailboxEnabled || mailboxState.state === 'ok' || mailboxState.state === 'failed';
  const partnerSettling = Boolean(syncStatus && STILL_SYNCING.has(syncStatus.state));
  const stillLooking = status === 'empty' && !waitedOut && (!mailboxSettled || partnerSettling);

  useEffect(() => {
    if (status === 'empty' && mailboxSettled) refresh();
  }, [status, mailboxSettled, refresh]);

  if (status === 'loading' || status === 'locked' || status === 'ready') return null;

  if (status === 'unclaimed') {
    return (
      <Shell>
        <div className="flex items-center gap-2 mb-1">
          <Heart className="w-4 h-4 text-blush-400 fill-blush-400" />
          <span className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide">
            Almost there
          </span>
        </div>
        <p className="font-handwriting text-2xl text-slate-800 leading-snug mb-1">
          Which one of you is this?
        </p>
        <p className="text-xs text-slate-500 leading-relaxed mb-5">
          Tap your own name. It is only so this phone knows whose answers are whose.
        </p>

        <div className="space-y-2">
          {people.map((person, index) => (
            <BouncyButton
              key={person.personId}
              type="button"
              variant={index === 0 ? 'primary' : 'lavender'}
              disabled={busy}
              onClick={async () => {
                tap();
                const ok = await claimPerson(person.personId);
                if (ok) celebration();
                else setError('That did not save. Try again in a moment.');
              }}
              className="w-full py-3.5 text-base font-bold disabled:opacity-50"
            >
              {person.name || 'This one'}
            </BouncyButton>
          ))}
        </div>

        {error && (
          <p role="alert" className="text-[11px] text-rose-600 font-semibold mt-3 text-center">
            {error}
          </p>
        )}

        <p className="text-[10px] text-slate-400 text-center leading-relaxed mt-4">
          Picked the wrong one? You can switch any time from the Pair &amp; Sync Hub.
        </p>
      </Shell>
    );
  }

  if (dismissed || stillLooking) return null;

  const canSave = myName.trim().length > 0 && theirName.trim().length > 0;

  return (
    <Shell>
      <div className="flex items-center gap-2 mb-1">
        <Heart className="w-4 h-4 text-blush-400 fill-blush-400" />
        <span className="text-[11px] font-bold text-lavender-500 uppercase tracking-wide">
          One small thing
        </span>
      </div>
      <p className="font-handwriting text-2xl text-slate-800 leading-snug mb-1">
        What should we call you two?
      </p>
      <p className="text-xs text-slate-500 leading-relaxed mb-2">
        So this place can use your names instead of saying &ldquo;your partner&rdquo; forever.
      </p>
      <p className="text-[11px] text-amber-700 leading-relaxed mb-5">
        Only do this on one phone. If the other phone already has your names, they will arrive
        here by themselves.
      </p>

      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (!canSave || busy) return;
          setError('');
          const ok = await createCouple(
            { name: myName, pronoun: myPronoun },
            { name: theirName, pronoun: theirPronoun }
          );
          if (ok) celebration();
          else setError('That did not save. Try again in a moment.');
        }}
        className="space-y-4"
      >
        <div>
          <label
            htmlFor="people-my-name"
            className="text-[11px] font-bold text-slate-500 uppercase tracking-wide"
          >
            You
          </label>
          <input
            id="people-my-name"
            value={myName}
            onChange={(e) => setMyName(e.target.value)}
            maxLength={MAX_NAME_LENGTH}
            autoFocus
            placeholder="Your name"
            className="w-full mt-1 px-4 py-2.5 bg-white border border-lavender-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-lavender-300 placeholder:text-slate-400"
          />
          <PronounPicker value={myPronoun} onChange={setMyPronoun} idPrefix="people-my-pronoun" />
        </div>

        <div>
          <label
            htmlFor="people-their-name"
            className="text-[11px] font-bold text-slate-500 uppercase tracking-wide"
          >
            Them
          </label>
          <input
            id="people-their-name"
            value={theirName}
            onChange={(e) => setTheirName(e.target.value)}
            maxLength={MAX_NAME_LENGTH}
            placeholder="Their name"
            className="w-full mt-1 px-4 py-2.5 bg-white border border-lavender-200 rounded-2xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-lavender-300 placeholder:text-slate-400"
          />
          <PronounPicker
            value={theirPronoun}
            onChange={setTheirPronoun}
            idPrefix="people-their-pronoun"
          />
        </div>

        {error && (
          <p role="alert" className="text-[11px] text-rose-600 font-semibold">
            {error}
          </p>
        )}

        <BouncyButton
          type="submit"
          disabled={!canSave || busy}
          className="w-full py-3 text-sm font-bold disabled:opacity-50"
        >
          {busy ? 'Saving…' : 'That’s us 💕'}
        </BouncyButton>

        <button
          type="button"
          onClick={() => {
            tap();
            setDismissed(true);
          }}
          className="w-full text-[11px] font-bold text-slate-400 hover:text-slate-600"
        >
          Already did this on the other phone
        </button>
      </form>
    </Shell>
  );
}

export default PeopleSetup;
