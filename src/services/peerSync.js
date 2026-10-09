import Peer from 'peerjs';
import {
  encryptJSON,
  decryptJSON,
  generateSecureNonce,
  bufferToBase64,
  base64ToBuffer,
  decryptRecord,
  recordHasAuthenticatedHeader,
  RECORD_SCHEMA_VERSION,
} from './crypto.js';
import { PEER_ID_REGEX } from '../utils/invite.js';
import db, { SYNCED_TABLES, MAX_IMAGE_BLOB_BYTES, MAX_RECORDS_PER_TABLE } from '../db/index.js';
import { buildIceServers } from './iceServers.js';
import {
  MAX_BATCH_PAYLOAD_BYTES,
  MAX_SINGLE_RECORD_BYTES,
} from './limits.js';

const PROTOCOL_ID = 'SWEETHEART_V2';
const LEGACY_PROTOCOL_ID = 'SWEETHEART_V1';

const MAX_CIPHERTEXT_LENGTH = 30 * 1024 * 1024;

const AUTH_TIMEOUT_MS = 30000;
const CONNECT_OPEN_TIMEOUT_MS = 15000;

const UNKNOWN_CONNECT_OPEN_TIMEOUT_MS = 8000;
const UNKNOWN_AUTH_TIMEOUT_MS = 12000;

const STRANGER_EVICT_AFTER_MS = 3000;

const ADMISSION_BACKOFF_BASE_MS = 2000;
const ADMISSION_BACKOFF_MAX_MS = 5 * 60 * 1000;
const KNOWN_PEER_FREE_ATTEMPTS = 3;
const KNOWN_PEER_BACKOFF_MAX_MS = 15000;
const ADMISSION_ENTRY_TTL_MS = 30 * 60 * 1000;
const ADMISSION_MAX_TRACKED_PEERS = 128;
const ADMISSION_FLOOD_WINDOW_MS = 60000;
const ADMISSION_FLOOD_MAX_UNKNOWN = 6;
const ADMISSION_WARN_INTERVAL_MS = 30000;

const HEARTBEAT_INTERVAL_MS = 15000;
const HEARTBEAT_TIMEOUT_MS = 50000;
const SYNC_SESSION_TIMEOUT_MS = 120000;

const MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

const MAX_DECRYPT_FAILURES = 5;
const MAX_REQUESTS_PER_SESSION = 5000;
const MAX_CONCURRENT_SESSIONS = 4;
const MAX_COUPLE_NAMES_LENGTH = 120;

const ROUTE_PROBE_INTERVAL_MS = 1500;
const ROUTE_PROBE_MAX_ATTEMPTS = 12;

const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

const ICE_FAILURE_MESSAGE =
  'Could not open a direct connection to your partner. This app uses no relay server, so a strict mobile network (CGNAT) on either side can block pairing. Try putting both devices on the same Wi-Fi, or switch one device to a different network.';

const LOCAL_PEER_ID_KEY = 'sweetheart_device_peer_id';
const SYNC_CLOCK_KEY = 'sweetheart_sync_clock';
const KNOWN_PARTNER_KEY = 'sweetheart_known_partner_peer';

const PEER_ID_PREFIX = 'love-';

const BASE32_ALPHABET = '0123456789abcdefghjkmnpqrstvwxyz';

const PEER_ID_RANDOM_BYTES = 10;

function getRandomBytes(byteLength) {
  const bytes = new Uint8Array(byteLength);
  const cryptoObj = typeof window !== 'undefined' ? window.crypto : globalThis.crypto;
  cryptoObj.getRandomValues(bytes);
  return bytes;
}

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
    if (id && PEER_ID_REGEX.test(id)) return id;
  } catch {
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
  }
}

function getStoredKnownPartnerId() {
  try {
    if (typeof localStorage === 'undefined') return null;
    const id = localStorage.getItem(KNOWN_PARTNER_KEY);
    if (id && PEER_ID_REGEX.test(id)) return id;
  } catch {
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
  }
}

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

const WIRE_FIELDS_COMMON = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

const WIRE_FIELDS_BY_TABLE = {
  memories: [],
};

function wireFieldsFor(table) {
  return new Set([...WIRE_FIELDS_COMMON, ...(WIRE_FIELDS_BY_TABLE[table] || [])]);
}

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
    this.dialingPeerId = null;

    this._knownPartnerId = getStoredKnownPartnerId();
    this._admission = new Map();
    this._unknownAdmissions = [];
    this._slotKnown = false;
    this._slotSince = 0;
    this._slotProgressed = false;
    this._admissionWarnedAt = 0;

    this.authTimeoutTimer = null;
    this.connectOpenTimer = null;
    this.heartbeatTimer = null;
    this.lastPongAt = 0;

    this.connectionType = null;
    this.routeProbeTimer = null;
    this.routeProbeAttempts = 0;
    this._iceListener = null;
    this._icePeerConnection = null;
    this._routeFailed = false;

    this.decryptFailures = 0;

    this._outSessions = new Map();
    this._inSessions = new Map();

    this._lastIssuedStamp = 0;
    this._observedRemoteMax = 0;
    this._clockSkewWarned = false;

    this._hasRetriedUnavailableId = false;
    this.initPromise = null;
  }

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

  _currentState() {
    if (!this.isConnected) return 'disconnected';
    if (!this.isAuthorized) return 'handshaking';
    return this.isSyncing ? 'syncing' : 'authorized';
  }

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

  _emitFatal(code, error, state = 'error') {
    if (this.activeConnection || this.isConnected) {
      this._closeActiveConnection();
    }
    this.emit('status', { state, code, error });
  }

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

    const iceServers = buildIceServers();

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
          debug: 0,
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
        if (err?.type === 'unavailable-id') {
          if (!this._hasRetriedUnavailableId) {
            this._hasRetriedUnavailableId = true;
            setTimeout(() => {
              this._closeActiveConnection();
              try {
                this.peer?.destroy();
              } catch {
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

        if (this.isAuthorized && this.activeConnection?.open) {
          this._emitWarning('signalling_' + (err?.type || 'error'), msg, { errorType: err?.type });
          return;
        }

        if (this.activeConnection || this.isConnected) this._closeActiveConnection();
        this.emit('status', {
          state: 'error',
          code: err?.type || 'peer_error',
          error: msg,
          errorType: err?.type,
        });
      });

      this.peer.on('disconnected', () => {
        try {
          if (this.peer && !this.peer.destroyed) {
            this.peer.reconnect();
          }
        } catch {
        }
      });
    });

    return this.initPromise;
  }

  async connectToPartner(partnerPeerId) {
    const cleanId = (partnerPeerId || '').trim();
    if (!cleanId || !PEER_ID_REGEX.test(cleanId) || cleanId === this.myPeerId) {
      throw new Error('Invalid Partner Peer ID format');
    }

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

  _isKnownPeer(peerId) {
    if (!peerId) return false;
    return peerId === this.dialingPeerId || peerId === this._knownPartnerId;
  }

  _pruneAdmission(now) {
    for (const [peerId, entry] of this._admission) {
      if (now - entry.lastSeenAt > ADMISSION_ENTRY_TTL_MS) this._admission.delete(peerId);
    }
    while (this._admission.size > ADMISSION_MAX_TRACKED_PEERS) {
      const oldest = this._admission.keys().next().value;
      if (oldest === undefined) break;
      this._admission.delete(oldest);
    }
    this._unknownAdmissions = this._unknownAdmissions.filter(
      (t) => now - t < ADMISSION_FLOOD_WINDOW_MS
    );
  }

  _admitInbound(peerId, isKnown) {
    const now = Date.now();
    this._pruneAdmission(now);

    const entry = this._admission.get(peerId);
    if (entry && entry.blockedUntil > now) {
      return { allowed: false, reason: 'backoff' };
    }

    if (!isKnown && this._unknownAdmissions.length >= ADMISSION_FLOOD_MAX_UNKNOWN) {
      return { allowed: false, reason: 'flood' };
    }

    return { allowed: true };
  }

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

    this._admission.delete(peerId);
    this._admission.set(peerId, entry);
  }

  _noteAdmissionSuccess(peerId) {
    if (!peerId) return;
    this._admission.delete(peerId);
    this._knownPartnerId = peerId;
    setStoredKnownPartnerId(peerId);
  }

  _refuseConnection(conn, warningCode, warningText) {
    try {
      conn.close();
    } catch {
    }
    this._refuseWarn(warningCode, warningText);
  }

  _mayEvictIncumbent(conn) {
    if (!this.activeConnection || this.isAuthorized) return false;
    if (this._slotKnown) return false;
    if (this._isKnownPeer(conn.peer)) return true;
    if (this._slotProgressed) return false;
    return Date.now() - this._slotSince >= STRANGER_EVICT_AFTER_MS;
  }

  _setupConnection(conn, isInitiator) {
    if (!conn || typeof conn.peer !== 'string') return;
    if (this.activeConnection === conn) return;

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
      } else {
        const expectedPeer = this.dialingPeerId || existing.peer;
        if (conn.peer !== expectedPeer) {
          if (!this._mayEvictIncumbent(conn)) {
            this._refuseConnection(
              conn,
              'unknown_peer_rejected',
              'Someone else tried to connect while you were pairing. We said no.'
            );
            return;
          }
        } else if (this.myPeerId && this.myPeerId <= conn.peer) {
          try {
            conn.close();
          } catch {
          }
          return;
        }
      }
    }

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
    if (isInitiator) this.dialingPeerId = conn.peer;
    this.activeConnection = conn;
    this.decryptFailures = 0;
    this._routeFailed = false;
    this._slotKnown = isKnown;
    this._slotSince = Date.now();
    this._slotProgressed = false;

    this._startAuthTimeout(conn, isKnown);
    this._startConnectOpenTimeout(conn, isKnown);

    const handleOpen = async () => {
      if (this.activeConnection !== conn) return;
      this._clearConnectOpenTimeout();
      this.isConnected = true;

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

  _startHeartbeat() {
    this._clearHeartbeat();
    this.lastPongAt = Date.now();
    this.heartbeatTimer = setInterval(() => {
      this._heartbeatTick().catch(() => {
      });
    }, HEARTBEAT_INTERVAL_MS);
  }

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
      }
      this.activeConnection = null;
    }
  }

  closeConnection() {
    this._closeActiveConnection();
    this.emit('status', { state: 'disconnected', code: 'closed_locally' });
  }

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

  _startRouteProbe() {
    this._clearRouteProbe();
    this.routeProbeAttempts = 0;

    const pc = this.activeConnection?.peerConnection;
    if (pc && typeof pc.addEventListener === 'function') {
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
      }
    }
    this._iceListener = null;
    this._icePeerConnection = null;
  }

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

  async _sendAuthChallenge() {
    if (!this.activeConnection || !this.cryptoKey) return;
    const nonce = generateSecureNonce(16);
    this.pendingChallengeNonce = nonce;
    await this._send({ type: 'CHALLENGE', nonce });
  }

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

    if (!this.cryptoKey) return;

    let decrypted;
    try {
      decrypted = await decryptJSON(ciphertext, iv, this.cryptoKey);
    } catch {
      this._handleDecryptFailure();
      return;
    }

    this.decryptFailures = 0;
    this.lastPongAt = Date.now();
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
        }
        break;

      case 'PONG':
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

  async _onAuthorized() {
    this._clearAuthTimeout();
    this._clearConnectOpenTimeout();
    this.isAuthorized = true;
    this.dialingPeerId = null;
    this.lastPongAt = Date.now();

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

  _touchSession(session) {
    if (!session) return;
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
    }
  }

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
        'Could not compare notes with your partner. Try again.'
      );
      return;
    }

    if (requests.length === 0) {
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

    if (decrypted.wantReciprocal === true && this._outSessions.size === 0) {
      await this.syncNow({ wantReciprocal: false });
    }
  }

  async _sendSyncComplete(sessionId, applied, rejected, unverifiable = 0) {
    try {
      await this._send({ type: 'SYNC_COMPLETE', sessionId, applied, rejected, unverifiable });
    } catch {
    }
  }

  async diffAgainstLocal(remoteManifest) {
    if (!remoteManifest || typeof remoteManifest !== 'object') return [];
    return await this._diffManifest(remoteManifest);
  }

  async _diffManifest(remoteManifest) {
    const localManifest = await db.getManifest();
    const requests = [];
    const now = Date.now();
    let sawFutureTimestamp = false;

    for (const [table, remoteItems] of Object.entries(remoteManifest)) {
      if (!ALLOWED_TABLES.has(table) || !Array.isArray(remoteItems)) continue;
      if (remoteItems.length > MAX_RECORDS_PER_TABLE) continue;

      const localMap = new Map(
        (localManifest[table] || []).map((i) => [i.id, { updatedAt: i.updatedAt, deleted: i.deleted === true }])
      );

      for (const rItem of remoteItems) {
        if (!rItem || typeof rItem.id !== 'string' || rItem.id.length > 128) continue;

        if (!Number.isFinite(rItem.updatedAt) || rItem.updatedAt < 0) continue;
        if (rItem.updatedAt > now + MAX_CLOCK_SKEW_MS) {
          sawFutureTimestamp = true;
          continue;
        }

        const local = localMap.get(rItem.id);

        const wantsRemote =
          local === undefined ||
          rItem.updatedAt > local.updatedAt ||
          (rItem.updatedAt === local.updatedAt && rItem.deleted === true && !local.deleted);

        if (wantsRemote) {
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

  _estimateWireBytes(wire) {
    let bytes = 128;
    for (const [field, value] of Object.entries(wire)) {
      bytes += field.length + 8;
      if (typeof value === 'string') bytes += value.length;
      else bytes += 16;
    }
    return bytes;
  }

  _validateWireRecord(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) return { ok: false, code: 'shape' };
    if (typeof data.id !== 'string' || data.id.length < 1 || data.id.length > 128) {
      return { ok: false, code: 'bad_id' };
    }
    if (!Number.isFinite(data.updatedAt) || data.updatedAt < 0) {
      return { ok: false, code: 'bad_timestamp' };
    }
    if (data.updatedAt > Date.now() + MAX_CLOCK_SKEW_MS) {
      return { ok: false, code: 'future_timestamp' };
    }
    if (typeof data.deleted !== 'boolean') return { ok: false, code: 'bad_tombstone' };
    if (data.v !== RECORD_SCHEMA_VERSION) return { ok: false, code: 'bad_version' };
    return { ok: true };
  }

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

  async _verifyRecordIntegrity(row, table) {
    if (!this.cryptoKey) return { ok: false, code: 'locked' };
    if (!recordHasAuthenticatedHeader(row)) {
      return { ok: false, code: 'unauthenticated' };
    }
    try {
      const plain = await decryptRecord(row, this.cryptoKey, { table });
      if (plain && plain._binaryTampered === true) {
        return { ok: false, code: 'binary_tampered' };
      }
      if (plain && plain._tableTampered === true) {
        return { ok: false, code: 'table_mismatch' };
      }
      if (plain && plain._headerTampered === true) {
        return { ok: false, code: 'header_tampered' };
      }
      if (plain && (plain._binaryUnverified === true || plain._tableUnverified === true)) {
        return { ok: true, unverified: true };
      }
      return { ok: true, unverified: false };
    } catch {
      return { ok: false, code: 'undecryptable' };
    }
  }

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

      const integrity = await this._verifyRecordIntegrity(row, item.table);
      if (!integrity.ok) {
        note(integrity.code);
        continue;
      }

      staged.push({ table: item.table, row, unverifiedBinding: integrity.unverified === true });
    }

    if (reasons.has('future_timestamp')) this._warnClockSkew();
    return { staged, rejected, reasons };
  }

  _incomingWins(existing, incoming) {
    if (!existing) return true;

    const localAt = Number.isFinite(existing.updatedAt) ? existing.updatedAt : -1;
    const remoteAt = incoming.updatedAt;

    if (remoteAt > localAt) return true;
    if (remoteAt < localAt) return false;

    const localDeleted = existing.deleted === true;
    const remoteDeleted = incoming.deleted === true;
    if (localDeleted !== remoteDeleted) return remoteDeleted;

    return this._fingerprint(incoming) > this._fingerprint(existing);
  }

  _fingerprint(row) {
    const parts = [String(row.v || RECORD_SCHEMA_VERSION), row.ciphertext || '', row.iv || ''];
    return parts.join('|');
  }

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
        if (!recordHasAuthenticatedHeader(row)) {
          unverifiable++;
          continue;
        }
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

  async broadcastLiveRecord(table, record) {
    if (!record || typeof record !== 'object' || typeof record.id !== 'string') return false;
    if (!ALLOWED_TABLES.has(table)) return false;

    try {
      this.emit('local-record', { table, id: record.id });
    } catch {
    }

    if (!this.isConnected || !this.isAuthorized) return false;

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

  getSyncSafeTimestamp() {
    const now = Date.now();

    const ceiling = now + MAX_CLOCK_SKEW_MS;

    let floor = 0;
    try {
      if (typeof localStorage !== 'undefined') {
        const raw = localStorage.getItem(SYNC_CLOCK_KEY);
        const parsed = Number(raw);
        if (Number.isFinite(parsed) && parsed > 0) floor = parsed;
      }
    } catch {
    }

    if (floor > ceiling) {
      floor = now;
      this._emitWarning(
        'clock_rolled_back',
        "This phone's date looks like it was changed. We have set syncing back to the current time."
      );
    }
    const remoteFloor = Math.min(this._observedRemoteMax, ceiling);

    const next = Math.max(now, floor + 1, remoteFloor + 1, this._lastIssuedStamp + 1);
    this._lastIssuedStamp = next;

    try {
      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(SYNC_CLOCK_KEY, String(next));
      }
    } catch {
    }

    return next;
  }

  disconnect() {
    this.closeConnection();
  }

  releaseTransport() {
    this._closeActiveConnection();
    try {
      this.peer?.destroy();
    } catch {
    }
    this.peer = null;
    this.myPeerId = null;
    this.initPromise = null;
  }

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
  window.addEventListener('pagehide', (event) => {
    if (event.persisted) return;
    try {
      peerSync.releaseTransport();
    } catch {
    }
  });

  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible') return;

      if (peerSync.peer && !peerSync.peer.destroyed && peerSync.peer.disconnected) {
        try {
          peerSync.peer.reconnect();
        } catch {
        }
      }

      if (peerSync.isAuthorized) {
        peerSync._heartbeatTick().catch(() => {});
      }
    });
  }
}

export default peerSync;
