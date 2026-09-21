/**
 * src/components/people/PeopleSetup.jsx
 * The two questions that let the app use your names.
 *
 * TWO STATES, AND THEY FEEL VERY DIFFERENT ON PURPOSE
 *   empty      Nobody has been entered. This is a small warm form, asked once,
 *              by whoever opens the app first.
 *   unclaimed  The names are already here - they arrived over sync - and this
 *              device just needs to know which of you is holding it. That is
 *              ONE TAP, and it must never look like a form, because it is also
 *              what a person sees after their browser quietly discarded
 *              localStorage. Being asked to fill in a form again at that moment
 *              would read as "the app lost our stuff".
 *
 * WHY 'empty' IS DISMISSIBLE AND 'unclaimed' IS NOT
 * Dismissing 'empty' costs nothing: every screen already has neutral copy to
 * fall back on, because that is all it had before people existed. Dismissing
 * 'unclaimed' would leave the app unable to tell whose answers are whose,
 * which is the one thing it must not get wrong - and the cost of answering is a
 * single tap on your own name.
 */
import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Heart } from 'lucide-react';
import { usePeople } from '../../context/PeopleContext';
import { MAX_NAME_LENGTH, PRONOUNS } from '../../services/people';
import BouncyButton from '../common/BouncyButton';
import { useHaptics } from '../../hooks/useHaptics';

/** How each pronoun is offered. The label is a sentence, not a grammar term. */
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
  const { status, people, busy, createCouple, claimPerson } = usePeople();
  const { tap, celebration } = useHaptics();

  const [myName, setMyName] = useState('');
  const [myPronoun, setMyPronoun] = useState('they');
  const [theirName, setTheirName] = useState('');
  const [theirPronoun, setTheirPronoun] = useState('they');
  const [dismissed, setDismissed] = useState(false);
  const [error, setError] = useState('');

  if (status === 'loading' || status === 'locked' || status === 'ready') return null;

  /* ------------------------------------------------------------ which of you */

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
          {/* One colour each, so the two names never read as the same button twice. */}
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
          Pick the wrong one? Tap the other name any time in Settings.
        </p>
      </Shell>
    );
  }

  /* ------------------------------------------------------------ both names */

  if (dismissed) return null;

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
      <p className="text-xs text-slate-500 leading-relaxed mb-5">
        So this place can use your names instead of saying &ldquo;your partner&rdquo; forever.
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

        {/*
          Only reachable before anything is written. Once both names exist this
          screen never shows the form again - the other phone gets the one-tap
          version instead, because the names reach it over sync.
        */}
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
