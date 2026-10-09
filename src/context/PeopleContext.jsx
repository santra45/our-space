import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
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

function broadcast(rows) {
  for (const row of Array.isArray(rows) ? rows : [rows]) {
    if (!row) continue;
    try {
      peerSync.broadcastLiveRecord(PEOPLE_TABLE, row);
    } catch {
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

      if (next.status === 'ready') {
        const healed = await ensureDeviceClaimed({ cryptoKey, timestamp: stamp });
        if (healed) {
          broadcast(healed);
          setState(await resolveIdentity({ cryptoKey }));
        }
      }
    } catch {
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

  const myPersonIdRef = useRef(null);
  myPersonIdRef.current = state.me ? state.me.personId : null;

  const touchLastActive = useCallback(async () => {
    const personId = myPersonIdRef.current;
    if (!cryptoKey || !personId) return;
    if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return;
    try {
      const row = await touchPersonActive({ cryptoKey, personId, timestamp: stamp });
      if (row) {
        broadcast(row);
        await refresh();
      }
    } catch {
    }
  }, [cryptoKey, stamp, refresh]);

  useEffect(() => {
    if (state.status !== 'ready' || !state.me) return undefined;
    touchLastActive();

    const onVisible = () => {
      if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
        touchLastActive();
      }
    };

    const onLocalRecord = (e) => {
      if (e && e.table !== PEOPLE_TABLE) {
        touchLastActive();
      }
    };

    peerSync.on('local-record', onLocalRecord);
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', onVisible);
    }
    return () => {
      peerSync.off('local-record', onLocalRecord);
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

      myOwnerId: me ? me.personId : null,
      myOwnerIds: ownerIdsFor(me),

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
