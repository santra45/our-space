/**
 * src/context/PeopleContext.jsx
 * Who is holding this phone, and who the other one is, for every screen.
 *
 * WHY A CONTEXT AND NOT A HOOK PER SCREEN
 * Because the answer has to be the SAME answer everywhere. Three screens each
 * resolving identity for themselves is three chances to disagree about whose
 * answer an answer is, and the whole point of services/people.js is that the
 * question has exactly one answer.
 *
 * IT FOLLOWS SYNC
 * A person record arrives like any other record, so `me` and `partner` can
 * change under a screen that is already open - most visibly on the phone that
 * did NOT do the setup, where "which one are you?" appears the moment the
 * partner's records land. Listening to `data-updated` is what makes that feel
 * like the app noticing rather than something the user has to go and find.
 */
import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { useVault } from './VaultContext';
import peerSync from '../services/peerSync';
import {
  PEOPLE_TABLE,
  claimPerson as claimPersonRecord,
  createCouple as createCoupleRecords,
  ensureDeviceClaimed,
  grammarOf,
  nameOf,
  ownerIdsFor,
  possessiveOf,
  resolveIdentity,
  savePerson as savePersonRecord,
  touchPersonActive,
} from '../services/people';

const PeopleContext = createContext(null);

/** Hands a row to the partner if they happen to be listening. Never throws. */
function broadcast(rows) {
  for (const row of Array.isArray(rows) ? rows : [rows]) {
    if (!row) continue;
    try {
      peerSync.broadcastLiveRecord(PEOPLE_TABLE, row);
    } catch {
      // Not connected. The record is written and the next manifest sync
      // carries it, which is the ordinary case rather than a failure.
    }
  }
}

export function PeopleProvider({ children }) {
  const { cryptoKey } = useVault();

  const [state, setState] = useState({ status: 'loading', people: [], me: null, partner: null });
  const [busy, setBusy] = useState(false);

  const stamp = useCallback(() => {
    try {
      return peerSync.getSyncSafeTimestamp();
    } catch {
      return Date.now();
    }
  }, []);

  const refresh = useCallback(async () => {
    if (!cryptoKey) {
      setState({ status: 'locked', people: [], me: null, partner: null });
      return;
    }
    try {
      const next = await resolveIdentity({ cryptoKey });
      setState(next);

      // Self-healing, and deliberately after the state is already set so it
      // never delays a render: two devices belonging to one person can knock
      // each other's tag off the record, and this puts ours back.
      if (next.status === 'ready') {
        const healed = await ensureDeviceClaimed({ cryptoKey, timestamp: stamp });
        if (healed) {
          broadcast(healed);
          setState(await resolveIdentity({ cryptoKey }));
        }
      }
    } catch {
      // A screen that cannot read the people table is not an emergency. It
      // falls back to neutral copy, which is what the app said before people
      // existed at all.
      setState({ status: 'empty', people: [], me: null, partner: null });
    }
  }, [cryptoKey, stamp]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    const onUpdate = () => refresh();
    peerSync.on('data-updated', onUpdate);
    return () => peerSync.off('data-updated', onUpdate);
  }, [refresh]);

  const createCouple = useCallback(
    async (mine, theirs) => {
      if (!cryptoKey || busy) return false;
      setBusy(true);
      try {
        const result = await createCoupleRecords({ cryptoKey, mine, theirs, timestamp: stamp });
        broadcast(result.rows);
        await refresh();
        return true;
      } catch {
        return false;
      } finally {
        setBusy(false);
      }
    },
    [cryptoKey, busy, refresh, stamp]
  );

  const claimPerson = useCallback(
    async (personId) => {
      if (!cryptoKey || busy) return false;
      setBusy(true);
      try {
        broadcast(await claimPersonRecord({ cryptoKey, personId, timestamp: stamp }));
        await refresh();
        return true;
      } catch {
        return false;
      } finally {
        setBusy(false);
      }
    },
    [cryptoKey, busy, refresh, stamp]
  );

  const savePerson = useCallback(
    async (personId, fields) => {
      if (!cryptoKey || busy) return false;
      setBusy(true);
      try {
        broadcast(await savePersonRecord({ cryptoKey, personId, ...fields, timestamp: stamp }));
        await refresh();
        return true;
      } catch {
        return false;
      } finally {
        setBusy(false);
      }
    },
    [cryptoKey, busy, refresh, stamp]
  );

  const touchLastActive = useCallback(async () => {
    if (!cryptoKey || !state.me) return;
    try {
      const row = await touchPersonActive({
        cryptoKey,
        personId: state.me.personId,
        timestamp: stamp,
      });
      if (row) {
        broadcast(row);
        await refresh();
      }
    } catch {
      // Non-fatal
    }
  }, [cryptoKey, state.me, stamp, refresh]);

  // Touch active on unlock and whenever returning to foreground
  useEffect(() => {
    if (state.status !== 'ready' || !state.me) return undefined;
    touchLastActive();

    const onVisible = () => {
      if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
        touchLastActive();
      }
    };
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', onVisible);
    }
    return () => {
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', onVisible);
      }
    };
  }, [state.status, state.me?.personId, touchLastActive]);

  const value = useMemo(() => {
    const { status, people, me, partner } = state;
    return {
      status,
      people,
      me,
      partner,
      busy,

      /** The id answers are WRITTEN under. Falls back to nothing when unknown. */
      myOwnerId: me ? me.personId : null,
      /** Everything that counts as mine, including tags from before people. */
      myOwnerIds: ownerIdsFor(me),

      /** Copy helpers, so no screen hardcodes a name or guesses a verb. */
      myName: nameOf(me, 'you'),
      partnerName: nameOf(partner),
      partnerPossessive: possessiveOf(partner),
      partnerGrammar: grammarOf(partner),
      partnerLastActive: partner?.lastActiveAt || null,

      refresh,
      createCouple,
      claimPerson,
      savePerson,
      touchLastActive,
    };
  }, [state, busy, refresh, createCouple, claimPerson, savePerson, touchLastActive]);

  return <PeopleContext.Provider value={value}>{children}</PeopleContext.Provider>;
}

export function usePeople() {
  const ctx = useContext(PeopleContext);
  if (!ctx) throw new Error('usePeople must be used inside a PeopleProvider');
  return ctx;
}

export default PeopleContext;
