import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import peerSync from '../services/peerSync';
import { useVault } from './VaultContext';
import { usePeople } from './PeopleContext';
import { parseInvite, PEER_ID_REGEX } from '../utils/invite';
import { fireCelebrationBurst } from '../components/common/ConfettiBurst';
import { useHaptics } from '../hooks/useHaptics';
import db from '../db';
import { getVaultKey } from '../services/vaultKey';
import {
  LOVE_BURST_TABLE,
  sendLoveBurst as writeLoveBurst,
  collectUnseenBursts,
  markBurstsSeen,
  describeBursts,
} from '../services/loveBursts';
import { isMailboxEnabled, syncMailbox } from '../services/mailbox';
import { derivePersonSlots } from '../services/people';

const SyncContext = createContext(null);

const TRUSTED_PARTNER_KEY = 'sweetheart_trusted_partner_id';
const PAIRED_PARTNER_KEY = 'sweetheart_paired_partner_id';
const PENDING_CONNECT_KEY = 'pending_partner_connect';
const LAST_CONNECTED_KEY = 'sweetheart_last_connected_at';

const AUTHORIZED_STATES = new Set(['authorized', 'syncing', 'synced']);
const ROUTE_CLEARING_STATES = new Set(['disconnected', 'error', 'auth_failed', 'ice_failed']);

const NOTICE_TTL_MS = 4000;
const WARNING_TTL_MS = 7000;

function readStored(key) {
  try {
    const value = localStorage.getItem(key);
    return value ? value.trim() : null;
  } catch {
    return null;
  }
}

function writeStored(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
  }
}

function removeStored(key) {
  try {
    localStorage.removeItem(key);
  } catch {
  }
}

export function SyncProvider({ children }) {
  const { cryptoKey, isUnlocked, vaultConfig } = useVault();
  const { partnerName, myOwnerId } = usePeople();
  const { celebration } = useHaptics();
  const [myPeerId, setMyPeerId] = useState(null);
  const [partnerId, setPartnerId] = useState(() => readStored(PAIRED_PARTNER_KEY));
  const [syncStatus, setSyncStatus] = useState({ state: 'disconnected' });
  const [lastSyncNotice, setLastSyncNotice] = useState(null);
  const [syncWarning, setSyncWarning] = useState(null);
  const [syncError, setSyncError] = useState(null);
  const [connectionType, setConnectionType] = useState(null);
  const [pendingInvite, setPendingInvite] = useState(null);
  const [lastConnectedAt, setLastConnectedAt] = useState(() => {
    const stored = readStored(LAST_CONNECTED_KEY);
    return stored ? Number(stored) : null;
  });

  const vaultConfigRef = useRef(vaultConfig);
  useEffect(() => {
    vaultConfigRef.current = vaultConfig;
  }, [vaultConfig]);

  const partnerNameRef = useRef(partnerName);
  useEffect(() => {
    partnerNameRef.current = partnerName;
  }, [partnerName]);

  const myPersonIdRef = useRef(myOwnerId);
  useEffect(() => {
    myPersonIdRef.current = myOwnerId;
  }, [myOwnerId]);

  const [mailboxState, setMailboxState] = useState({ state: 'idle', at: 0 });
  const mailboxBusyRef = useRef(false);
  const mailboxTimerRef = useRef(null);

  const runMailbox = useCallback(
    async (reason) => {
      const key = cryptoKey || getVaultKey();
      if (!key || !isMailboxEnabled()) return;
      if (mailboxBusyRef.current) return;

      mailboxBusyRef.current = true;
      setMailboxState((prev) => ({ ...prev, state: 'syncing' }));

      try {
        const slots = await derivePersonSlots(key);
        const result = await syncMailbox({
          cryptoKey: key,
          ownerId: myPersonIdRef.current,
          slots,
        });

        setMailboxState({
          state: 'ok',
          at: Date.now(),
          applied: result.applied,
          uploaded: result.uploaded,
          reason,
        });

        if (result.applied > 0) {
          setLastSyncNotice(
            `${result.applied} new thing${result.applied === 1 ? '' : 's'} from ${partnerNameRef.current} 💕`
          );
        }
      } catch {
        setMailboxState({ state: 'failed', at: Date.now(), reason });
      } finally {
        mailboxBusyRef.current = false;
      }
    },
    [cryptoKey]
  );

  const scheduleMailbox = useCallback(
    (reason, delay = 4000) => {
      if (!isMailboxEnabled()) return;
      if (mailboxTimerRef.current) clearTimeout(mailboxTimerRef.current);
      mailboxTimerRef.current = setTimeout(() => {
        mailboxTimerRef.current = null;
        runMailbox(reason);
      }, delay);
    },
    [runMailbox]
  );

  useEffect(() => {
    if (!isUnlocked || !isMailboxEnabled()) return undefined;

    scheduleMailbox('unlock', 1500);

    const onLocal = () => scheduleMailbox('local-write');
    const onVisible = () => {
      if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
        scheduleMailbox('foreground', 500);
      }
    };

    peerSync.on('local-record', onLocal);
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', onVisible);
    }

    return () => {
      peerSync.off('local-record', onLocal);
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', onVisible);
      }
      if (mailboxTimerRef.current) {
        clearTimeout(mailboxTimerRef.current);
        mailboxTimerRef.current = null;
      }
    };
  }, [isUnlocked, scheduleMailbox]);

  const dialTimerRef = useRef(null);

  const syncStatusRef = useRef(syncStatus);
  const pendingInviteRef = useRef(pendingInvite);
  const myPeerIdRef = useRef(myPeerId);
  useEffect(() => {
    syncStatusRef.current = syncStatus;
  }, [syncStatus]);
  useEffect(() => {
    pendingInviteRef.current = pendingInvite;
  }, [pendingInvite]);
  useEffect(() => {
    myPeerIdRef.current = myPeerId;
  }, [myPeerId]);

  useEffect(() => {
    if (!lastSyncNotice) return undefined;
    const timer = setTimeout(() => setLastSyncNotice(null), NOTICE_TTL_MS);
    return () => clearTimeout(timer);
  }, [lastSyncNotice]);

  useEffect(() => {
    if (!syncWarning) return undefined;
    const timer = setTimeout(() => setSyncWarning(null), WARNING_TTL_MS);
    return () => clearTimeout(timer);
  }, [syncWarning]);

  useEffect(() => {
    if (!isUnlocked || !cryptoKey) {
      peerSync.closeConnection();
      setMyPeerId(null);
      setSyncStatus({ state: 'disconnected' });
      setConnectionType(null);
      setPendingInvite(null);
      setSyncError(null);
      setSyncWarning(null);
      return;
    }

    let isMounted = true;

    const handleStatus = (status) => {
      if (!isMounted || !status) return;
      setSyncStatus(status);

      if (status.peerId) setMyPeerId(status.peerId);

      if (status.partnerId && AUTHORIZED_STATES.has(status.state)) {
        setPartnerId(status.partnerId);
        writeStored(PAIRED_PARTNER_KEY, status.partnerId);
      }

      if (status.state === 'connecting') {
        setSyncError(null);
      }

      if (AUTHORIZED_STATES.has(status.state)) {
        const now = Date.now();
        setLastConnectedAt(now);
        writeStored(LAST_CONNECTED_KEY, String(now));
        setSyncError(null);
        if (status.state === 'authorized' && vaultConfigRef.current) {
          peerSync.syncVaultConfig(vaultConfigRef.current);
        }
      }

      if (status.error) {
        setSyncError({
          code: status.code || status.state || 'error',
          state: status.state,
          text: status.error,
        });
      }

      if (status.warning) setSyncWarning({ code: status.code || 'warning', text: status.warning });
      if (status.message) setLastSyncNotice(status.message);

      if (Object.prototype.hasOwnProperty.call(status, 'connectionType')) {
        setConnectionType(status.connectionType || null);
      }
      if (ROUTE_CLEARING_STATES.has(status.state)) setConnectionType(null);
    };

    const handleDataUpdated = (data) => {
      if (!isMounted) return;
      setLastSyncNotice(`Synced ${data?.count || 1} new item(s) from ${partnerNameRef.current} 💕`);
    };

    peerSync.on('status', handleStatus);
    peerSync.on('data-updated', handleDataUpdated);

    let invitedPeerId = null;
    try {
      const pending = sessionStorage.getItem(PENDING_CONNECT_KEY);
      if (pending) {
        sessionStorage.removeItem(PENDING_CONNECT_KEY);
        invitedPeerId = pending.trim() || null;
      }
    } catch {
    }

    if (typeof window !== 'undefined' && window.location.hash) {
      const parsed = parseInvite(window.location.hash);
      if (parsed && parsed.partnerPeerId) invitedPeerId = parsed.partnerPeerId;
      try {
        history.replaceState(null, document.title, window.location.pathname + window.location.search);
      } catch {
      }
    }

    peerSync
      .init(cryptoKey)
      .then((id) => {
        if (!isMounted) return;
        setMyPeerId(id);

        const trusted = readStored(TRUSTED_PARTNER_KEY);
        const target = invitedPeerId || readStored(PAIRED_PARTNER_KEY);
        if (!target || target === id) return;

        setPartnerId(target);

        if (target === trusted) {
          dialTimerRef.current = setTimeout(() => {
            if (isMounted) peerSync.connectToPartner(target).catch(() => {});
          }, 800);
          return;
        }

        setPendingInvite({ peerId: target, fromLink: Boolean(invitedPeerId) });
      })
      .catch(() => {
      });

    return () => {
      isMounted = false;
      peerSync.off('status', handleStatus);
      peerSync.off('data-updated', handleDataUpdated);
      if (dialTimerRef.current) {
        clearTimeout(dialTimerRef.current);
        dialTimerRef.current = null;
      }
    };
  }, [isUnlocked, cryptoKey]);

  const trustAndConnect = (id) => {
    const clean = (id || '').trim();
    if (!clean) return;
    if (!PEER_ID_REGEX.test(clean) || clean === myPeerId) {
      setSyncError({
        code: 'bad_peer_id',
        state: 'error',
        text: `“${clean}” is not a usable pairing code. Ask your partner to re-share their code or invite link.`,
      });
      return;
    }
    writeStored(TRUSTED_PARTNER_KEY, clean);
    writeStored(PAIRED_PARTNER_KEY, clean);
    setPartnerId(clean);
    setSyncError(null);
    peerSync.connectToPartner(clean).catch((err) => {
      console.error('Could not start a connection to ' + clean + ':', err);
      setSyncError({
        code: 'dial_failed',
        state: 'error',
        text: `We could not reach ${clean}. Check they have Our Space open, then try again.`,
      });
    });
  };

  const connectToPartner = (id) => {
    trustAndConnect(id);
  };

  const confirmPendingInvite = () => {
    if (!pendingInvite) return;
    const target = pendingInvite.peerId;
    setPendingInvite(null);
    trustAndConnect(target);
  };

  const declinePendingInvite = () => {
    const declined = pendingInvite?.peerId;
    setPendingInvite(null);
    if (!declined) return;
    if (readStored(PAIRED_PARTNER_KEY) === declined) removeStored(PAIRED_PARTNER_KEY);
    if (readStored(TRUSTED_PARTNER_KEY) === declined) removeStored(TRUSTED_PARTNER_KEY);
    setPartnerId((current) => (current === declined ? null : current));
  };

  const reconnectToPartner = () => {
    const target = readStored(TRUSTED_PARTNER_KEY) || partnerId || readStored(PAIRED_PARTNER_KEY);
    if (!target || target === myPeerId) return;
    trustAndConnect(target);
  };

  const resumeGuardRef = useRef(0);
  useEffect(() => {
    if (!isUnlocked || !cryptoKey) return undefined;

    const RESUME_COOLDOWN_MS = 5000;

    const maybeResume = () => {
      if (document.visibilityState !== 'visible') return;
      if (!navigator.onLine) return;
      if (pendingInviteRef.current) return;
      if (AUTHORIZED_STATES.has(syncStatusRef.current.state)) return;

      const target = readStored(TRUSTED_PARTNER_KEY);
      if (!target || target === myPeerIdRef.current) return;

      const now = Date.now();
      if (now - resumeGuardRef.current < RESUME_COOLDOWN_MS) return;
      resumeGuardRef.current = now;

      peerSync.connectToPartner(target).catch(() => {
      });
    };

    document.addEventListener('visibilitychange', maybeResume);
    window.addEventListener('online', maybeResume);
    maybeResume();

    return () => {
      document.removeEventListener('visibilitychange', maybeResume);
      window.removeEventListener('online', maybeResume);
    };
  }, [isUnlocked, cryptoKey]);

  const unpairPartner = () => {
    removeStored(PAIRED_PARTNER_KEY);
    removeStored(TRUSTED_PARTNER_KEY);
    try {
      sessionStorage.removeItem(PENDING_CONNECT_KEY);
    } catch {
    }
    setPartnerId(null);
    setPendingInvite(null);
    setSyncError(null);
    setConnectionType(null);
    peerSync.disconnect();
  };

  const syncNow = () => {
    peerSync
      .syncNow()
      .then((started) => {
        if (!started) {
          setSyncWarning({
            code: 'sync_start_failed',
            text: 'Could not start a sync right now. Check the connection and try again.',
          });
        }
      })
      .catch(() => {});
  };

  const disconnect = () => {
    peerSync.disconnect();
  };

  const isAuthorized = AUTHORIZED_STATES.has(syncStatus.state);

  useEffect(() => {
    if (!isAuthorized) return undefined;
    const interval = setInterval(() => {
      const now = Date.now();
      setLastConnectedAt(now);
      writeStored(LAST_CONNECTED_KEY, String(now));
    }, 30000);
    return () => clearInterval(interval);
  }, [isAuthorized]);

  const isAuthorizedRef = useRef(isAuthorized);
  isAuthorizedRef.current = isAuthorized;

  const burstRows = useLiveQuery(
    () => (isUnlocked && cryptoKey ? db.table(LOVE_BURST_TABLE).toArray() : []),
    [isUnlocked, cryptoKey],
    []
  );

  const burstSignal = (burstRows || [])
    .map((row) => `${row.id}:${row.updatedAt}`)
    .sort()
    .join('|');

  useEffect(() => {
    if (!isUnlocked || !cryptoKey) return undefined;

    let cancelled = false;
    (async () => {
      const unseen = await collectUnseenBursts(cryptoKey);
      if (cancelled || unseen.total <= 0) return;

      markBurstsSeen(unseen.records);

      try {
        fireCelebrationBurst();
        celebration();
      } catch (err) {
        console.error('Could not play the love burst:', err);
      }

      setLastSyncNotice(describeBursts(unseen.total, isAuthorizedRef.current, partnerNameRef.current));
    })();

    return () => {
      cancelled = true;
    };
  }, [isUnlocked, cryptoKey, burstSignal]);

  const clearSyncError = () => setSyncError(null);
  const clearSyncWarning = () => setSyncWarning(null);

  const sendLoveBurst = async () => {
    if (!cryptoKey) {
      setLastSyncNotice('Unlock Our Space first 💕');
      return false;
    }

    let row;
    try {
      row = await writeLoveBurst(cryptoKey);
    } catch {
      setLastSyncNotice('Could not send that just now 💕');
      return false;
    }

    if (isAuthorized) {
      peerSync.broadcastLiveRecord(LOVE_BURST_TABLE, row);
      setLastSyncNotice(`Love burst sent to ${partnerName}! 💕`);
    } else {
      setLastSyncNotice(`Saved 💕 ${partnerName} will see it the moment you two connect.`);
    }
    return true;
  };

  return (
    <SyncContext.Provider
      value={{
        myPeerId,
        partnerId,
        syncStatus,
        lastSyncNotice,
        syncWarning,
        syncError,
        clearSyncError,
        clearSyncWarning,
        connectToPartner,
        reconnectToPartner,
        unpairPartner,
        syncNow,
        sendLoveBurst,
        disconnect,
        pendingInvite,
        confirmPendingInvite,
        declinePendingInvite,
        connectionType,
        isAuthorized,
        isHandshaking: syncStatus.state === 'handshaking',
        isConnecting: syncStatus.state === 'connecting',
        isDirectP2P: connectionType === 'direct',
        isRelayed: connectionType === 'relayed',
        isRouteUnknown: isAuthorized && connectionType !== 'direct' && connectionType !== 'relayed',

        mailboxEnabled: isMailboxEnabled(),
        mailboxState,
        syncMailboxNow: () => runMailbox('manual'),

        lastConnectedAt,
      }}
    >
      {children}
    </SyncContext.Provider>
  );
}

export function useSync() {
  const context = useContext(SyncContext);
  if (!context) throw new Error('useSync must be used within SyncProvider');
  return context;
}

export default SyncContext;
