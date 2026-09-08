/**
 * src/services/peerSync.js
 * Security-Hardened P2P WebRTC Data Replication Manager using PeerJS
 *
 * PROTOCOL: SWEETHEART_V2
 * Every frame on the wire is `{ protocol: 'SWEETHEART_V2', payload: { ciphertext, iv } }`
 * where the payload is the AES-GCM encryption of a JSON message under the shared
 * vault key. A peer that cannot produce a valid frame cannot say anything at all.
 *
 * WHAT CHANGED FROM V1 (and why)
 *  - Replication is BIDIRECTIONAL. Both peers advertise a manifest on authorization,
 *    so records that exist only on the answering side are no longer stranded.
 *  - Every sync exchange is a SESSION with an explicit `sessionId`, an explicit
 *    SYNC_COMPLETE terminator and a timeout. Neither side can hang in `syncing`.
 *  - SYNC_RECORDS_BATCH is CHUNKED and sequenced. A record that cannot fit in a
 *    single frame is reported through SYNC_ERROR instead of vanishing.
 *  - Every write path compares `updatedAt` against the local row and refuses stale
 *    data, with a deterministic tie-break so both devices converge on the same
 *    winner rather than flip-flopping.
 *  - Insane timestamps (NaN, Infinity, far-future) are rejected outright, so a
 *    device with a broken clock cannot pin a record as "newest" forever.
 *  - A decrypt failure BEFORE authentication means a passphrase mismatch and kills
 *    the session. A decrypt failure AFTER authentication is one bad frame: it is
 *    counted and dropped, and only a sustained run tears the session down.
 *  - checkConnectionType() reports 'unknown' when it does not know, instead of
 *    asserting 'direct'. There is no TURN server, so a route that never nominates
 *    a candidate pair surfaces as an actionable ICE failure.
 *
 * STATUS EVENT CONTRACT
 * `emit('status', { state, code, ... })`. `state` is the connection lifecycle and
 * is the ONLY thing UI should use to decide "are we connected". Non-fatal problems
 * are emitted as WARNINGS: they carry the CURRENT state plus a `warning` string, so
 * surfacing a problem never makes a live connection look dead.
 *
 * The relative imports below spell out `.js` on purpose: Vite does not need it,
 * plain Node does, and `node test-crypto.mjs` loads this module to check that the
 * backup merge really uses _incomingWins rather than a second copy of the rule.
 */
import Peer from 'peerjs';
import {
  encryptJSON,
  decryptJSON,
  generateSecureNonce,
  bufferToBase64,
  base64ToBuffer,
  decryptRecord,
  recordCarriesAuthenticatedPayload,
  recordHasAuthenticatedHeader,
} from './crypto.js';
import { PEER_ID_REGEX } from '../utils/invite.js';
import db, { SYNCED_TABLES, MAX_IMAGE_BLOB_BYTES, MAX_RECORDS_PER_TABLE } from '../db/index.js';

/* ------------------------------------------------------------------------- *
 * Protocol constants
 * ------------------------------------------------------------------------- */

const PROTOCOL_ID = 'SWEETHEART_V2';
const LEGACY_PROTOCOL_ID = 'SWEETHEART_V1';

/** Hard ceiling on an inbound ciphertext string. Anything larger is hostile or broken. */
const MAX_CIPHERTEXT_LENGTH = 30 * 1024 * 1024;

/**
 * Budget for ONE outbound SYNC_RECORDS_BATCH, measured on the serialized record
 * payload before encryption. Base64 + AES-GCM inflates roughly 1.34x, so 8MB of
 * records lands near 11MB of ciphertext - comfortably under the 30MB inbound cap
 * with room for a partner running slightly different limits.
 */
const MAX_BATCH_PAYLOAD_BYTES = 8 * 1024 * 1024;

/**
 * Ceiling on a SINGLE record. A record over this can never be framed, so it is
 * reported to both sides rather than silently dropped forever.
 */
const MAX_SINGLE_RECORD_BYTES = 16 * 1024 * 1024;

const AUTH_TIMEOUT_MS = 30000;
const CONNECT_OPEN_TIMEOUT_MS = 15000;

/**
 * A peer we have NEVER authenticated with gets a much shorter leash than a peer
 * we know. Our peer id is permanent and is announced to a public broker on every
 * launch, so anyone who has ever seen it can dial us forever. Giving a stranger
 * the same 15s/30s squat window as a real partner is what let a reconnect loop
 * hold the single pairing slot indefinitely.
 */
const UNKNOWN_CONNECT_OPEN_TIMEOUT_MS = 8000;
const UNKNOWN_AUTH_TIMEOUT_MS = 12000;

/**
 * How long an unknown, unauthenticated incumbent may hold the slot before a new
 * arrival is allowed to evict it. A real peer sends its first protocol frame
 * within about one round trip, so anything still silent after this has proved
 * nothing and is not worth protecting.
 */
const STRANGER_EVICT_AFTER_MS = 3000;

/**
 * Per-peer-id admission backoff. A cooldown is armed the moment a peer is let
 * in and only cleared when it actually authenticates, so a loop of failed
 * attempts throttles itself: 2s, 4s, 8s ... up to 5 minutes.
 */
const ADMISSION_BACKOFF_BASE_MS = 2000;
const ADMISSION_BACKOFF_MAX_MS = 5 * 60 * 1000;
/** A known partner on a flaky network may retry this often before any backoff. */
const KNOWN_PEER_FREE_ATTEMPTS = 3;
const KNOWN_PEER_BACKOFF_MAX_MS = 15000;
/** Admission records older than this are forgotten, so a bad night is not permanent. */
const ADMISSION_ENTRY_TTL_MS = 30 * 60 * 1000;
/** Hard cap on the admission table so a peer-id-rotating flood cannot grow it without bound. */
const ADMISSION_MAX_TRACKED_PEERS = 128;
/**
 * Global circuit breaker. Past this many unknown inbound admissions in a window
 * we are plainly under a flood, and we refuse ALL unknown inbound connections
 * until it subsides. The known partner keeps getting in, and dialling OUT is
 * unaffected, so the user can still pair deliberately. Safety over convenience:
 * refusing strangers is recoverable, a permanently squatted slot is not.
 */
const ADMISSION_FLOOD_WINDOW_MS = 60000;
const ADMISSION_FLOOD_MAX_UNKNOWN = 6;
/** Strangers must not be able to spam the user with toasts, so refusals are throttled. */
const ADMISSION_WARN_INTERVAL_MS = 30000;

const HEARTBEAT_INTERVAL_MS = 15000;
const HEARTBEAT_TIMEOUT_MS = 50000;
const SYNC_SESSION_TIMEOUT_MS = 120000;

/** How far ahead of our own clock a partner's timestamp may be before we distrust it. */
const MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

const MAX_DECRYPT_FAILURES = 5;
const MAX_REQUESTS_PER_SESSION = 5000;
const MAX_CONCURRENT_SESSIONS = 4;
const MAX_COUPLE_NAMES_LENGTH = 120;

const ROUTE_PROBE_INTERVAL_MS = 1500;
const ROUTE_PROBE_MAX_ATTEMPTS = 12;

const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

/**
 * There is deliberately no TURN server in this app (a relay would see the
 * ciphertext volume and both IPs, and would need to be paid for and trusted), so
 * a route that never establishes is a real dead end the user has to act on.
 */
const ICE_FAILURE_MESSAGE =
  'Could not open a direct connection to your partner. This app uses no relay server, so a strict mobile network (CGNAT) on either side can block pairing. Try putting both devices on the same Wi-Fi, or switch one device to a different network.';

const LOCAL_PEER_ID_KEY = 'sweetheart_device_peer_id';
const SYNC_CLOCK_KEY = 'sweetheart_sync_clock';
/**
 * The last peer id that actually completed the challenge-response. Admission
 * control needs to tell "my partner reconnecting after a tunnel" apart from "a
 * stranger looping on my public peer id", and only a proven id can do that.
 * SyncContext already keeps the paired id in localStorage, so this stores
 * nothing new about the user.
 */
const KNOWN_PARTNER_KEY = 'sweetheart_known_partner_peer';

/* ------------------------------------------------------------------------- *
 * Peer identity
 * ------------------------------------------------------------------------- */

const PEER_ID_PREFIX = 'love-';

/**
 * Crockford base32: 32 symbols, no i / l / o / u so a hand-typed id cannot be
 * misread. Purely alphanumeric, which keeps the id valid under PEER_ID_REGEX and
 * under every signalling-server id rule we might meet.
 */
const BASE32_ALPHABET = '0123456789abcdefghjkmnpqrstvwxyz';

/** 10 bytes = 80 bits = exactly 16 base32 symbols. No padding, no bias, no loss. */
const PEER_ID_RANDOM_BYTES = 10;

function getRandomBytes(byteLength) {
  const bytes = new Uint8Array(byteLength);
  const cryptoObj = typeof window !== 'undefined' ? window.crypto : globalThis.crypto;
  cryptoObj.getRandomValues(bytes);
  return bytes;
}

/**
 * Generates a peer id that keeps every bit of its entropy.
 *
 * The previous implementation base64'd 6 random bytes and then ran
 * `.toLowerCase().replace(/[^a-z0-9]/g, 'x')` over it, folding A-Z onto a-z and
 * both '+' and '/' onto the single symbol 'x'. That collapsed 48 uniform bits to
 * about 40.75 bits over a non-uniform 36-symbol alphabet. Base32 needs no
 * mangling at all: the output is already lowercase alphanumeric.
 *
 * @returns {string} e.g. "love-4kq7z2m9r3wxb8vn" (80 bits of entropy)
 */
function generatePeerId() {
  const bytes = getRandomBytes(PEER_ID_RANDOM_BYTES);
  let value = 0;
  let bits = 0;
  let out = '';

  for (let i = 0; i < bytes.length; i++) {
    value = (value << 8) | bytes[i];
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += BASE32_ALPHABET[(value >>> bits) & 31];
      value &= (1 << bits) - 1;
    }
  }
  if (bits > 0) {
    out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }

  return PEER_ID_PREFIX + out;
}

function getStoredDevicePeerId() {
  try {
    if (typeof localStorage === 'undefined') return null;
    const id = localStorage.getItem(LOCAL_PEER_ID_KEY);
    // Ids minted by older builds are still perfectly usable; only the generator changed.
    if (id && PEER_ID_REGEX.test(id)) return id;
  } catch {
    // storage unavailable (private mode); fall through to a fresh id
  }
  return null;
}

function setStoredDevicePeerId(id) {
  try {
    if (typeof localStorage === 'undefined') return;
    if (id && PEER_ID_REGEX.test(id)) {
      localStorage.setItem(LOCAL_PEER_ID_KEY, id);
    }
  } catch {
    // safe fail
  }
}

function getStoredKnownPartnerId() {
  try {
    if (typeof localStorage === 'undefined') return null;
    const id = localStorage.getItem(KNOWN_PARTNER_KEY);
    if (id && PEER_ID_REGEX.test(id)) return id;
  } catch {
    // storage unavailable; admission control simply treats everyone as unknown
  }
  return null;
}

function setStoredKnownPartnerId(id) {
  try {
    if (typeof localStorage === 'undefined') return;
    if (id && PEER_ID_REGEX.test(id)) {
      localStorage.setItem(KNOWN_PARTNER_KEY, id);
    }
  } catch {
    // safe fail
  }
}

/* ------------------------------------------------------------------------- *
 * Wire allowlists
 * ------------------------------------------------------------------------- */

/**
 * Tables that may cross the wire. Derived from the database's own list and then
 * explicitly stripped of `vaultMeta`: the salt and canary that key the entire
 * vault must never be requestable, sendable or writable by a peer.
 */
const ALLOWED_TABLES = new Set(SYNCED_TABLES.filter((name) => name !== 'vaultMeta'));

const ALLOWED_MESSAGE_TYPES = new Set([
  'CHALLENGE',
  'CHALLENGE_RESPONSE',
  'CHALLENGE_ACK',
  'SYNC_MANIFEST',
  'SYNC_REQUEST_RECORDS',
  'SYNC_RECORDS_BATCH',
  'SYNC_COMPLETE',
  'SYNC_ERROR',
  'LIVE_RECORD_BROADCAST',
  'SYNC_CONFIG',
  'PING',
  'PONG',
]);

/** Fields common to every record shape, v1 and v2 alike. */
const WIRE_FIELDS_COMMON = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

/**
 * Legacy (schema v1) fields, per table. A partner who has not yet run the v2
 * re-encryption sweep still sends these, so they stay on the allowlist. Local-only
 * bookkeeping (`_del`, `needsReencrypt`) is deliberately absent: the receiver
 * derives both itself.
 */
const WIRE_FIELDS_BY_TABLE = {
  memories: ['date', 'captionCipher', 'captionIv', 'mimeType'],
  milestones: ['date', 'titleCipher', 'titleIv'],
  dateIdeas: ['category', 'isScratched', 'textCipher', 'textIv'],
  letters: ['unlockDate', 'isOpened', 'titleCipher', 'titleIv', 'contentCipher', 'contentIv'],
  bucketList: ['category', 'completed', 'completedAt', 'textCipher', 'textIv'],
};

function wireFieldsFor(table) {
  return new Set([...WIRE_FIELDS_COMMON, ...(WIRE_FIELDS_BY_TABLE[table] || [])]);
}

/**
 * The user-facing sentence for a refusal that is NOT staleness.
 *
 * Kept here, in one place, because the same fact reaches the user from two
 * directions (we refused their rows; they refused ours) and the two messages
 * must not drift into contradicting each other. It names the actual remedy: the
 * refusal is caused by the SENDER's rows predating the integrity binding, and
 * only the sender's device can fix that, by running a build that has the re-seal
 * sweep and unlocking once.
 *
 * @param {number} count
 * @returns {string}
 */
function unverifiableWarningText(count) {
  const plural = count === 1 ? '' : 's';
  return (
    `${count} change${plural} from your partner did not come through. ` +
    'Make sure Our Space is up to date on both phones, then open it again.'
  );
}

export class PeerSyncManager {
  constructor() {
    this.peer = null;
    this.activeConnection = null;
    this.myPeerId = null;
    this.cryptoKey = null;
    this.listeners = new Map();

    this.isConnected = false;
    this.isAuthorized = false;
    this.isSyncing = false;

    this.pendingChallengeNonce = null;
    /** Peer we deliberately dialled. Only this peer may win a pre-auth glare tie-break. */
    this.dialingPeerId = null;

    /* --- Admission control (S7) --- */
    /** Last peer id that completed the handshake. Survives a reload; see KNOWN_PARTNER_KEY. */
    this._knownPartnerId = getStoredKnownPartnerId();
    /** peerId -> { attempts, blockedUntil, lastSeenAt }. Bounded by ADMISSION_MAX_TRACKED_PEERS. */
    this._admission = new Map();
    /** Timestamps of recent UNKNOWN inbound admissions, for the flood circuit breaker. */
    this._unknownAdmissions = [];
    /** Whoever currently holds the single connection slot, and what they have proved. */
    this._slotKnown = false;
    this._slotSince = 0;
    this._slotProgressed = false;
    /** Throttles the "a stranger was refused" toast so a flood cannot spam the UI. */
    this._admissionWarnedAt = 0;

    this.authTimeoutTimer = null;
    this.connectOpenTimer = null;
    this.heartbeatTimer = null;
    this.lastPongAt = 0;

    /** 'direct' | 'relayed' | 'unknown' | null. `null` means "no connection", never "direct". */
    this.connectionType = null;
    this.routeProbeTimer = null;
    this.routeProbeAttempts = 0;
    this._iceListener = null;
    this._icePeerConnection = null;
    /** Set when ICE reports `failed`, so the close that follows stays quiet. */
    this._routeFailed = false;

    this.decryptFailures = 0;

    /** sessionId -> session. `out` = we advertised, we owe records. `in` = we requested, we owe a SYNC_COMPLETE. */
    this._outSessions = new Map();
    this._inSessions = new Map();

    /** Highest partner timestamp we have accepted, used to keep our own writes monotonic. */
    this._observedRemoteMax = 0;
    this._clockSkewWarned = false;

    this._hasRetriedUnavailableId = false;
    this.initPromise = null;
  }

  /* ----------------------------------------------------------------------- *
   * Event bus
   * ----------------------------------------------------------------------- */

  on(event, callback) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event).push(callback);
  }

  off(event, callback) {
    if (!this.listeners.has(event)) return;
    if (!callback) {
      this.listeners.delete(event);
      return;
    }
    const handlers = this.listeners.get(event);
    const index = handlers.indexOf(callback);
    if (index !== -1) {
      handlers.splice(index, 1);
    }
  }

  emit(event, payload) {
    const handlers = this.listeners.get(event) || [];
    [...handlers].forEach((fn) => {
      try {
        fn(payload);
      } catch (err) {
        console.error(`Error in peerSync listener for ${event}:`, err);
      }
    });
  }

  /**
   * The connection lifecycle state as it stands right now.
   * @returns {'disconnected'|'handshaking'|'authorized'|'syncing'}
   */
  _currentState() {
    if (!this.isConnected) return 'disconnected';
    if (!this.isAuthorized) return 'handshaking';
    return this.isSyncing ? 'syncing' : 'authorized';
  }

  /**
   * Emits a NON-FATAL problem.
   *
   * The status object carries the CURRENT lifecycle state, not an error state, so
   * reporting a dropped frame or a refused stranger can never make a live,
   * authenticated connection render as disconnected. UI shows `status.warning`.
   */
  _emitWarning(code, warning, extra = {}) {
    this.emit('status', {
      state: this._currentState(),
      code,
      warning,
      partnerId: this.activeConnection?.peer || null,
      connectionType: this.connectionType,
      isDirect: this.connectionType === 'direct',
      ...extra,
    });
  }

  /**
   * Emits a FATAL problem: the session is over.
   *
   * REG-1: the UI treats every state emitted here ('error', 'auth_failed',
   * 'ice_failed') as terminal - SyncContext drops `isAuthorized` and clears the
   * route badge - so emitting one while the data channel is still live paints a
   * dead link over an authenticated session that nothing will ever re-assert.
   * Rather than trusting fourteen call sites to remember to tear down first,
   * the invariant is enforced here: announcing the session is over MAKES it
   * over. Anything that is genuinely survivable must use _emitWarning, which
   * carries the current lifecycle state instead.
   */
  _emitFatal(code, error, state = 'error') {
    if (this.activeConnection || this.isConnected) {
      this._closeActiveConnection();
    }
    this.emit('status', { state, code, error });
  }

  /* ----------------------------------------------------------------------- *
   * Lifecycle
   * ----------------------------------------------------------------------- */

  /**
   * Initialize local WebRTC Peer
   * @param {CryptoKey} cryptoKey - The derived vault key for auth & encryption
   * @param {string} [customId] - Optional custom Peer ID
   */
  async init(cryptoKey, customId = null) {
    this.cryptoKey = cryptoKey;

    if (this.peer && !this.peer.destroyed && this.peer.open) {
      return this.myPeerId;
    }

    if (this.initPromise) {
      return this.initPromise;
    }

    if (customId && !PEER_ID_REGEX.test(customId)) {
      throw new Error('Invalid custom Peer ID format');
    }

    const iceServers = [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
      { urls: 'stun:global.stun.twilio.com:3478' },
    ];

    this.initPromise = new Promise((resolve, reject) => {
      let peerId = customId;
      if (!peerId) {
        peerId = getStoredDevicePeerId();
      }
      if (!peerId) {
        peerId = generatePeerId();
      }

      try {
        this.peer = new Peer(peerId, {
          config: { iceServers },
          debug: 0, // Disable internal PeerJS logging
        });
      } catch {
        this.initPromise = null;
        return reject(new Error('Could not start the connection on this phone.'));
      }

      this.peer.on('open', (id) => {
        this.myPeerId = id;
        this._hasRetriedUnavailableId = false;
        setStoredDevicePeerId(id);
        this.initPromise = null;
        this.emit('status', { state: 'ready', code: 'peer_ready', peerId: id });
        resolve(id);
      });

      this.peer.on('connection', (conn) => {
        this._setupConnection(conn, false);
      });

      this.peer.on('error', (err) => {
        // If a previous socket didn't close cleanly on reload, wait briefly and retry once with the same id.
        if (err?.type === 'unavailable-id') {
          if (!this._hasRetriedUnavailableId) {
            this._hasRetriedUnavailableId = true;
            setTimeout(() => {
              // PeerJS destroy() cascades a close onto any live data connection, but
              // tearing it down explicitly keeps our own state honest first.
              this._closeActiveConnection();
              try {
                this.peer?.destroy();
              } catch {
                // ignore
              }
              this.peer = null;
              this.initPromise = null;
              this.init(cryptoKey, peerId).then(resolve).catch(reject);
            }, 1200);
            return;
          }
          this._hasRetriedUnavailableId = false;
          const freshId = generatePeerId();
          setStoredDevicePeerId(freshId);
          this._closeActiveConnection();
          this.peer = null;
          this.initPromise = null;
          this.init(cryptoKey, freshId).then(resolve).catch(reject);
          return;
        }

        let msg = 'Could not reach your partner right now.';
        if (err?.type === 'peer-unavailable') {
          msg =
            'Cannot find their phone. Ask them to open Our Space and leave it on screen.';
          this._closeActiveConnection();
        } else if (err?.type === 'network') {
          msg = 'Trouble with the connection. Check your internet and try again.';
        }

        // REG-1, same class: this is the SIGNALLING socket failing, and the
        // 'disconnected' handler right below deliberately keeps the P2P data
        // channel alive through exactly that. Emitting a terminal 'error' while
        // an authenticated session is still carrying data would tell the user
        // their link is dead when it demonstrably is not.
        if (this.isAuthorized && this.activeConnection?.open) {
          this._emitWarning('signalling_' + (err?.type || 'error'), msg, { errorType: err?.type });
          return;
        }

        // Terminal state, so honour the same invariant _emitFatal enforces.
        if (this.activeConnection || this.isConnected) this._closeActiveConnection();
        this.emit('status', {
          state: 'error',
          code: err?.type || 'peer_error',
          error: msg,
          errorType: err?.type,
        });
      });

      this.peer.on('disconnected', () => {
        // Signalling server dropped us. The P2P data channel is independent and
        // must not be disturbed, so only the socket is re-established.
        try {
          if (this.peer && !this.peer.destroyed) {
            this.peer.reconnect();
          }
        } catch {
          // safe fail
        }
      });
    });

    return this.initPromise;
  }

  /**
   * Connect to partner's Peer ID with strict input validation
   */
  async connectToPartner(partnerPeerId) {
    const cleanId = (partnerPeerId || '').trim();
    if (!cleanId || !PEER_ID_REGEX.test(cleanId) || cleanId === this.myPeerId) {
      throw new Error('Invalid Partner Peer ID format');
    }

    // Already talking to exactly this partner: leave a good session alone.
    if (this.isConnected && this.isAuthorized && this.activeConnection?.peer === cleanId) {
      return;
    }

    if (!this.peer || this.peer.destroyed) {
      if (this.cryptoKey) {
        await this.init(this.cryptoKey);
      } else {
        throw new Error('Peer not initialized');
      }
    }

    if (!this.peer.open && this.initPromise) {
      await this.initPromise;
    }

    if (!this.peer || this.peer.destroyed || !this.peer.open) {
      throw new Error('Peer signaling not ready');
    }

    if (this.activeConnection) {
      this._closeActiveConnection();
    }

    this.dialingPeerId = cleanId;
    this.emit('status', { state: 'connecting', code: 'dialing', partnerId: cleanId });

    const conn = this.peer.connect(cleanId, { reliable: true });
    this._setupConnection(conn, true);
  }

  /* ----------------------------------------------------------------------- *
   * Admission control
   * ----------------------------------------------------------------------- */

  /**
   * A peer we have reason to expect: the one we are dialling right now, or the
   * one that last completed a handshake on this device. Everyone else is a
   * stranger, no matter how plausible their id looks.
   */
  _isKnownPeer(peerId) {
    if (!peerId) return false;
    return peerId === this.dialingPeerId || peerId === this._knownPartnerId;
  }

  /** Drops stale admission records so a rough evening does not become a permanent block. */
  _pruneAdmission(now) {
    for (const [peerId, entry] of this._admission) {
      if (now - entry.lastSeenAt > ADMISSION_ENTRY_TTL_MS) this._admission.delete(peerId);
    }
    // A flood that rotates peer ids would otherwise grow this map forever.
    // Evict oldest-first; the flood breaker below is what actually stops them.
    while (this._admission.size > ADMISSION_MAX_TRACKED_PEERS) {
      const oldest = this._admission.keys().next().value;
      if (oldest === undefined) break;
      this._admission.delete(oldest);
    }
    this._unknownAdmissions = this._unknownAdmissions.filter(
      (t) => now - t < ADMISSION_FLOOD_WINDOW_MS
    );
  }

  /**
   * Decides whether an INBOUND peer may take the pairing slot at all.
   *
   * S7: the previous build only applied admission control when the slot was
   * already occupied, so in the idle state - the normal state - any stranger who
   * knew our permanent, publicly-brokered peer id could take the slot and hold it
   * for the full open/auth timeout, over and over, forever. Pairing denial is not
   * a bounded delay when nothing rate-limits the reconnect.
   *
   * @returns {{ allowed: boolean, reason?: string }}
   */
  _admitInbound(peerId, isKnown) {
    const now = Date.now();
    this._pruneAdmission(now);

    const entry = this._admission.get(peerId);
    if (entry && entry.blockedUntil > now) {
      return { allowed: false, reason: 'backoff' };
    }

    if (!isKnown && this._unknownAdmissions.length >= ADMISSION_FLOOD_MAX_UNKNOWN) {
      // Under a flood we shut the door on everyone we cannot vouch for. The known
      // partner still gets in, and dialling out still works, so this degrades
      // pairing rather than breaking the app. Losing the slot to an attacker is
      // not recoverable by the user; being told to try again is.
      return { allowed: false, reason: 'flood' };
    }

    return { allowed: true };
  }

  /**
   * Arms this peer's cooldown as it takes the slot. It is cleared only by a
   * successful handshake (_noteAdmissionSuccess), so a loop that never
   * authenticates walks itself up an exponential backoff while a real partner
   * pays nothing after its first good connection.
   */
  _noteAdmission(peerId, isKnown) {
    const now = Date.now();
    const entry = this._admission.get(peerId) || { attempts: 0, blockedUntil: 0, lastSeenAt: now };
    entry.attempts += 1;
    entry.lastSeenAt = now;

    let backoff;
    if (isKnown) {
      const over = entry.attempts - KNOWN_PEER_FREE_ATTEMPTS;
      backoff = over <= 0 ? 0 : Math.min(1000 * 2 ** (over - 1), KNOWN_PEER_BACKOFF_MAX_MS);
    } else {
      backoff = Math.min(
        ADMISSION_BACKOFF_BASE_MS * 2 ** (entry.attempts - 1),
        ADMISSION_BACKOFF_MAX_MS
      );
      this._unknownAdmissions.push(now);
    }
    entry.blockedUntil = now + backoff;

    // Re-insert so map order stays oldest-first for the size eviction above.
    this._admission.delete(peerId);
    this._admission.set(peerId, entry);
  }

  /** A completed handshake proves this peer belongs here. Forget every strike. */
  _noteAdmissionSuccess(peerId) {
    if (!peerId) return;
    this._admission.delete(peerId);
    this._knownPartnerId = peerId;
    setStoredKnownPartnerId(peerId);
  }

  /** Refuses a connection without ever letting it touch the slot. */
  _refuseConnection(conn, warningCode, warningText) {
    try {
      conn.close();
    } catch {
      // ignore
    }
    this._refuseWarn(warningCode, warningText);
  }

  /**
   * Whether a newcomer may evict the peer currently holding the slot.
   *
   * Only ever applies to an UNAUTHENTICATED incumbent. A known peer always beats
   * a stranger, and a stranger that has not yet delivered a single decryptable
   * frame has proved nothing and is evictable once its grace period is up. That
   * is what stops a squatter from locking out a real partner, without letting an
   * attacker interrupt a handshake that is visibly making progress.
   */
  _mayEvictIncumbent(conn) {
    if (!this.activeConnection || this.isAuthorized) return false;
    if (this._slotKnown) return false;
    if (this._isKnownPeer(conn.peer)) return true;
    if (this._slotProgressed) return false;
    return Date.now() - this._slotSince >= STRANGER_EVICT_AFTER_MS;
  }

  /**
   * Admission control for a new data connection.
   *
   * An AUTHENTICATED session is never sacrificed for an unauthenticated newcomer,
   * and during the pre-auth window only the peer we are actually dialling is
   * allowed into the glare tie-break. Anyone else is refused outright, so a
   * stranger cannot pick a low peer id and repeatedly kill handshakes.
   */
  _setupConnection(conn, isInitiator) {
    if (!conn || typeof conn.peer !== 'string') return;
    if (this.activeConnection === conn) return; // already wired up

    const isKnown = isInitiator || this._isKnownPeer(conn.peer);

    const existing = this.activeConnection;
    if (existing) {
      if (this.isAuthorized) {
        if (conn.peer !== existing.peer) {
          this._refuseConnection(
            conn,
            'unknown_peer_rejected',
            'Someone else tried to connect. We said no.'
          );
          return;
        }
        // Same partner reconnecting (reload, network handoff): replace cleanly.
      } else {
        const expectedPeer = this.dialingPeerId || existing.peer;
        if (conn.peer !== expectedPeer) {
          // Not who we were talking to. Normally refused - but a stranger must
          // not be able to squat the slot and lock the real partner out, so a
          // stalled, unproven incumbent can be evicted.
          if (!this._mayEvictIncumbent(conn)) {
            this._refuseConnection(
              conn,
              'unknown_peer_rejected',
              'Someone else tried to connect while you were pairing. We said no.'
            );
            return;
          }
        } else if (this.myPeerId && this.myPeerId <= conn.peer) {
          // Genuine glare: both sides dialled each other at once. Deterministic
          // tie-break, but only ever against the peer we were already talking to.
          try {
            conn.close();
          } catch {
            // ignore
          }
          return;
        }
      }
    }

    // The idle slot is NOT free for the taking. Rate-limit and flood-break every
    // inbound peer before it is allowed to start any timer of ours.
    if (!isInitiator) {
      const verdict = this._admitInbound(conn.peer, isKnown);
      if (!verdict.allowed) {
        this._refuseConnection(
          conn,
          verdict.reason === 'flood' ? 'pairing_flood' : 'peer_rate_limited',
          verdict.reason === 'flood'
            ? 'A few unknown phones are trying to connect, so pairing is paused for a minute. This does not affect your partner.'
            : 'A phone is retrying too fast, so we asked it to wait a moment.'
        );
        return;
      }
      this._noteAdmission(conn.peer, isKnown);
    }

    this._closeActiveConnection();
    // _closeActiveConnection clears dialingPeerId, but we are, right now, dialling
    // this peer - losing that would make our own partner look like a stranger to
    // the glare tie-break and to admission control.
    if (isInitiator) this.dialingPeerId = conn.peer;
    this.activeConnection = conn;
    this.decryptFailures = 0;
    this._routeFailed = false;
    this._slotKnown = isKnown;
    this._slotSince = Date.now();
    this._slotProgressed = false;

    // The auth clock starts the moment a peer occupies the slot, not when the data
    // channel opens: otherwise a peer that stalls ICE squats here forever. An
    // unknown peer gets a materially shorter leash than one we expect.
    this._startAuthTimeout(conn, isKnown);
    this._startConnectOpenTimeout(conn, isKnown);

    const handleOpen = async () => {
      if (this.activeConnection !== conn) return;
      this._clearConnectOpenTimeout();
      this.isConnected = true;

      // NOT 'connected'. Nothing is verified yet - this peer is a stranger until
      // the challenge-response completes. UI must never render this as paired.
      this.emit('status', { state: 'handshaking', code: 'channel_open', partnerId: conn.peer });

      if (isInitiator) {
        try {
          await this._sendAuthChallenge();
        } catch {
          this._closeActiveConnection();
          this._emitFatal('challenge_failed', 'Could not start the connection. Try again.');
        }
      }
    };

    if (conn.open) {
      handleOpen();
    } else {
      conn.on('open', handleOpen);
    }

    conn.on('data', (data) => {
      if (this.activeConnection !== conn) return;
      this._handleMessage(data).catch((err) => this._handlePipelineError(err));
    });

    conn.on('close', () => {
      if (this.activeConnection !== conn) return;
      // An ICE failure has already reported itself with actionable copy; letting
      // the close overwrite it with a bare "disconnected" would throw that away.
      const routeFailed = this._routeFailed;
      this._closeActiveConnection();
      if (!routeFailed) {
        this.emit('status', { state: 'disconnected', code: 'peer_closed' });
      }
    });

    conn.on('error', () => {
      if (this.activeConnection === conn) {
        this._closeActiveConnection();
        this._emitFatal('data_channel_error', 'The connection dropped.');
      }
    });
  }

  /**
   * Anything that escapes the message pipeline. Storage exhaustion is fatal and
   * must be visible; everything else degrades to a dropped frame.
   */
  _handlePipelineError(err) {
    const name = err?.name || '';
    if (name === 'QuotaExceededError' || name === 'NotEnoughSpaceError') {
      this._abortAllSessions('storage_full', { silent: true });
      this._emitFatal(
        'storage_full',
        'This phone is out of space, so new memories could not be saved. Free some space and try again.'
      );
      return;
    }
    this._emitWarning(
      'message_failed',
      'Something came through that we could not use, so we skipped it.'
    );
  }

  /**
   * @param {boolean} isKnown - Whether this peer is one we expect. A stranger gets
   *   a shorter window AND a quiet teardown: reporting every stranger's timeout as
   *   a loud "authentication failed" would hand an attacker a way to spam alarming
   *   toasts at the user. The loud path is kept for a first-ever pairing, where a
   *   timeout really is the answer the user is waiting for.
   */
  _startAuthTimeout(conn, isKnown = true) {
    this._clearAuthTimeout();
    const timeout = isKnown ? AUTH_TIMEOUT_MS : UNKNOWN_AUTH_TIMEOUT_MS;
    const quiet = !isKnown && Boolean(this._knownPartnerId);
    this.authTimeoutTimer = setTimeout(() => {
      if (this.activeConnection !== conn || this.isAuthorized) return;
      if (quiet) {
        this._closeActiveConnection();
        this._refuseWarn(
          'stranger_auth_timeout',
          'Someone else tried to pair and did not finish. We disconnected them.'
        );
        return;
      }
      this._emitFatal(
        'auth_timeout',
        `Authentication timed out after ${Math.round(
          timeout / 1000
        )} seconds. Your partner never completed the secure handshake.`,
        'auth_failed'
      );
    }, timeout);
  }

  /** Throttled warning, shared with _refuseConnection so strangers cannot spam the UI. */
  _refuseWarn(code, text) {
    const now = Date.now();
    if (now - this._admissionWarnedAt < ADMISSION_WARN_INTERVAL_MS) return;
    this._admissionWarnedAt = now;
    this._emitWarning(code, text);
  }

  _clearAuthTimeout() {
    if (this.authTimeoutTimer) {
      clearTimeout(this.authTimeoutTimer);
      this.authTimeoutTimer = null;
    }
  }

  /**
   * Bounds how long a peer may hold the connection slot without opening a channel.
   * An unknown peer that never opens a channel is the cheapest possible squat -
   * it costs the attacker one signalling message - so its window is short and its
   * teardown is quiet.
   */
  _startConnectOpenTimeout(conn, isKnown = true) {
    this._clearConnectOpenTimeout();
    const timeout = isKnown ? CONNECT_OPEN_TIMEOUT_MS : UNKNOWN_CONNECT_OPEN_TIMEOUT_MS;
    const quiet = !isKnown && Boolean(this._knownPartnerId);
    this.connectOpenTimer = setTimeout(() => {
      if (this.activeConnection !== conn || conn.open) return;
      if (quiet) {
        this._closeActiveConnection();
        this._refuseWarn(
          'stranger_open_timeout',
          'Someone else was holding up pairing, so we disconnected them.'
        );
        return;
      }
      this._emitFatal(
        'ice_failed',
        'Could not open a direct connection to your partner. This app uses no relay server, so a strict mobile network (CGNAT) on either side can block pairing. Try the same Wi-Fi network, or a different network on one device.',
        'ice_failed'
      );
    }, timeout);
  }

  _clearConnectOpenTimeout() {
    if (this.connectOpenTimer) {
      clearTimeout(this.connectOpenTimer);
      this.connectOpenTimer = null;
    }
  }

  /* ----------------------------------------------------------------------- *
   * Liveness
   * ----------------------------------------------------------------------- */

  _startHeartbeat() {
    this._clearHeartbeat();
    this.lastPongAt = Date.now();
    this.heartbeatTimer = setInterval(() => {
      this._heartbeatTick().catch(() => {
        // handled inside
      });
    }, HEARTBEAT_INTERVAL_MS);
  }

  /**
   * A half-open RTCDataChannel keeps accepting send() without error, which is
   * exactly what happens on a mobile network handoff. The only reliable detector
   * is a missing reply, so the interval enforces one.
   */
  async _heartbeatTick() {
    if (!this.isConnected || !this.isAuthorized || !this.activeConnection?.open || !this.cryptoKey) {
      this._clearHeartbeat();
      return;
    }

    if (Date.now() - this.lastPongAt > HEARTBEAT_TIMEOUT_MS) {
      this._closeActiveConnection();
      this._emitFatal(
        'peer_unresponsive',
        'Lost them - their phone stopped responding. Tap to reconnect.'
      );
      return;
    }

    try {
      await this._send({ type: 'PING', t: Date.now() });
    } catch {
      this._closeActiveConnection();
      this.emit('status', { state: 'disconnected', code: 'send_failed' });
    }
  }

  _clearHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  _resetAuthState() {
    this._clearAuthTimeout();
    this._clearConnectOpenTimeout();
    this._clearHeartbeat();
    this._clearRouteProbe();
    this._abortAllSessions('disconnected', { silent: true });
    this.pendingChallengeNonce = null;
    this.isAuthorized = false;
    this.isSyncing = false;
    this.connectionType = null;
    this.decryptFailures = 0;
    this.lastPongAt = 0;
  }

  _closeActiveConnection() {
    this._resetAuthState();
    this.isConnected = false;
    this.dialingPeerId = null;
    this._slotKnown = false;
    this._slotSince = 0;
    this._slotProgressed = false;
    if (this.activeConnection) {
      try {
        this.activeConnection.close();
      } catch {
        // ignore
      }
      this.activeConnection = null;
    }
  }

  closeConnection() {
    this._closeActiveConnection();
    this.emit('status', { state: 'disconnected', code: 'closed_locally' });
  }

  /* ----------------------------------------------------------------------- *
   * Connection route
   * ----------------------------------------------------------------------- */

  /**
   * Inspects the WebRTC candidate pair to classify the route.
   *
   * There is deliberately NO TURN server in this app, so "relayed" can only ever
   * mean a relay the browser found on its own. What matters here is honesty: when
   * ICE has not nominated a pair yet, or getStats is unavailable, or anything
   * throws, the answer is 'unknown'. Claiming 'direct' in those cases is what made
   * the old "Direct P2P" badge effectively hardcoded on.
   *
   * @returns {Promise<'direct' | 'relayed' | 'unknown' | null>} null only when there is no connection at all.
   */
  async checkConnectionType() {
    if (!this.isConnected || !this.activeConnection) return null;

    const pc = this.activeConnection.peerConnection;
    if (!pc || typeof pc.getStats !== 'function') {
      return 'unknown';
    }

    try {
      const stats = await pc.getStats();
      let isRelayed = false;
      let hasPair = false;

      stats.forEach((report) => {
        if (
          report.type === 'candidate-pair' &&
          (report.selected ||
            report.nominated ||
            (report.state === 'succeeded' && report.bytesSent > 0))
        ) {
          hasPair = true;
          const local = stats.get(report.localCandidateId);
          const remote = stats.get(report.remoteCandidateId);
          if (local?.candidateType === 'relay' || remote?.candidateType === 'relay') {
            isRelayed = true;
          }
        }
      });

      if (!hasPair) return 'unknown';
      return isRelayed ? 'relayed' : 'direct';
    } catch {
      return 'unknown';
    }
  }

  /**
   * ICE has usually not nominated a pair at the instant authentication finishes,
   * so a single sample there is worthless. This polls until the route is known
   * (or gives up and says so) and watches for outright ICE failure.
   */
  _startRouteProbe() {
    this._clearRouteProbe();
    this.routeProbeAttempts = 0;

    const pc = this.activeConnection?.peerConnection;
    if (pc && typeof pc.addEventListener === 'function') {
      // addEventListener, never `pc.oniceconnectionstatechange = ...`: PeerJS owns
      // that property and assigning to it silently breaks its own negotiation.
      this._iceListener = () => {
        const state = pc.iceConnectionState;
        if (state === 'failed') {
          this._routeFailed = true;
          this._emitFatal('ice_failed', ICE_FAILURE_MESSAGE, 'ice_failed');
        } else if (state === 'connected' || state === 'completed') {
          this._probeRoute();
        }
      };
      pc.addEventListener('iceconnectionstatechange', this._iceListener);
      this._icePeerConnection = pc;
    }

    this.routeProbeTimer = setInterval(() => {
      this._probeRoute();
    }, ROUTE_PROBE_INTERVAL_MS);

    this._probeRoute();
  }

  async _probeRoute() {
    if (!this.isConnected || !this.isAuthorized) {
      this._clearRouteProbe();
      return;
    }

    this.routeProbeAttempts++;
    const type = await this.checkConnectionType();
    const settled = type === 'direct' || type === 'relayed';
    const giveUp = this.routeProbeAttempts >= ROUTE_PROBE_MAX_ATTEMPTS;

    if (settled || giveUp) {
      const resolved = settled ? type : 'unknown';
      if (resolved !== this.connectionType) {
        this.connectionType = resolved;
        this.emit('status', {
          state: this._currentState(),
          code: 'route_update',
          partnerId: this.activeConnection?.peer || null,
          connectionType: resolved,
          isDirect: resolved === 'direct',
        });
      }
      this._clearRouteProbe();
    }
  }

  _clearRouteProbe() {
    if (this.routeProbeTimer) {
      clearInterval(this.routeProbeTimer);
      this.routeProbeTimer = null;
    }
    if (this._icePeerConnection && this._iceListener) {
      try {
        this._icePeerConnection.removeEventListener('iceconnectionstatechange', this._iceListener);
      } catch {
        // ignore
      }
    }
    this._iceListener = null;
    this._icePeerConnection = null;
  }

  /* ----------------------------------------------------------------------- *
   * Transport
   * ----------------------------------------------------------------------- */

  async _send(message) {
    const conn = this.activeConnection;
    if (!conn || !conn.open) throw new Error('No open connection to your partner');
    if (!this.cryptoKey) throw new Error('Vault is locked');

    const payload = await encryptJSON(message, this.cryptoKey);
    if (typeof payload?.ciphertext !== 'string') {
      throw new Error('Message could not be encrypted');
    }
    if (payload.ciphertext.length > MAX_CIPHERTEXT_LENGTH) {
      throw new Error('Message is too large to send');
    }
    conn.send({ protocol: PROTOCOL_ID, payload });
  }

  /**
   * Initiator step: send a cryptographically secure random challenge nonce.
   */
  async _sendAuthChallenge() {
    if (!this.activeConnection || !this.cryptoKey) return;
    const nonce = generateSecureNonce(16);
    this.pendingChallengeNonce = nonce;
    await this._send({ type: 'CHALLENGE', nonce });
  }

  /* ----------------------------------------------------------------------- *
   * Message pipeline
   * ----------------------------------------------------------------------- */

  async _handleMessage(msg) {
    if (!msg || typeof msg !== 'object' || !msg.payload || typeof msg.payload !== 'object') {
      return;
    }

    if (msg.protocol === LEGACY_PROTOCOL_ID) {
      this._closeActiveConnection();
      this._emitFatal(
        'version_mismatch',
        'Their Our Space is out of date. Update it on both phones so you can sync.'
      );
      return;
    }
    if (msg.protocol !== PROTOCOL_ID) return;

    const { ciphertext, iv } = msg.payload;
    if (typeof ciphertext !== 'string' || typeof iv !== 'string') return;
    if (ciphertext.length > MAX_CIPHERTEXT_LENGTH) {
      // The only way to hit this from a well-behaved partner is a record that
      // slipped past their own send-side cap. Never silent.
      if (this.isAuthorized) {
        this._emitWarning(
          'oversized_message',
          'Something was too big to send. We will try it again next time.'
        );
      } else {
        this._closeActiveConnection();
        this._emitFatal('oversized_message', 'Something went wrong while pairing. Try again.');
      }
      return;
    }

    if (!this.cryptoKey) return; // vault locked mid-session; not a passphrase problem

    let decrypted;
    try {
      decrypted = await decryptJSON(ciphertext, iv, this.cryptoKey);
    } catch {
      this._handleDecryptFailure();
      return;
    }

    // A frame that decrypts proves the channel is alive and the key matches.
    this.decryptFailures = 0;
    this.lastPongAt = Date.now();
    // Real protocol progress. From here the slot holder is no longer evictable by
    // a newcomer, so an attacker cannot interrupt a handshake that is working.
    this._slotProgressed = true;

    if (!decrypted || typeof decrypted !== 'object' || !ALLOWED_MESSAGE_TYPES.has(decrypted.type)) {
      return;
    }

    const isAuthMsg =
      decrypted.type === 'CHALLENGE' ||
      decrypted.type === 'CHALLENGE_RESPONSE' ||
      decrypted.type === 'CHALLENGE_ACK';

    if (!this.isAuthorized && !isAuthMsg) return;

    switch (decrypted.type) {
      case 'CHALLENGE':
        await this._onChallenge(decrypted);
        break;
      case 'CHALLENGE_RESPONSE':
        await this._onChallengeResponse(decrypted);
        break;
      case 'CHALLENGE_ACK':
        await this._onChallengeAck(decrypted);
        break;

      case 'PING':
        try {
          await this._send({ type: 'PONG', t: Date.now() });
        } catch {
          // The next heartbeat tick will notice if the channel is really gone.
        }
        break;

      case 'PONG':
        // lastPongAt already refreshed above.
        break;

      case 'SYNC_CONFIG':
        this._onSyncConfig(decrypted.config);
        break;

      case 'SYNC_MANIFEST':
        await this._onSyncManifest(decrypted);
        break;

      case 'SYNC_REQUEST_RECORDS':
        await this._onSyncRequestRecords(decrypted);
        break;

      case 'SYNC_RECORDS_BATCH':
        await this._onSyncRecordsBatch(decrypted);
        break;

      case 'SYNC_COMPLETE':
        this._onSyncComplete(decrypted);
        break;

      case 'SYNC_ERROR':
        this._onSyncError(decrypted);
        break;

      case 'LIVE_RECORD_BROADCAST':
        await this._applySingleLiveRecord(decrypted.record);
        break;

      default:
        break;
    }
  }

  /**
   * BEFORE authentication a decrypt failure means the two vaults hold different
   * keys - that really is a passphrase mismatch and the session is over.
   *
   * AFTER authentication the key is proven, so a failure is one corrupted frame.
   * Killing the session (and blaming the passphrase) would be a lie. Count it,
   * drop it, and only tear down on a sustained run.
   */
  _handleDecryptFailure() {
    if (!this.isAuthorized) {
      this._closeActiveConnection();
      this._emitFatal(
        'passphrase_mismatch',
        'Your passphrases do not match. Check you both typed exactly the same one.',
        'auth_failed'
      );
      return;
    }

    this.decryptFailures++;
    if (this.decryptFailures >= MAX_DECRYPT_FAILURES) {
      this._closeActiveConnection();
      this._emitFatal(
        'corrupt_stream',
        'Too much came through that we could not read, so we closed the connection. Tap to reconnect.'
      );
      return;
    }

    this._emitWarning(
      'corrupt_frame',
      'Something came through that we could not read, so we skipped it.'
    );
  }

  async _onChallenge(decrypted) {
    if (typeof decrypted.nonce !== 'string' || decrypted.nonce.length < 16) {
      this._closeActiveConnection();
      this._emitFatal('bad_challenge', 'Something went wrong while pairing. Try again.', 'auth_failed');
      return;
    }

    const counterNonce = generateSecureNonce(16);
    this.pendingChallengeNonce = counterNonce;

    await this._send({
      type: 'CHALLENGE_RESPONSE',
      echo: decrypted.nonce,
      counterNonce,
    });
  }

  async _onChallengeResponse(decrypted) {
    if (
      !this.pendingChallengeNonce ||
      typeof decrypted.echo !== 'string' ||
      decrypted.echo !== this.pendingChallengeNonce ||
      typeof decrypted.counterNonce !== 'string' ||
      decrypted.counterNonce.length < 16
    ) {
      this._closeActiveConnection();
      this._emitFatal(
        'challenge_replay',
        'Pairing did not go through. Try again.',
        'auth_failed'
      );
      return;
    }

    this.pendingChallengeNonce = null;

    await this._send({ type: 'CHALLENGE_ACK', echo: decrypted.counterNonce });
    await this._onAuthorized();
  }

  async _onChallengeAck(decrypted) {
    if (
      !this.pendingChallengeNonce ||
      typeof decrypted.echo !== 'string' ||
      decrypted.echo !== this.pendingChallengeNonce
    ) {
      this._closeActiveConnection();
      this._emitFatal(
        'challenge_replay',
        'Pairing did not go through. Try again.',
        'auth_failed'
      );
      return;
    }

    this.pendingChallengeNonce = null;
    await this._onAuthorized();
  }

  /**
   * Shared post-authentication path.
   *
   * BOTH sides run this, and BOTH sides advertise a manifest. That is what makes
   * replication bidirectional: previously only the initiator advertised, so a
   * record that existed only on the answering device was never offered to anyone.
   * Neither of these sessions asks for a reciprocal, so exactly two sessions run
   * per handshake and the exchange provably terminates.
   */
  async _onAuthorized() {
    this._clearAuthTimeout();
    this._clearConnectOpenTimeout();
    this.isAuthorized = true;
    this.dialingPeerId = null;
    this.lastPongAt = Date.now();

    // Honest until proven otherwise: the route is unknown until ICE settles.
    this.connectionType = 'unknown';
    this._startHeartbeat();

    this.emit('status', {
      state: 'authorized',
      code: 'authorized',
      partnerId: this.activeConnection?.peer,
      connectionType: this.connectionType,
      isDirect: false,
    });

    this._startRouteProbe();
    await this.syncNow({ wantReciprocal: false });
  }

  /* ----------------------------------------------------------------------- *
   * Sync sessions
   * ----------------------------------------------------------------------- */

  _sessionMap(kind) {
    return kind === 'out' ? this._outSessions : this._inSessions;
  }

  _openSession(kind, sessionId, extra = {}) {
    const map = this._sessionMap(kind);
    const session = {
      id: sessionId,
      kind,
      startedAt: Date.now(),
      applied: 0,
      rejected: 0,
      // Rows the partner sent that we refused an overwrite or a delete because
      // their binding could not be verified. Tracked apart from `rejected`
      // (unreadable) and from staleness (our copy is genuinely newer) because it
      // is the only one of the three the user can act on - see
      // _commitStagedRecords.
      unverifiable: 0,
      expectedSeq: 0,
      timer: null,
      ...extra,
    };
    map.set(sessionId, session);
    this._touchSession(session);

    const wasIdle = !this.isSyncing;
    this.isSyncing = true;
    if (wasIdle) {
      this.emit('status', {
        state: 'syncing',
        code: 'sync_started',
        partnerId: this.activeConnection?.peer || null,
        connectionType: this.connectionType,
        isDirect: this.connectionType === 'direct',
      });
    }
    return session;
  }

  /** Restarts a session's stall timer. Called on every observable step forward. */
  _touchSession(session) {
    if (!session) return;
    // A session that already finished or timed out must not resurrect its timer.
    if (this._sessionMap(session.kind).get(session.id) !== session) return;
    if (session.timer) clearTimeout(session.timer);
    session.timer = setTimeout(() => {
      const map = this._sessionMap(session.kind);
      if (map.get(session.id) !== session) return;
      this._closeSession(session.kind, session.id);
      this._emitFatal(
        'sync_timeout',
        'That took too long, so we stopped. Nothing was lost - try again.'
      );
    }, SYNC_SESSION_TIMEOUT_MS);
  }

  _closeSession(kind, sessionId) {
    const map = this._sessionMap(kind);
    const session = map.get(sessionId);
    if (!session) return null;
    if (session.timer) clearTimeout(session.timer);
    map.delete(sessionId);
    if (this._outSessions.size === 0 && this._inSessions.size === 0) {
      this.isSyncing = false;
    }
    return session;
  }

  _abortAllSessions(code, options = {}) {
    let had = false;
    for (const kind of ['out', 'in']) {
      const map = this._sessionMap(kind);
      for (const session of map.values()) {
        if (session.timer) clearTimeout(session.timer);
        had = true;
      }
      map.clear();
    }
    this.isSyncing = false;
    if (had && !options.silent) {
      this._emitWarning(code, 'That was cancelled.');
    }
  }

  /**
   * Ends one session and reports it. `synced` is only emitted once EVERY session
   * has drained, so the other direction still running cannot flip the UI out of
   * its syncing state prematurely.
   */
  _finishSession(kind, sessionId, message, extra = {}) {
    this._closeSession(kind, sessionId);
    this.emit('status', {
      state: this.isSyncing ? 'syncing' : 'synced',
      code: this.isSyncing ? 'sync_progress' : 'sync_complete',
      message,
      partnerId: this.activeConnection?.peer || null,
      connectionType: this.connectionType,
      isDirect: this.connectionType === 'direct',
      ...extra,
    });
  }

  async _sendSyncError(sessionId, code, message, extra = {}) {
    try {
      await this._send({ type: 'SYNC_ERROR', sessionId, code, message, ...extra });
    } catch {
      // If we cannot even report the error, the session timer will finish the job.
    }
  }

  /**
   * Advertises the local manifest, opening a sync session we own.
   *
   * @param {{ wantReciprocal?: boolean }} [options] - When true (the default, i.e.
   *   a user-triggered "Sync Now"), the partner is asked to advertise its own
   *   manifest back. A reciprocal manifest is always sent with `wantReciprocal:false`,
   *   so the exchange is at most one level deep and can never ping-pong.
   * @returns {Promise<boolean>} True when a session was opened.
   */
  async syncNow(options = {}) {
    if (!this.isConnected || !this.isAuthorized || !this.activeConnection?.open) return false;
    if (this._outSessions.size >= MAX_CONCURRENT_SESSIONS) return false;

    const wantReciprocal = options.wantReciprocal !== false;
    const sessionId = generateSecureNonce(9);

    this._openSession('out', sessionId, { phase: 'advertised' });

    try {
      const manifest = await db.getManifest();
      await this._send({ type: 'SYNC_MANIFEST', sessionId, manifest, wantReciprocal });
      return true;
    } catch (err) {
      this._closeSession('out', sessionId);
      this._emitWarning(
        'sync_start_failed',
        'Could not start syncing. Try again.'
      );
      return false;
    }
  }

  /**
   * Consumer side. Works out what we are missing and asks for exactly that.
   */
  async _onSyncManifest(decrypted) {
    const sessionId = decrypted.sessionId;
    if (typeof sessionId !== 'string' || sessionId.length < 8 || sessionId.length > 64) {
      await this._sendSyncError(
        typeof sessionId === 'string' ? sessionId : 'unknown',
        'bad_session',
        'Missing or malformed sessionId'
      );
      return;
    }
    if (this._inSessions.has(sessionId)) {
      await this._sendSyncError(sessionId, 'duplicate_session', 'That sync session is already open');
      return;
    }
    if (this._inSessions.size >= MAX_CONCURRENT_SESSIONS) {
      await this._sendSyncError(sessionId, 'too_many_sessions', 'Too many sync sessions in flight');
      return;
    }

    const remoteManifest = decrypted.manifest;
    if (!remoteManifest || typeof remoteManifest !== 'object' || Array.isArray(remoteManifest)) {
      await this._sendSyncError(sessionId, 'manifest_rejected', 'Manifest was not an object');
      this._emitWarning('manifest_rejected', 'Something came through that we could not read. Try again.');
      return;
    }

    let requests = [];
    try {
      requests = await this._diffManifest(remoteManifest);
    } catch (err) {
      await this._sendSyncError(sessionId, 'manifest_rejected', 'Could not read the local manifest');
      this._emitWarning(
        'manifest_rejected',
        // Deliberately does NOT interpolate err.message: these read like
        // "Cannot verify which copy of a record is newer" and this string goes
        // on screen in a couple's app, not into a log.
        'Could not compare notes with your partner. Try again.'
      );
      return;
    }

    if (requests.length === 0) {
      // Nothing wanted: terminate this direction immediately.
      await this._sendSyncComplete(sessionId, 0, 0);
    } else {
      this._openSession('in', sessionId, { phase: 'requested', requested: requests.length });
      try {
        await this._send({ type: 'SYNC_REQUEST_RECORDS', sessionId, requests });
      } catch (err) {
        this._closeSession('in', sessionId);
        this._emitWarning(
          'sync_request_failed',
          'Could not ask your partner for updates. Try again.'
        );
        return;
      }
    }

    // Bidirectional convergence for a user-triggered sync. The reply carries
    // wantReciprocal:false, which is what bounds the exchange.
    if (decrypted.wantReciprocal === true && this._outSessions.size === 0) {
      await this.syncNow({ wantReciprocal: false });
    }
  }

  /**
   * @param {string} sessionId
   * @param {number} applied
   * @param {number} rejected
   * @param {number} [unverifiable] - How many of the partner's rows we refused
   *   an overwrite or delete because we could not verify them. A build that
   *   predates this field ignores it, which is exactly the build most likely to
   *   be on the receiving end of it.
   */
  async _sendSyncComplete(sessionId, applied, rejected, unverifiable = 0) {
    try {
      await this._send({ type: 'SYNC_COMPLETE', sessionId, applied, rejected, unverifiable });
    } catch {
      // The provider's session timer will clean up.
    }
  }

  /**
   * Compares a remote manifest against ours.
   *
   * Ties (`remote.updatedAt === local.updatedAt`) are deliberately NOT requested:
   * fetching every equal-timestamp record on every round would transfer the whole
   * library forever. The deterministic tie-break lives on the apply path, where it
   * actually matters, because that is where two competing versions meet.
   */
  async _diffManifest(remoteManifest) {
    const localManifest = await db.getManifest();
    const requests = [];
    const now = Date.now();
    let sawFutureTimestamp = false;

    for (const [table, remoteItems] of Object.entries(remoteManifest)) {
      if (!ALLOWED_TABLES.has(table) || !Array.isArray(remoteItems)) continue;
      if (remoteItems.length > MAX_RECORDS_PER_TABLE) continue;

      const localMap = new Map((localManifest[table] || []).map((i) => [i.id, i.updatedAt]));

      for (const rItem of remoteItems) {
        if (!rItem || typeof rItem.id !== 'string' || rItem.id.length > 128) continue;

        // Number.isFinite is the guard that matters: `typeof NaN === 'number'` and
        // `typeof Infinity === 'number'` both pass a naive typeof check, and an
        // Infinity timestamp would win every comparison forever.
        if (!Number.isFinite(rItem.updatedAt) || rItem.updatedAt < 0) continue;
        if (rItem.updatedAt > now + MAX_CLOCK_SKEW_MS) {
          sawFutureTimestamp = true;
          continue;
        }

        const localUpdatedAt = localMap.get(rItem.id);
        if (localUpdatedAt === undefined || rItem.updatedAt > localUpdatedAt) {
          requests.push({ table, id: rItem.id });
          if (requests.length >= MAX_REQUESTS_PER_SESSION) break;
        }
      }
      if (requests.length >= MAX_REQUESTS_PER_SESSION) break;
    }

    if (sawFutureTimestamp) this._warnClockSkew();
    return requests;
  }

  _warnClockSkew() {
    if (this._clockSkewWarned) return;
    this._clockSkewWarned = true;
    this._emitWarning(
      'clock_skew',
      "Your partner's device clock looks far ahead of yours, so some of their items were not accepted. Check the date and time settings on both phones."
    );
  }

  /**
   * Provider side. Chunks the requested records into frames that stay well under
   * the ciphertext ceiling, sequenced so the consumer can detect a gap.
   */
  async _onSyncRequestRecords(decrypted) {
    const sessionId = decrypted.sessionId;
    const session = typeof sessionId === 'string' ? this._outSessions.get(sessionId) : null;
    if (!session) {
      await this._sendSyncError(
        typeof sessionId === 'string' ? sessionId : 'unknown',
        'unknown_session',
        'No such sync session',
        { fatal: true }
      );
      return;
    }
    if (session.phase !== 'advertised') {
      // A second request list would restart `seq` at 0 and desync the consumer.
      await this._sendSyncError(sessionId, 'duplicate_request', 'Records were already sent for that session', {
        fatal: true,
      });
      return;
    }
    session.phase = 'sending';
    this._touchSession(session);

    const requests = Array.isArray(decrypted.requests) ? decrypted.requests : [];
    if (requests.length > MAX_REQUESTS_PER_SESSION) {
      await this._sendSyncError(sessionId, 'too_many_requests', 'Request list exceeded the limit', {
        fatal: true,
      });
      this._closeSession('out', sessionId);
      this._emitWarning('too_many_requests', 'That was more than we can send at once. Try again.');
      return;
    }

    let batch = [];
    let batchBytes = 0;
    let seq = 0;
    const oversized = [];

    const flush = async (final) => {
      const records = batch;
      batch = [];
      batchBytes = 0;
      await this._send({ type: 'SYNC_RECORDS_BATCH', sessionId, seq, records, final });
      seq++;
      this._touchSession(session);
    };

    try {
      for (const req of requests) {
        if (
          !req ||
          typeof req !== 'object' ||
          !ALLOWED_TABLES.has(req.table) ||
          typeof req.id !== 'string' ||
          req.id.length > 128
        ) {
          continue;
        }

        const row = await db.table(req.table).get(req.id);
        if (!row) continue;

        const wire = this._toWireRecord(req.table, row);
        const bytes = this._estimateWireBytes(wire);

        if (bytes > MAX_SINGLE_RECORD_BYTES) {
          // No silent drops. Both sides find out.
          oversized.push({ table: req.table, id: req.id });
          continue;
        }

        if (batch.length > 0 && batchBytes + bytes > MAX_BATCH_PAYLOAD_BYTES) {
          await flush(false);
        }

        batch.push({ table: req.table, data: wire });
        batchBytes += bytes;
      }

      if (oversized.length > 0) {
        await this._sendSyncError(
          sessionId,
          'record_too_large',
          `${oversized.length} item(s) are too large to transfer`,
          { items: oversized.slice(0, 50) }
        );
        this._emitWarning(
          'record_too_large',
          `${oversized.length} item(s) are too large to send to your partner and were skipped. Re-add the photo at a smaller size to sync it.`
        );
      }

      // Always terminate the stream, even when nothing matched.
      await flush(true);
    } catch (err) {
      this._closeSession('out', sessionId);
      await this._sendSyncError(sessionId, 'send_failed', 'Could not send records', { fatal: true });
      this._emitWarning(
        'send_failed',
        'Could not send your memories right now. We will try again next time.'
      );
    }
  }

  /**
   * Consumer side. Applies one chunk and, on the final one, terminates the session
   * with an explicit SYNC_COMPLETE so the provider stops waiting.
   */
  async _onSyncRecordsBatch(decrypted) {
    const sessionId = decrypted.sessionId;
    const session = typeof sessionId === 'string' ? this._inSessions.get(sessionId) : null;
    if (!session) {
      await this._sendSyncError(
        typeof sessionId === 'string' ? sessionId : 'unknown',
        'unknown_session',
        'No such sync session',
        { fatal: true }
      );
      return;
    }

    if (decrypted.seq !== session.expectedSeq) {
      this._closeSession('in', sessionId);
      await this._sendSyncError(sessionId, 'out_of_order', 'Batch arrived out of order', {
        fatal: true,
      });
      this._emitWarning(
        'out_of_order',
        'Things arrived out of order, so we stopped. Try again.'
      );
      return;
    }
    session.expectedSeq++;
    this._touchSession(session);

    const result = await this._applyRemoteRecords(decrypted.records);
    session.applied += result.applied;
    session.rejected += result.rejected;
    session.unverifiable += result.unverifiable;

    if (decrypted.final === true) {
      const applied = session.applied;
      const rejected = session.rejected;
      const unverifiable = session.unverifiable;
      this._closeSession('in', sessionId);

      await this._sendSyncComplete(sessionId, applied, rejected, unverifiable);

      // "All memories up to date!" is a claim, and with `unverifiable > 0` it is
      // a false one: the partner made changes, we received them, and we threw
      // them away. Emit no message at all in that case and let the warning below
      // carry the news, rather than printing a reassurance and a contradiction
      // in two banners at once. (SyncContext only records `message` when it is
      // truthy, so a null here leaves the previous notice to expire on its own.)
      const message =
        applied > 0
          ? `Synced ${applied} update${applied === 1 ? '' : 's'} from your partner!`
          : unverifiable > 0
            ? null
            : 'All memories up to date!';

      this.emit('status', {
        state: this.isSyncing ? 'syncing' : 'synced',
        code: this.isSyncing ? 'sync_progress' : 'sync_complete',
        message,
        applied,
        rejected,
        unverifiable,
        partnerId: this.activeConnection?.peer || null,
        connectionType: this.connectionType,
        isDirect: this.connectionType === 'direct',
      });

      if (applied > 0) {
        this.emit('data-updated', { count: applied });
      }
      if (rejected > 0) {
        this._emitWarning(
          'records_rejected',
          `${rejected} item(s) from your partner could not be read and were skipped.`
        );
      }
      if (unverifiable > 0) {
        this._emitWarning('records_unverifiable', unverifiableWarningText(unverifiable), {
          unverifiable,
        });
      }
    }
  }

  /**
   * Provider side: the consumer is done, so this direction is finished.
   *
   * "Your partner is up to date!" was printed here whenever `applied` came back
   * 0, which included the case where the partner had received our changes and
   * refused all of them. From THIS side that is the more likely direction of the
   * problem - we are the ones whose rows cannot be verified - so the count is
   * read off the wire and reported. A partner on an older build sends no
   * `unverifiable` field at all; it reads as 0 and this behaves exactly as it
   * did, which is the best that can be done from this end.
   */
  _onSyncComplete(decrypted) {
    const sessionId = decrypted.sessionId;
    if (typeof sessionId !== 'string' || !this._outSessions.has(sessionId)) return;

    const applied = Number.isFinite(decrypted.applied) ? decrypted.applied : 0;
    const unverifiable =
      Number.isFinite(decrypted.unverifiable) && decrypted.unverifiable > 0
        ? Math.min(decrypted.unverifiable, MAX_REQUESTS_PER_SESSION)
        : 0;

    const message =
      applied > 0
        ? `Sent ${applied} update${applied === 1 ? '' : 's'} to your partner!`
        : unverifiable > 0
          ? null
          : 'Your partner is up to date!';

    this._finishSession('out', sessionId, message, { sent: applied, unverifiable });

    if (unverifiable > 0) {
      this._emitWarning(
        'records_unverifiable_remote',
        `Your partner's phone could not verify ${unverifiable} of your change${unverifiable === 1 ? '' : 's'} and did not apply ${unverifiable === 1 ? 'it' : 'them'}. Make sure both phones are on the same version of Our Space, then unlock this vault again and sync.`,
        { unverifiable }
      );
    }
  }

  _onSyncError(decrypted) {
    const sessionId = typeof decrypted.sessionId === 'string' ? decrypted.sessionId : null;
    const code = typeof decrypted.code === 'string' ? decrypted.code.slice(0, 64) : 'sync_error';
    const detail = typeof decrypted.message === 'string' ? decrypted.message.slice(0, 200) : '';

    if (sessionId && decrypted.fatal === true) {
      this._closeSession('out', sessionId);
      this._closeSession('in', sessionId);
    }

    const human =
      code === 'record_too_large'
        ? 'Some items on your partner\'s device are too large to transfer and were skipped.'
        : `Your partner reported a sync problem${detail ? `: ${detail}` : '.'}`;

    this._emitWarning(code, human);
  }

  /* ----------------------------------------------------------------------- *
   * Record marshalling
   * ----------------------------------------------------------------------- */

  /**
   * Converts a stored row into its wire form.
   *
   * Schema v2 rows are `{ id, updatedAt, deleted, v, ciphertext, iv }` plus an
   * independently-encrypted `imageBlob`; the blob is base64'd because JSON cannot
   * carry binary. Local-only bookkeeping (`_del`, `needsReencrypt`) never leaves
   * this device - the receiver derives its own.
   */
  _toWireRecord(table, row) {
    const allowed = wireFieldsFor(table);
    const wire = {};

    for (const [field, value] of Object.entries(row)) {
      if (value === undefined) continue;
      if (!allowed.has(field)) continue;
      wire[field] = value;
    }

    wire.id = row.id;
    wire.updatedAt = Number.isFinite(row.updatedAt) ? row.updatedAt : 0;
    wire.deleted = row.deleted === true;

    if (table === 'memories' && row.imageBlob) {
      wire.imageBlobBase64 = bufferToBase64(row.imageBlob);
    }

    return wire;
  }

  /**
   * Cheap byte estimate for one wire record. Everything that can be large is a
   * base64 string (ciphertext, imageBlobBase64), so string length is an accurate
   * proxy and avoids stringifying the payload twice.
   */
  _estimateWireBytes(wire) {
    let bytes = 128;
    for (const [field, value] of Object.entries(wire)) {
      bytes += field.length + 8;
      if (typeof value === 'string') bytes += value.length;
      else bytes += 16;
    }
    return bytes;
  }

  /**
   * Structural validation of an inbound record header.
   * @returns {{ ok: boolean, code?: string }}
   */
  _validateWireRecord(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) return { ok: false, code: 'shape' };
    if (typeof data.id !== 'string' || data.id.length < 1 || data.id.length > 128) {
      return { ok: false, code: 'bad_id' };
    }
    // Rejects NaN and Infinity, both of which pass a bare `typeof === 'number'`.
    if (!Number.isFinite(data.updatedAt) || data.updatedAt < 0) {
      return { ok: false, code: 'bad_timestamp' };
    }
    if (data.updatedAt > Date.now() + MAX_CLOCK_SKEW_MS) {
      return { ok: false, code: 'future_timestamp' };
    }
    if (typeof data.deleted !== 'boolean') return { ok: false, code: 'bad_tombstone' };
    if (data.v !== undefined && data.v !== 1 && data.v !== 2) return { ok: false, code: 'bad_version' };
    return { ok: true };
  }

  /**
   * Copies an inbound record through a strict field allowlist so a hostile or
   * corrupted peer cannot persist arbitrary keys into the live tables. Never
   * mutates the caller's object.
   * @returns {Object|null} The row to store, or null to reject it.
   */
  _sanitizeIncomingRow(table, data) {
    const allowed = wireFieldsFor(table);
    const row = {};

    for (const [field, value] of Object.entries(data)) {
      if (value === undefined) continue;
      if (!allowed.has(field)) continue;
      row[field] = value;
    }

    row.id = data.id;
    row.updatedAt = data.updatedAt;
    row.deleted = data.deleted === true;
    // `_del` is the 0/1 index mirror IndexedDB needs (it refuses boolean keys).
    // Dexie hooks maintain it too, but writing it here keeps the manifest correct
    // even on write paths that bypass hooks.
    row._del = row.deleted ? 1 : 0;

    if (table === 'memories' && typeof data.imageBlobBase64 === 'string') {
      try {
        const bytes = base64ToBuffer(data.imageBlobBase64);
        if (bytes.byteLength > MAX_IMAGE_BLOB_BYTES) return null;
        row.imageBlob = bytes;
      } catch {
        return null;
      }
    }

    return row;
  }

  /**
   * Proves an inbound record is genuinely ours before it is written.
   *
   * peerSync holds the vault key, and the envelope is a small JSON blob (the photo
   * itself stays binary and is opened only when it is displayed), so this is one
   * cheap AES-GCM open per record, plus - only when a record carries a photo -
   * one SHA-256 pass over those bytes.
   *
   * WHAT IT PROVES DEPENDS ON THE ROW'S SCHEMA AND ON HOW OLD ITS ENVELOPE IS,
   * and the difference is the whole reason the commit gate exists as well as
   * this one. Scoped precisely, because these dimensions did not ship together:
   *
   *  - EVERY v2 row: the key opened the envelope, and the envelope's own copy of
   *    the plaintext id / updatedAt / deleted header matches the row's
   *    (`_headerTampered`). No exception and no version window - encryptRecord
   *    has sealed that header inside the payload since v2 existed at all - so a
   *    peer can never rewrite a header undetected.
   *  - A v2 row sealed WITH a digest map: the SHA-256 of the attached photo
   *    bytes matches too (`_binaryTampered`), so a peer cannot keep a valid
   *    envelope while swapping the photo underneath it.
   *  - A v2 row sealed WITH a table binding: the table the peer filed it under
   *    matches the one it was sealed for (`_tableTampered`), so a peer cannot
   *    replay a bucketList tombstone as a delete against a letter.
   *  - v1: the key opened SOME `<base>Cipher` field, and that is all.
   *    decryptLegacyRecord() stamps every tamper flag false unconditionally
   *    because v1 carries no authenticated header, no digest and no binding -
   *    there is nothing to compare against. A clean verdict on a v1 row means
   *    "unknowable". That is why _commitStagedRecords additionally refuses any
   *    v1 row aimed at an id that already exists: it may create, never destroy.
   *
   * Three cases stay unverified on purpose, and they are the SAME case three
   * times: an envelope sealed before the digest map existed, one sealed before
   * the table binding existed, and one the sender's own sweep re-sealed out of a
   * v1 row (PROVENANCE_LEGACY, surfaced as `_headerUnverified`). All are
   * accepted as-is rather than rejected outright, because refusing them would
   * break every photo already in the vault and cut a partner off completely
   * rather than partially. See BINARY_DIGEST_FIELD, TABLE_BINDING_FIELD and
   * PROVENANCE_FIELD in crypto.js.
   *
   * BUT `unverified` IS NOT `ok`, AND THE DIFFERENCE IS NOT TEMPORARY FOR
   * EVERYONE. db.migrateLegacyRecords() re-seals the first two kinds at unlock,
   * so a device on THIS build drains its own rows. A partner on an older build
   * never runs that sweep - it ships in this build - so their rows keep arriving
   * unverified indefinitely, and _commitStagedRecords refuses every update and
   * every delete they send for as long as that lasts. Their creates still land.
   * The third kind never drains at all, by design: a v1 row's header was never
   * authenticated and re-sealing must not pretend otherwise.
   *
   * Callers must therefore report an `unverified` refusal as its own outcome
   * (`unverifiable`), not as staleness - the partner is NOT up to date, and the
   * only fix is on their device.
   *
   * @param {Object} row
   * @param {string} [table] - The table the peer filed this row under. Omit it
   *   and the table dimension is simply not checked.
   * @returns {Promise<{ ok: boolean, code?: string, unverified?: boolean }>}
   *   `{ok:false, code}` refuses the row outright. `{ok:true, unverified:false}`
   *   is proved on every dimension. `{ok:true, unverified:true}` opened cleanly
   *   but carries at least one ABSENT binding: it may create, never overwrite or
   *   delete. `unverified` is present on every ok verdict and is the field
   *   _stageIncomingRecords carries onto the staged entry.
   */
  async _verifyRecordIntegrity(row, table) {
    if (!this.cryptoKey) return { ok: false, code: 'locked' };
    // See recordCarriesAuthenticatedPayload: decryptRecord resolving does not by
    // itself prove our key was used, because a row with no ciphertext resolves
    // through the legacy path untouched. Without this an authenticated peer
    // could push a bare row over any id it can guess.
    if (!recordCarriesAuthenticatedPayload(row)) {
      return { ok: false, code: 'unauthenticated' };
    }
    try {
      const plain = await decryptRecord(row, this.cryptoKey, { table });
      // Reported separately from header_tampered only so the rejection counter
      // names the real reason; every one of these verdicts refuses the write.
      if (plain && plain._binaryTampered === true) {
        return { ok: false, code: 'binary_tampered' };
      }
      if (plain && plain._tableTampered === true) {
        return { ok: false, code: 'table_mismatch' };
      }
      if (plain && plain._headerTampered === true) {
        return { ok: false, code: 'header_tampered' };
      }
      // Binding ABSENT is neither ok nor tampered. It is reported so the caller
      // can allow a create but refuse an overwrite - the same rule the import
      // path applies. The re-seal sweep does NOT cover this: it re-seals rows
      // this device HOLDS, while this only ever decrypts the row ARRIVING, so an
      // envelope harvested before binding existed would otherwise stay a
      // permanent capability against that id no matter how often we sweep.
      if (
        plain &&
        (plain._binaryUnverified === true ||
          plain._tableUnverified === true ||
          plain._headerUnverified === true)
      ) {
        return { ok: true, unverified: true };
      }
      return { ok: true, unverified: false };
    } catch {
      return { ok: false, code: 'undecryptable' };
    }
  }

  /**
   * Validates, sanitizes and integrity-checks a list of inbound records.
   * Deliberately runs OUTSIDE any Dexie transaction: awaiting Web Crypto inside
   * one would let the transaction commit out from under us.
   */
  async _stageIncomingRecords(items) {
    const staged = [];
    const reasons = new Map();
    let rejected = 0;

    const note = (code) => {
      rejected++;
      reasons.set(code, (reasons.get(code) || 0) + 1);
    };

    for (const item of items) {
      if (!item || typeof item !== 'object' || !ALLOWED_TABLES.has(item.table)) {
        note('table');
        continue;
      }

      const check = this._validateWireRecord(item.data);
      if (!check.ok) {
        note(check.code);
        continue;
      }

      const row = this._sanitizeIncomingRow(item.table, item.data);
      if (!row) {
        note('blob_rejected');
        continue;
      }

      // `item.table` is the peer's own claim about where this row belongs, and
      // it is exactly the claim being checked: a sealed table binding that
      // disagrees with it is a cross-table replay.
      const integrity = await this._verifyRecordIntegrity(row, item.table);
      if (!integrity.ok) {
        note(integrity.code);
        continue;
      }

      // Carried on the staged entry rather than mutating the row: `row` is what
      // gets written to IndexedDB, and a bookkeeping field would be persisted.
      staged.push({ table: item.table, row, unverifiedBinding: integrity.unverified === true });
    }

    if (reasons.has('future_timestamp')) this._warnClockSkew();
    return { staged, rejected, reasons };
  }

  /**
   * Decides whether an inbound version replaces the local one.
   *
   * Newer wins. Older LOSES - that is the whole point, and its absence is what let
   * a stale LIVE_RECORD_BROADCAST silently clobber newer local data. Equal
   * timestamps are broken deterministically so both devices pick the SAME winner
   * and converge, instead of each keeping its own copy forever.
   */
  _incomingWins(existing, incoming) {
    if (!existing) return true;

    const localAt = Number.isFinite(existing.updatedAt) ? existing.updatedAt : -1;
    const remoteAt = incoming.updatedAt;

    if (remoteAt > localAt) return true;
    if (remoteAt < localAt) return false;

    // Tie-break 1: a deletion is never resurrected by a same-instant edit.
    const localDeleted = existing.deleted === true;
    const remoteDeleted = incoming.deleted === true;
    if (localDeleted !== remoteDeleted) return remoteDeleted;

    // Tie-break 2: lexicographic on a stable fingerprint. Both devices compare the
    // same pair of strings, so both reach the same verdict.
    return this._fingerprint(incoming) > this._fingerprint(existing);
  }

  _fingerprint(row) {
    const parts = [String(row.v || 1), row.ciphertext || '', row.iv || ''];
    // The `<base>Cipher` fields are folded in ONLY for a row that has no
    // authenticated envelope, i.e. a v1 row, where they are the only content
    // there is and dropping them would make every v1 row at a given id
    // fingerprint identically.
    //
    // On a v2 row they are exactly the bug class removed below for the blob's
    // byteLength: leftover, unauthenticated, attacker-choosable. A v2 envelope
    // does not seal them, so appending `captionCipher: "zzzz"` to an otherwise
    // byte-identical replay used to flip the tie-break - _incomingWins(local,
    // {...local, captionCipher: 'zzzz'}) returned true. Nothing is lost by
    // dropping them here: on a v2 row every field that matters is inside
    // `ciphertext`, which is already the second part of this string.
    if (!recordHasAuthenticatedHeader(row)) {
      for (const field of Object.keys(row).sort()) {
        if (field.endsWith('Cipher') && typeof row[field] === 'string') {
          parts.push(field, row[field]);
        }
      }
    }
    // DELIBERATELY NOT the blob's byteLength. It used to be appended here, and
    // that was a working attack: the length is not authenticated, so an attacker
    // could replay a harvested envelope BYTE FOR BYTE - same ciphertext, same iv,
    // same updatedAt, no forgery needed - with a garbage photo whose length in
    // decimal happens to sort high ('900...' beats '64'). Every other part of the
    // fingerprint matched, so this one attacker-chosen string decided the
    // tie-break and the real photo was overwritten.
    //
    // Nothing is lost by dropping it. For a row sealed by the current
    // encryptRecord the blob's digest lives INSIDE the encrypted payload, so a
    // different blob necessarily means different ciphertext, which is already in
    // the fingerprint above. For an older row the length proves nothing at all.
    return parts.join('|');
  }

  /**
   * Writes staged records, skipping anything the merge rule says is stale.
   * The transaction is scoped to the tables actually being touched - `vaultMeta`
   * is never among them, so a photo import cannot block a salt read.
   *
   * TWO KINDS OF "NOT WRITTEN", AND THEY MUST NOT SHARE A COUNTER.
   * `stale` means the merge rule looked at both copies and ours is newer. That
   * is a non-event: nothing is missing and there is nothing for anyone to do.
   * `unverifiable` means the partner's copy might well have been the newer one
   * and we refused it anyway, because it could not be proved to belong to the id
   * it targets. That IS an event - the partner's edit is gone and the only fix
   * is on their device - and it used to be counted as `stale`, which the caller
   * then reported as "up to date". A partner on a build older than the re-seal
   * sweep has EVERY update and EVERY delete land in this bucket, forever,
   * because the sweep that would fix their rows only exists in this build.
   *
   * @param {Array<{table: string, row: Object, unverifiedBinding: boolean}>} staged
   * @returns {Promise<{ applied: number, stale: number, unverifiable: number }>}
   */
  async _commitStagedRecords(staged) {
    if (staged.length === 0) return { applied: 0, stale: 0, unverifiable: 0 };

    const tableNames = [...new Set(staged.map((s) => s.table))];
    const tables = tableNames.map((name) => db.table(name));

    let applied = 0;
    let stale = 0;
    let unverifiable = 0;

    await db.transaction('rw', tables, async () => {
      for (const { table, row, unverifiedBinding } of staged) {
        const existing = await db.table(table).get(row.id);
        // Overwriting or deleting an existing row requires a BOUND header, so a
        // v1 row can only ever create. decryptLegacyRecord cannot detect a
        // rewritten id / updatedAt / deleted header (see
        // recordHasAuthenticatedHeader), which would otherwise let a single
        // ciphertext produced under the vault key be aimed at any id as a
        // forged tombstone.
        if (existing && !recordHasAuthenticatedHeader(row)) {
          unverifiable++;
          continue;
        }
        // Same rule for a binding that is merely absent: an envelope predating
        // the photo digest or the table binding cannot prove which bytes or
        // which table it belongs to, so it may create but never overwrite or
        // delete. Without this a harvested pre-binding envelope erases a photo
        // (swap the bytes, or just omit them) with no UI in the way at all,
        // because the sync path has no confirmation step. The same verdict
        // covers a row the partner's own sweep re-sealed out of v1
        // (PROVENANCE_LEGACY -> `_headerUnverified`).
        if (existing && unverifiedBinding === true) {
          unverifiable++;
          continue;
        }
        if (!this._incomingWins(existing, row)) {
          stale++;
          continue;
        }
        await db.table(table).put(row);
        applied++;
      }
    });

    // Keeps our own future writes ahead of anything the partner has issued, so a
    // device with a slow clock cannot be permanently out-voted.
    for (const { row } of staged) {
      if (row.updatedAt > this._observedRemoteMax) this._observedRemoteMax = row.updatedAt;
    }

    return { applied, stale, unverifiable };
  }

  async _applyRemoteRecords(records) {
    if (!this.isAuthorized || !Array.isArray(records)) {
      return { applied: 0, rejected: 0, stale: 0, unverifiable: 0 };
    }

    const { staged, rejected } = await this._stageIncomingRecords(records);
    const { applied, stale, unverifiable } = await this._commitStagedRecords(staged);
    return { applied, rejected, stale, unverifiable };
  }

  /* ----------------------------------------------------------------------- *
   * Live broadcast
   * ----------------------------------------------------------------------- */

  /**
   * Real-time push of a single record. Fire-and-forget by design: it NEVER
   * rejects, so the six call sites that do not attach a .catch() cannot produce
   * an unhandled rejection. A failure is surfaced as a warning and the record is
   * picked up by the next manifest sync.
   *
   * @param {string} table
   * @param {Object} record - The stored row (i.e. what db.putEncrypted returned).
   * @returns {Promise<boolean>} True when the record was handed to the channel.
   */
  async broadcastLiveRecord(table, record) {
    if (!this.isConnected || !this.isAuthorized || !ALLOWED_TABLES.has(table)) return false;
    if (!record || typeof record !== 'object' || typeof record.id !== 'string') return false;

    try {
      const wire = this._toWireRecord(table, record);
      const bytes = this._estimateWireBytes(wire);

      if (bytes > MAX_SINGLE_RECORD_BYTES) {
        this._emitWarning(
          'record_too_large',
          'That one is too big to send. Try adding the photo again a bit smaller.'
        );
        return false;
      }

      await this._send({ type: 'LIVE_RECORD_BROADCAST', record: { table, data: wire } });
      return true;
    } catch (err) {
      this._emitWarning(
        'broadcast_failed',
        'Could not send that just now. It will go through next time you connect.'
      );
      return false;
    }
  }

  /**
   * Applies one live-broadcast record - through exactly the same validation,
   * integrity check and staleness guard as a batched sync. The old blind put()
   * here is what let a late-arriving broadcast overwrite newer local data.
   */
  async _applySingleLiveRecord(record) {
    if (!this.isAuthorized || !record || typeof record !== 'object') return;

    const { staged, rejected, reasons } = await this._stageIncomingRecords([record]);
    if (staged.length === 0) {
      if (rejected > 0) {
        const code = [...reasons.keys()][0] || 'record_rejected';
        this._emitWarning(
          code,
          'One update could not be read, so we skipped it.'
        );
      }
      return;
    }

    // A stale broadcast is silently ignored: our copy is simply newer, and that is
    // a race the user can neither see nor act on. An UNVERIFIABLE one is the
    // opposite - the partner's live edit was discarded and only their device can
    // fix it - so it is surfaced, on the same wording the batched path uses.
    const { applied, unverifiable } = await this._commitStagedRecords(staged);
    if (applied > 0) {
      this.emit('data-updated', { single: true, count: applied, table: record.table });
    }
    if (unverifiable > 0) {
      this._emitWarning('records_unverifiable', unverifiableWarningText(unverifiable), {
        unverifiable,
      });
    }
  }

  /* ----------------------------------------------------------------------- *
   * Vault config
   * ----------------------------------------------------------------------- */

  /**
   * Syncs relationship anniversary start date & couple names across devices.
   */
  async syncVaultConfig(config) {
    if (!this.isConnected || !this.isAuthorized || !this.cryptoKey) return false;
    try {
      await this._send({
        type: 'SYNC_CONFIG',
        config: {
          coupleNames: String(config?.coupleNames || '').slice(0, MAX_COUPLE_NAMES_LENGTH),
          startDate: ISO_DATE_REGEX.test(config?.startDate || '') ? config.startDate : '',
          updatedAt: Number.isFinite(config?.updatedAt) ? config.updatedAt : Date.now(),
        },
      });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * The sender coerces its own fields; the receiver must not simply trust that.
   * Everything here is bounded and shape-checked before it reaches the app, which
   * writes it straight into vault settings.
   */
  _onSyncConfig(config) {
    if (!config || typeof config !== 'object' || Array.isArray(config)) {
      this._emitWarning('bad_config', 'We could not read their details. Try again.');
      return;
    }

    const coupleNames =
      typeof config.coupleNames === 'string'
        ? config.coupleNames.slice(0, MAX_COUPLE_NAMES_LENGTH)
        : '';
    const startDate =
      typeof config.startDate === 'string' && ISO_DATE_REGEX.test(config.startDate)
        ? config.startDate
        : '';

    let updatedAt = 0;
    if (
      Number.isFinite(config.updatedAt) &&
      config.updatedAt >= 0 &&
      config.updatedAt <= Date.now() + MAX_CLOCK_SKEW_MS
    ) {
      updatedAt = config.updatedAt;
    }

    if (!coupleNames && !startDate) {
      this._emitWarning('bad_config', 'Nothing to update from their side.');
      return;
    }

    this.emit('config-synced', { coupleNames, startDate, updatedAt });
  }

  /* ----------------------------------------------------------------------- *
   * Clock
   * ----------------------------------------------------------------------- */

  /**
   * A write timestamp that is monotonic on this device AND ahead of anything the
   * partner has issued.
   *
   * Raw `Date.now()` last-write-wins means a device whose clock runs slow can
   * never win a merge, and one whose clock runs fast wins everything. Callers that
   * stamp `updatedAt` on a new or edited record should use this instead of
   * `Date.now()`.
   *
   * @returns {number}
   */
  getSyncSafeTimestamp() {
    let floor = 0;
    try {
      if (typeof localStorage !== 'undefined') {
        const raw = localStorage.getItem(SYNC_CLOCK_KEY);
        const parsed = Number(raw);
        if (Number.isFinite(parsed) && parsed > 0) floor = parsed;
      }
    } catch {
      // storage unavailable; in-memory high-water mark still applies
    }

    const next = Math.max(Date.now(), floor + 1, this._observedRemoteMax + 1);

    try {
      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(SYNC_CLOCK_KEY, String(next));
      }
    } catch {
      // safe fail
    }

    return next;
  }

  /* ----------------------------------------------------------------------- *
   * Teardown
   * ----------------------------------------------------------------------- */

  /**
   * Disconnect from the current partner session (leaves the local peer listening).
   */
  disconnect() {
    this.closeConnection();
  }

  /**
   * Drops the signalling socket and the peer node but KEEPS the vault key, so
   * init() can rebuild everything without the user unlocking again. Used on page
   * hide, where the page may well come back.
   */
  releaseTransport() {
    this._closeActiveConnection();
    try {
      this.peer?.destroy();
    } catch {
      // ignore
    }
    this.peer = null;
    this.myPeerId = null;
    this.initPromise = null;
  }

  /**
   * Full teardown of the local peer node and all key material (vault lock).
   */
  destroy() {
    this.releaseTransport();
    this.cryptoKey = null;
    this._observedRemoteMax = 0;
    this._clockSkewWarned = false;
    this.emit('status', { state: 'disconnected', code: 'destroyed' });
  }
}

export const peerSync = new PeerSyncManager();

if (typeof window !== 'undefined') {
  /**
   * `pagehide` rather than `beforeunload`: beforeunload also fires on navigations
   * the user then CANCELS, and on bfcache-eligible navigations they can come back
   * from. The old handler destroyed the key in both cases, leaving a live page
   * with no way to reconnect short of re-entering the passphrase.
   */
  window.addEventListener('pagehide', (event) => {
    if (event.persisted) return; // going into bfcache; the page may return intact
    try {
      peerSync.releaseTransport();
    } catch {
      // ignore
    }
  });

  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible') return;

      if (peerSync.peer && !peerSync.peer.destroyed && peerSync.peer.disconnected) {
        try {
          peerSync.peer.reconnect();
        } catch {
          // ignore
        }
      }

      // Coming back from a long background can leave a half-open data channel that
      // still accepts send(). Force the liveness check rather than waiting.
      if (peerSync.isAuthorized) {
        peerSync._heartbeatTick().catch(() => {});
      }
    });
  }
}

export default peerSync;
