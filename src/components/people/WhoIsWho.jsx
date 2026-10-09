import React, { useState } from 'react';
import { UserRound, Check, Pencil } from 'lucide-react';
import { usePeople } from '../../context/PeopleContext';
import { MAX_NAME_LENGTH, PRONOUNS } from '../../services/people';
import { tradedPlacesAt } from '../../services/peopleRepair';
import { useHaptics } from '../../hooks/useHaptics';

const PRONOUN_LABELS = {
  she: 'she / her',
  he: 'he / him',
  they: 'they / them',
};

function formatMoment(ms) {
  try {
    return new Date(ms).toLocaleString(undefined, {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      hour: 'numeric',
      minute: '2-digit',
    });
  } catch {
    return new Date(ms).toString();
  }
}

export function WhoIsWho() {
  const { status, people, me, partner, busy, savePerson, claimPerson, swapUsBack } = usePeople();
  const { tap, celebration } = useHaptics();

  const [editing, setEditing] = useState(null);
  const [name, setName] = useState('');
  const [pronoun, setPronoun] = useState('they');
  const [confirmClaim, setConfirmClaim] = useState(null);
  const [swapOpen, setSwapOpen] = useState(false);
  const [swapNote, setSwapNote] = useState('');

  if (status !== 'ready' || !me) return null;

  const startEdit = (person) => {
    tap();
    setEditing(person.personId);
    setName(person.name || '');
    setPronoun(person.pronoun || 'they');
  };

  const commit = async () => {
    await savePerson(editing, { name, pronoun });
    setEditing(null);
  };

  const row = (person, isMe) => {
    if (editing === person.personId) {
      return (
        <div key={person.personId} className="p-2.5 rounded-2xl bg-white border border-lavender-200">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={MAX_NAME_LENGTH}
            autoFocus
            placeholder={isMe ? 'Your name' : 'Their name'}
            className="w-full px-3 py-2 bg-white border border-lavender-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-lavender-300 placeholder:text-slate-400"
          />
          <div className="flex gap-1.5 mt-2">
            {PRONOUNS.map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPronoun(p)}
                className={`flex-1 py-1 rounded-lg text-[10px] font-bold transition-colors ${
                  pronoun === p
                    ? 'bg-lavender-500 text-white'
                    : 'bg-lavender-50 text-lavender-600 hover:bg-lavender-100'
                }`}
              >
                {PRONOUN_LABELS[p]}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-3 mt-2.5">
            <button
              type="button"
              disabled={busy || !name.trim()}
              onClick={commit}
              className="text-[11px] font-bold text-emerald-700 inline-flex items-center gap-1 disabled:opacity-40"
            >
              <Check className="w-3 h-3" />
              <span>Save</span>
            </button>
            <button
              type="button"
              onClick={() => {
                tap();
                setEditing(null);
              }}
              className="text-[11px] font-bold text-slate-400"
            >
              Cancel
            </button>
          </div>
        </div>
      );
    }

    return (
      <div
        key={person.personId}
        className="flex items-center justify-between gap-2 p-2.5 rounded-2xl bg-white border border-slate-200/70"
      >
        <div className="flex items-center gap-2 min-w-0">
          <UserRound
            className={`w-3.5 h-3.5 shrink-0 ${isMe ? 'text-blush-400' : 'text-lavender-400'}`}
          />
          <span className="text-xs font-bold text-slate-700 truncate">
            {person.name || 'No name yet'}
          </span>
          {isMe && (
            <span className="text-[9px] font-bold text-blush-600 bg-blush-50 px-1.5 py-0.5 rounded-full border border-blush-100 shrink-0">
              this phone
            </span>
          )}
          <span className="text-[10px] text-slate-400 shrink-0">
            {PRONOUN_LABELS[person.pronoun] || PRONOUN_LABELS.they}
          </span>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          {!isMe && (
            <button
              type="button"
              disabled={busy}
              onClick={() => {
                tap();
                setSwapOpen(false);
                setConfirmClaim(person.personId);
              }}
              className="text-[10px] font-bold text-lavender-600 underline disabled:opacity-40"
            >
              I&apos;m this one
            </button>
          )}
          <button
            type="button"
            onClick={() => startEdit(person)}
            className="w-6 h-6 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
            aria-label={`Edit ${person.name || 'this person'}`}
          >
            <Pencil className="w-3 h-3" />
          </button>
        </div>
      </div>
    );
  };

  return (
    <div className="mb-4 p-3.5 rounded-2xl bg-slate-50 border border-slate-200/70">
      <p className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-2">
        Who is who
      </p>

      <div className="space-y-2">
        {row(me, true)}
        {partner && row(partner, false)}
      </div>

      {partner && confirmClaim === partner.personId && (
        <div className="mt-2 p-3 rounded-2xl bg-amber-50 border border-amber-200 text-[11px] text-amber-900 leading-relaxed">
          <p className="font-bold">Make this phone {partner.name || 'the other one'}?</p>
          <p className="mt-1">
            Answers already written on this phone stay with {me.name || 'you'}. If your names just
            look swapped, use &ldquo;Swap us back&rdquo; below instead.
          </p>
          <div className="flex items-center gap-3 mt-2">
            <button
              type="button"
              disabled={busy}
              onClick={async () => {
                tap();
                if (await claimPerson(confirmClaim)) setConfirmClaim(null);
              }}
              className="text-[11px] font-bold text-amber-800 underline disabled:opacity-40"
            >
              Yes, I&apos;m {partner.name || 'this one'}
            </button>
            <button
              type="button"
              onClick={() => {
                tap();
                setConfirmClaim(null);
              }}
              className="text-[11px] font-bold text-slate-400"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {partner && people.length === 2 && !swapOpen && (
        <button
          type="button"
          onClick={() => {
            tap();
            setConfirmClaim(null);
            setSwapNote('');
            setSwapOpen(true);
          }}
          className="mt-2 text-[10px] font-bold text-slate-400 underline"
        >
          Names or answers look swapped?
        </button>
      )}

      {partner && people.length === 2 && swapOpen && (
        <div className="mt-2 p-3 rounded-2xl bg-lavender-50 border border-lavender-200 text-[11px] text-slate-700 leading-relaxed">
          <p className="font-bold text-lavender-700">Swap us back?</p>
          <p className="mt-1">
            {me.name || 'You'} and {partner.name || 'your partner'} trade places, along with which
            phone is whose.
            {tradedPlacesAt(people)
              ? ` Answers written since ${formatMoment(tradedPlacesAt(people))} move with them.`
              : ''}{' '}
            Do this on one phone only. The other one follows by itself the next time it syncs.
          </p>
          <div className="flex items-center gap-3 mt-2">
            <button
              type="button"
              disabled={busy}
              onClick={async () => {
                tap();
                if (await swapUsBack()) {
                  celebration();
                  setSwapOpen(false);
                  setSwapNote('Swapped back. Your answers are where they belong again 💕');
                } else {
                  setSwapNote('That did not work, and nothing was changed. Try again in a moment.');
                }
              }}
              className="text-[11px] font-bold text-lavender-700 underline disabled:opacity-40"
            >
              Swap us back
            </button>
            <button
              type="button"
              onClick={() => {
                tap();
                setSwapOpen(false);
              }}
              className="text-[11px] font-bold text-slate-400"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {swapNote && (
        <p role="status" className="mt-2 text-[11px] font-semibold text-slate-600">
          {swapNote}
        </p>
      )}

      <p className="text-[10px] text-slate-400 leading-relaxed mt-2">
        {people.length > 2
          ? 'More than two people are in here, which should not happen. Pick yourself and tell the other phone to do the same.'
          : 'Names are sealed in your vault like everything else, and only ever appear on your two phones.'}
      </p>
    </div>
  );
}

export default WhoIsWho;
