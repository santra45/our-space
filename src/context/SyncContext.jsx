/**
 * src/context/SyncContext.jsx
 * Bridges the peerSync SWEETHEART_V2 status contract to React state.
 *
 * Two rules this file exists to enforce:
 *  1. ONLY an authenticated peer counts as "connected". peerSync emits
 *     `handshaking` for a channel that has opened but not proved it holds the
 *     vault key, and anyone who knows our peer id can reach that state. No
 *     security indicator may be derived from it.
 *  2. A peer id that arrived through a link is NOT consent to dial it. Dialling
 *     runs ICE, which hands the far side our local and public IP addresses, so
 *     an unrecognised peer waits behind an explicit confirmation.
 */
import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import peerSync from '../services/peerSync';
import { useVault } from './VaultContext';
import { parseInvite, PEER_ID_REGEX } from '../utils/invite';
import { fireCelebrationBurst } from '../components/common/ConfettiBurst';
import { useHaptics } from '../hooks/useHaptics';
import db from '../db';
import {
  LOVE_BURST_TABLE,
  sendLoveBurst as writeLoveBurst,
  collectUnseenBursts,
  markBurstsSeen,
  describeBursts,
} from '../services/loveBursts';

const SyncContext = createContext(null);

/** Peer we have dialled at least once and are willing to re-dial silently. */
const TRUSTED_PARTNER_KEY = 'sweetheart_trusted_partner_id';
/** Last peer id we saw, trusted or not. Used to prefill the confirmation. */
const PAIRED_PARTNER_KEY = 'sweetheart_paired_partner_id';
/** Handoff slot written by LockScreen when the user unlocked through an invite. */
const PENDING_CONNECT_KEY = 'pending_partner_connect';

/** Lifecycle states in which the peer has proved it holds the vault key. */
const AUTHORIZED_STATES = new Set(['authorized', 'syncing', 'synced']);
/** Lifecycle states that must clear a stale route reading. */
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
    // Private window / storage blocked. Pairing still works this session.
  }
}

function removeStored(key) {
  try {
    localStorage.removeItem(key);
  } catch {
    // ignore
  }
}

export function SyncProvider({ children }) {
  const { cryptoKey, isUnlocked, vaultConfig } = useVault();
  const { celebration } = useHaptics();
  const [myPeerId, setMyPeerId] = useState(null);
  const [partnerId, setPartnerId] = useState(() => readStored(PAIRED_PARTNER_KEY));
  const [syncStatus, setSyncStatus] = useState({ state: 'disconnected' });
  const [lastSyncNotice, setLastSyncNotice] = useState(null);
  const [syncWarning, setSyncWarning] = useState(null);
  const [syncError, setSyncError] = useState(null);
  const [connectionType, setConnectionType] = useState(null); // 'direct' | 'relayed' | 'unknown' | null
  const [pendingInvite, setPendingInvite] = useState(null);

  // Keep latest vaultConfig accessible to sync handlers without triggering effect re-runs
  const vaultConfigRef = useRef(vaultConfig);
  useEffect(() => {
    vaultConfigRef.current = vaultConfig;
  }, [vaultConfig]);

  const dialTimerRef = useRef(null);

  // The resume listeners below are registered once per unlock, so they must not
  // close over render-time values. These refs give them the current ones.
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

  // Transient banners expire on their own. Owning the timer here rather than at
  // each call site means a notice raised outside the peer effect (a failed
  // manual sync, say) cannot get stuck on screen forever.
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

  // Initialize peer when vault is unlocked
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

    /**
     * peerSync status contract:
     *  - `state` is the lifecycle and the only thing indicators may key off.
     *  - `warning` is a NON-fatal problem carried alongside the CURRENT state.
     *  - `error` is a fatal problem, on `auth_failed` / `ice_failed` / `error`.
     *  - `code` is stable and machine readable; `message` is only sync progress.
     */
    const handleStatus = (status) => {
      if (!isMounted || !status) return;
      setSyncStatus(status);

      if (status.peerId) setMyPeerId(status.peerId);

      // ONLY once the peer has proved it holds the vault key.
      //
      // peerSync emits `partnerId` from `channel_open`, which fires the moment a
      // WebRTC data channel opens - before the challenge/response proves
      // anything. Persisting it there meant any stranger or bot that probed this
      // peer id on the public broker immediately overwrote both the React state
      // and PAIRED_PARTNER_KEY with their own id. Their handshake then failed,
      // the user saw "connection lost", tapped Reconnect - and reconnect dials
      // `partnerId` and routes it through trustAndConnect(), which writes
      // TRUSTED_PARTNER_KEY. So one unauthenticated probe plus one innocent tap
      // permanently promoted a stranger, destroyed the real partner's stored id,
      // and made this device dial the stranger over ICE, disclosing its local
      // and public IP.
      //
      // The unproven id is still on `syncStatus.partnerId` for any UI that wants
      // to show who is dialling; it just never becomes "our partner", never
      // reaches storage, and can never be what a reconnect dials.
      if (status.partnerId && AUTHORIZED_STATES.has(status.state)) {
        setPartnerId(status.partnerId);
        writeStored(PAIRED_PARTNER_KEY, status.partnerId);
      }

      if (status.state === 'connecting') {
        // A new attempt supersedes whatever went wrong last time.
        setSyncError(null);
      }

      if (AUTHORIZED_STATES.has(status.state)) {
        setSyncError(null);
        if (status.state === 'authorized' && vaultConfigRef.current) {
          peerSync.syncVaultConfig(vaultConfigRef.current);
        }
      }

      // X4: fatal problems used to be dropped on the floor. They are the only
      // way the user ever learns their passphrases do not match.
      if (status.error) {
        setSyncError({
          code: status.code || status.state || 'error',
          state: status.state,
          text: status.error,
        });
      }

      if (status.warning) setSyncWarning({ code: status.code || 'warning', text: status.warning });
      if (status.message) setLastSyncNotice(status.message);

      // X3: 'unknown' is a real value now and must survive to the UI verbatim.
      if (Object.prototype.hasOwnProperty.call(status, 'connectionType')) {
        setConnectionType(status.connectionType || null);
      }
      if (ROUTE_CLEARING_STATES.has(status.state)) setConnectionType(null);
    };

    const handleDataUpdated = (data) => {
      if (!isMounted) return;
      setLastSyncNotice(`Synced ${data?.count || 1} new item(s) from partner 💕`);
    };

    peerSync.on('status', handleStatus);
    peerSync.on('data-updated', handleDataUpdated);

    // Read any pairing intent that arrived through a link BEFORE dialling
    // anything, and scrub the peer id out of the address bar either way.
    let invitedPeerId = null;
    try {
      const pending = sessionStorage.getItem(PENDING_CONNECT_KEY);
      if (pending) {
        sessionStorage.removeItem(PENDING_CONNECT_KEY);
        invitedPeerId = pending.trim() || null;
      }
    } catch {
      // ignore
    }

    if (typeof window !== 'undefined' && window.location.hash) {
      const parsed = parseInvite(window.location.hash);
      if (parsed && parsed.partnerPeerId) invitedPeerId = parsed.partnerPeerId;
      try {
        history.replaceState(null, document.title, window.location.pathname + window.location.search);
      } catch {
        // ignore
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
          // Already confirmed on this device. Silently re-dialling the partner
          // we deliberately paired with is the entire point of pairing.
          dialTimerRef.current = setTimeout(() => {
            if (isMounted) peerSync.connectToPartner(target).catch(() => {});
          }, 800);
          return;
        }

        // X6: unrecognised peer id. Do not dial, do not leak ICE candidates.
        setPendingInvite({ peerId: target, fromLink: Boolean(invitedPeerId) });
      })
      .catch(() => {
        // init failures already surface through the status listener
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

  /** Marks a peer as deliberately chosen by the user, then dials it. */
  const trustAndConnect = (id) => {
    const clean = (id || '').trim();
    if (!clean) return;
    // Validate before storing: a malformed id written to the trusted slot would
    // be silently re-dialled on every launch and fail every time.
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

  /**
   * Manual pairing from the hub (typed id, pasted link, scanned QR). The user
   * performed the action in-app, so it is its own confirmation.
   */
  const connectToPartner = (id) => {
    trustAndConnect(id);
  };

  /** X6: the user explicitly accepted the IP disclosure for a link invite. */
  const confirmPendingInvite = () => {
    if (!pendingInvite) return;
    const target = pendingInvite.peerId;
    setPendingInvite(null);
    trustAndConnect(target);
  };

  /**
   * Declining must also forget the peer id, otherwise the next launch would dial
   * it from storage and defeat the confirmation entirely.
   */
  const declinePendingInvite = () => {
    const declined = pendingInvite?.peerId;
    setPendingInvite(null);
    if (!declined) return;
    if (readStored(PAIRED_PARTNER_KEY) === declined) removeStored(PAIRED_PARTNER_KEY);
    if (readStored(TRUSTED_PARTNER_KEY) === declined) removeStored(TRUSTED_PARTNER_KEY);
    setPartnerId((current) => (current === declined ? null : current));
  };

  const reconnectToPartner = () => {
    // Trusted slot first. That one is only ever written by an explicit user
    // action (trustAndConnect), whereas PAIRED_PARTNER_KEY tracks whoever we
    // last authenticated with - so preferring it keeps a reconnect aimed at the
    // partner the user actually chose, even if something else got in between.
    const target = readStored(TRUSTED_PARTNER_KEY) || partnerId || readStored(PAIRED_PARTNER_KEY);
    if (!target || target === myPeerId) return;
    trustAndConnect(target);
  };

  /**
   * Re-dial the trusted partner when the phone comes back.
   *
   * peerSync already listens for `visibilitychange`, but all it does there is
   * `peer.reconnect()` - which reconnects this client to the PeerJS signalling
   * server and nothing else. It does NOT re-establish the data channel to the
   * partner. Mobile browsers tear that channel down while the screen is locked
   * or the tab is backgrounded, so coming back left the connection dead until
   * the user noticed and tapped Reconnect by hand. Nothing on screen said it had
   * to be tapped, so in practice the two phones just quietly stopped syncing.
   *
   * Guards, because this fires on every unlock and every network flap:
   *  - vault locked -> there is no key to authenticate with
   *  - already authorized -> connectToPartner would return anyway, but not
   *    calling it at all keeps a healthy session entirely untouched
   *  - a pending invite -> that peer has not been confirmed by the user yet, and
   *    auto-dialling it would defeat the confirmation
   *  - only the TRUSTED slot is dialled, never the paired one, so a stranger who
   *    got as far as opening a channel can never be re-dialled automatically
   *  - a cooldown, so a flapping network cannot produce a dial storm and trip
   *    the partner's own admission backoff
   */
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
        // Offline, partner asleep, or signalling not back yet. The next
        // visibility change or `online` event tries again.
      });
    };

    document.addEventListener('visibilitychange', maybeResume);
    window.addEventListener('online', maybeResume);
    // Also try once now: the effect can mount just after a resume, with no
    // further event coming.
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
      // ignore
    }
    setPartnerId(null);
    setPendingInvite(null);
    setSyncError(null);
    setConnectionType(null);
    peerSync.disconnect();
  };

  /** peerSync.syncNow() resolves false instead of rejecting; report that. */
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

  // Read by the burst watcher to pick its wording. A ref rather than a
  // dependency: connecting must not re-run the watcher and replay a burst.
  const isAuthorizedRef = useRef(isAuthorized);
  isAuthorizedRef.current = isAuthorized;

  /**
   * Watches the burst tallies and celebrates anything not celebrated yet.
   *
   * ONE PATH FOR BOTH CASES, on purpose. A burst that arrives while she has
   * the app open lands here as a live-record broadcast; one sent while her
   * phone was off lands here through the ordinary manifest diff on the next
   * connection. Either way it is a row changing, this fires, and she finds out.
   * The previous version listened for a wire message instead, so anything sent
   * to a phone that was not listening was simply gone.
   *
   * It runs on unlock too, which is what makes "while you were away" work: the
   * rows are already on disk by then, waiting to be counted.
   */
  const burstRows = useLiveQuery(
    () => (isUnlocked && cryptoKey ? db.table(LOVE_BURST_TABLE).toArray() : []),
    [isUnlocked, cryptoKey],
    []
  );

  // A cheap change signal. Both fields are plaintext by design, so noticing a
  // change costs no decryption - only actually counting does.
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

      // Mark BEFORE celebrating. If the confetti throws, or the tab is closed
      // mid-animation, the alternative is replaying the same burst on every
      // launch forever.
      markBurstsSeen(unseen.records);

      try {
        fireCelebrationBurst();
        celebration();
      } catch (err) {
        console.error('Could not play the love burst:', err);
      }

      setLastSyncNotice(describeBursts(unseen.total, isAuthorizedRef.current));
    })();

    return () => {
      cancelled = true;
    };
    // celebration is a stable haptics helper; including it would re-run this on
    // every render and re-fire the confetti.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isUnlocked, cryptoKey, burstSignal]);

  const clearSyncError = () => setSyncError(null);
  const clearSyncWarning = () => setSyncWarning(null);

  /**
   * Sends a love burst, connected or not.
   *
   * This used to refuse outright when the partner was offline, which is
   * precisely the moment you most want to tell someone you were thinking of
   * them. It is a record now: writing it is the send, and the broadcast below
   * is only a shortcut for when she happens to be listening. If she is not,
   * the next manifest diff carries it over with everything else.
   */
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
      setLastSyncNotice('Love burst sent to partner! 💕');
    } else {
      setLastSyncNotice('Saved 💕 She will see it the moment you two connect.');
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
        // X2: `isAuthorized` is the ONLY connection flag exposed. The old
        // `isPartnerConnected` also matched the pre-auth state, which is how a
        // stranger rendered as a secure partner.
        isAuthorized,
        isHandshaking: syncStatus.state === 'handshaking',
        isConnecting: syncStatus.state === 'connecting',
        // X3: only an actually-observed direct route may claim to be direct.
        isDirectP2P: connectionType === 'direct',
        isRelayed: connectionType === 'relayed',
        isRouteUnknown: isAuthorized && connectionType !== 'direct' && connectionType !== 'relayed',
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
