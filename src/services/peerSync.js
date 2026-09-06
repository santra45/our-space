/**
 * src/services/peerSync.js
 * Security-Hardened P2P WebRTC Data Replication Manager using PeerJS
 * - Zero-knowledge mutual challenge-response with cryptographic nonces
 * - 30-second authentication timeout and state reset
 * - Strict message type and database table allowlists
 * - Strict record schema validation and payload size limits
 * - No plaintext or sensitive data logging
 */
import Peer from 'peerjs';
import { encryptJSON, decryptJSON, generateSecureNonce } from './crypto';
import { PEER_ID_REGEX } from '../utils/invite';
import db from '../db';

const MAX_CIPHERTEXT_LENGTH = 30 * 1024 * 1024; // 30 MB max payload limit
const AUTH_TIMEOUT_MS = 30000; // 30s timeout
const LOCAL_PEER_ID_KEY = 'sweetheart_device_peer_id';

function getStoredDevicePeerId() {
  try {
    if (typeof localStorage === 'undefined') return null;
    const id = localStorage.getItem(LOCAL_PEER_ID_KEY);
    if (id && PEER_ID_REGEX.test(id)) return id;
  } catch {}
  return null;
}

function setStoredDevicePeerId(id) {
  try {
    if (typeof localStorage === 'undefined') return;
    if (id && PEER_ID_REGEX.test(id)) {
      localStorage.setItem(LOCAL_PEER_ID_KEY, id);
    }
  } catch {}
}

const ALLOWED_TABLES = new Set([
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
]);

const ALLOWED_MESSAGE_TYPES = new Set([
  'CHALLENGE',
  'CHALLENGE_RESPONSE',
  'CHALLENGE_ACK',
  'SYNC_MANIFEST',
  'SYNC_REQUEST_RECORDS',
  'SYNC_RECORDS_BATCH',
  'LIVE_RECORD_BROADCAST',
  'SYNC_CONFIG',
]);

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
    this.authTimeoutTimer = null;
    this.connectionType = null; // 'direct' | 'relayed' | null
    this._hasRetriedUnavailableId = false;
  }

  on(event, callback) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event).push(callback);
  }

  emit(event, payload) {
    const handlers = this.listeners.get(event) || [];
    handlers.forEach((fn) => fn(payload));
  }

  /**
   * Initialize local WebRTC Peer
   * @param {CryptoKey} cryptoKey - The derived vault key for auth & encryption
   * @param {string} [customId] - Optional custom Peer ID
   */
  async init(cryptoKey, customId = null) {
    this.cryptoKey = cryptoKey;

    if (this.peer && !this.peer.destroyed) {
      return this.myPeerId;
    }

    if (customId && !PEER_ID_REGEX.test(customId)) {
      throw new Error('Invalid custom Peer ID format');
    }

    const iceServers = [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
      { urls: 'stun:global.stun.twilio.com:3478' },
    ];

    return new Promise((resolve, reject) => {
      // Check stored device ID or generate clean cryptographically random 12-char peer ID
      let peerId = customId;
      if (!peerId) {
        peerId = getStoredDevicePeerId();
      }
      if (!peerId) {
        peerId = 'love-' + generateSecureNonce(6).toLowerCase().replace(/[^a-z0-9]/g, 'x');
      }

      try {
        this.peer = new Peer(peerId, {
          config: { iceServers },
          debug: 0, // Disable internal PeerJS logging
        });
      } catch (err) {
        return reject(new Error('Failed to create WebRTC peer instance'));
      }

      this.peer.on('open', (id) => {
        this.myPeerId = id;
        this._hasRetriedUnavailableId = false;
        setStoredDevicePeerId(id);
        this.emit('status', { state: 'ready', peerId: id });
        resolve(id);
      });

      this.peer.on('connection', (conn) => {
        this._handleIncomingConnection(conn);
      });

      this.peer.on('error', (err) => {
        // If previous socket didn't close cleanly on reload, wait briefly and retry once with same ID
        if (err?.type === 'unavailable-id') {
          if (!this._hasRetriedUnavailableId) {
            this._hasRetriedUnavailableId = true;
            setTimeout(() => {
              try { this.peer?.destroy(); } catch {}
              this.peer = null;
              this.init(cryptoKey, peerId).then(resolve).catch(reject);
            }, 1200);
            return;
          }
          this._hasRetriedUnavailableId = false;
          const freshId = 'love-' + generateSecureNonce(6).toLowerCase().replace(/[^a-z0-9]/g, 'x');
          setStoredDevicePeerId(freshId);
          this.init(cryptoKey, freshId).then(resolve).catch(reject);
          return;
        }

        let msg = 'WebRTC peer connection error';
        if (err?.type === 'peer-unavailable') {
          msg = 'Partner device not found or offline. Ensure your partner has the app open on their screen.';
        } else if (err?.type === 'network') {
          msg = 'Network connection issue with signalling server.';
        }
        this.emit('status', { state: 'error', error: msg, errorType: err?.type });
      });

      this.peer.on('disconnected', () => {
        this._resetAuthState();
        try {
          this.peer?.reconnect();
        } catch {
          // safe fail
        }
      });
    });
  }

  /**
   * Connect to partner's Peer ID with strict input validation
   */
  connectToPartner(partnerPeerId) {
    if (!this.peer || this.peer.destroyed) {
      throw new Error('Peer not initialized');
    }

    const cleanId = (partnerPeerId || '').trim();
    if (!cleanId || !PEER_ID_REGEX.test(cleanId) || cleanId === this.myPeerId) {
      throw new Error('Invalid Partner Peer ID format');
    }

    this.emit('status', { state: 'connecting', partnerId: cleanId });

    const conn = this.peer.connect(cleanId, {
      reliable: true,
    });

    this._setupConnection(conn, true);
  }

  _handleIncomingConnection(conn) {
    this._setupConnection(conn, false);
  }

  _setupConnection(conn, isInitiator) {
    if (this.activeConnection && this.activeConnection !== conn) {
      try {
        this.activeConnection.close();
      } catch {
        // ignore
      }
    }

    this._resetAuthState();
    this.activeConnection = conn;

    const handleOpen = async () => {
      this.isConnected = true;
      this.emit('status', { state: 'connected', partnerId: conn.peer });

      // Start strict 30-second authentication timeout
      this._startAuthTimeout();

      if (isInitiator) {
        await this._sendAuthChallenge();
      }
    };

    if (conn.open) {
      handleOpen();
    } else {
      conn.on('open', handleOpen);
    }

    conn.on('data', async (data) => {
      try {
        await this._handleMessage(data);
      } catch {
        // Suppress and drop malformed/untrusted frames
      }
    });

    conn.on('close', () => {
      if (this.activeConnection === conn) {
        this._resetAuthState();
        this.isConnected = false;
        this.activeConnection = null;
        this.emit('status', { state: 'disconnected' });
      }
    });

    conn.on('error', () => {
      if (this.activeConnection === conn) {
        this._resetAuthState();
        this.isConnected = false;
        this.activeConnection = null;
        this.emit('status', { state: 'error', error: 'Data channel error' });
      }
    });
  }

  _startAuthTimeout() {
    this._clearAuthTimeout();
    this.authTimeoutTimer = setTimeout(() => {
      if (!this.isAuthorized) {
        this.emit('status', { state: 'auth_failed', error: 'Authentication timed out after 30 seconds' });
        this.disconnect();
      }
    }, AUTH_TIMEOUT_MS);
  }

  _clearAuthTimeout() {
    if (this.authTimeoutTimer) {
      clearTimeout(this.authTimeoutTimer);
      this.authTimeoutTimer = null;
    }
  }

  _resetAuthState() {
    this._clearAuthTimeout();
    this.pendingChallengeNonce = null;
    this.isAuthorized = false;
    this.isSyncing = false;
    this.connectionType = null;
  }

  /**
   * Inspects WebRTC active candidate pair to determine if connection is direct P2P or relayed
   * @returns {Promise<'direct' | 'relayed' | null>}
   */
  async checkConnectionType() {
    const pc = this.activeConnection?.peerConnection;
    if (!pc || typeof pc.getStats !== 'function') {
      return this.isConnected ? 'direct' : null;
    }

    try {
      const stats = await pc.getStats();
      let isRelayed = false;
      let hasPair = false;

      stats.forEach((report) => {
        if (
          report.type === 'candidate-pair' &&
          (report.selected || report.nominated || (report.state === 'succeeded' && report.bytesSent > 0))
        ) {
          hasPair = true;
          const local = stats.get(report.localCandidateId);
          const remote = stats.get(report.remoteCandidateId);
          if (local?.candidateType === 'relay' || remote?.candidateType === 'relay') {
            isRelayed = true;
          }
        }
      });

      if (hasPair) {
        return isRelayed ? 'relayed' : 'direct';
      }
      return 'direct';
    } catch {
      return 'direct';
    }
  }

  /**
   * Initiator step: Send cryptographically secure random challenge nonce
   */
  async _sendAuthChallenge() {
    if (!this.activeConnection || !this.cryptoKey) return;
    const nonce = generateSecureNonce(16);
    this.pendingChallengeNonce = nonce;
    const challenge = await encryptJSON({ type: 'CHALLENGE', nonce }, this.cryptoKey);
    this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload: challenge });
  }

  async _handleMessage(msg) {
    if (
      !msg ||
      typeof msg !== 'object' ||
      msg.protocol !== 'SWEETHEART_V1' ||
      !msg.payload ||
      typeof msg.payload !== 'object'
    ) {
      return;
    }

    const { ciphertext, iv } = msg.payload;
    if (
      typeof ciphertext !== 'string' ||
      typeof iv !== 'string' ||
      ciphertext.length > MAX_CIPHERTEXT_LENGTH
    ) {
      return; // Drop oversized or invalid payloads
    }

    let decrypted;
    try {
      decrypted = await decryptJSON(ciphertext, iv, this.cryptoKey);
    } catch {
      // Decryption failed -> Mismatched passphrase or corrupted payload
      this.emit('status', {
        state: 'auth_failed',
        error: 'Passphrase mismatch! Please verify you both entered the exact same secret passphrase.',
      });
      this.disconnect();
      return;
    }

    if (!decrypted || typeof decrypted !== 'object' || !ALLOWED_MESSAGE_TYPES.has(decrypted.type)) {
      return; // Reject unallowed message types
    }

    // Gate: Drop non-auth messages if connection is not yet authorized
    const isAuthMsg =
      decrypted.type === 'CHALLENGE' ||
      decrypted.type === 'CHALLENGE_RESPONSE' ||
      decrypted.type === 'CHALLENGE_ACK';

    if (!this.isAuthorized && !isAuthMsg) {
      return;
    }

    switch (decrypted.type) {
      case 'CHALLENGE': {
        // Receiver receives challenge: generate counter-challenge nonce for mutual authentication
        if (typeof decrypted.nonce !== 'string' || decrypted.nonce.length < 16) {
          this.disconnect();
          return;
        }

        const counterNonce = generateSecureNonce(16);
        this.pendingChallengeNonce = counterNonce;

        const response = await encryptJSON(
          {
            type: 'CHALLENGE_RESPONSE',
            echo: decrypted.nonce,
            counterNonce,
          },
          this.cryptoKey
        );
        this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload: response });
        break;
      }

      case 'CHALLENGE_RESPONSE': {
        // Initiator verifies receiver's echo matches pending challenge
        if (
          !this.pendingChallengeNonce ||
          typeof decrypted.echo !== 'string' ||
          decrypted.echo !== this.pendingChallengeNonce ||
          typeof decrypted.counterNonce !== 'string'
        ) {
          // Replay or mismatch detected
          this.disconnect();
          return;
        }

        // Invalidate used nonce
        this.pendingChallengeNonce = null;

        // Respond to receiver's counter-challenge
        const ack = await encryptJSON(
          {
            type: 'CHALLENGE_ACK',
            echo: decrypted.counterNonce,
          },
          this.cryptoKey
        );
        this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload: ack });

        // Initiator is authenticated!
        this._clearAuthTimeout();
        this.isAuthorized = true;
        this.connectionType = await this.checkConnectionType();
        this.emit('status', {
          state: 'authorized',
          partnerId: this.activeConnection?.peer,
          connectionType: this.connectionType,
          isDirect: this.connectionType === 'direct',
        });
        await this.syncNow();
        break;
      }

      case 'CHALLENGE_ACK': {
        // Receiver verifies initiator's echo
        if (
          !this.pendingChallengeNonce ||
          typeof decrypted.echo !== 'string' ||
          decrypted.echo !== this.pendingChallengeNonce
        ) {
          this.disconnect();
          return;
        }

        // Invalidate used nonce
        this.pendingChallengeNonce = null;

        // Receiver is authenticated!
        this._clearAuthTimeout();
        this.isAuthorized = true;
        this.connectionType = await this.checkConnectionType();
        this.emit('status', {
          state: 'authorized',
          partnerId: this.activeConnection?.peer,
          connectionType: this.connectionType,
          isDirect: this.connectionType === 'direct',
        });
        break;
      }

      case 'SYNC_CONFIG': {
        if (!this.isAuthorized) return;
        this.emit('config-synced', decrypted.config);
        break;
      }

      case 'SYNC_MANIFEST': {
        if (!this.isAuthorized) return;
        await this._processRemoteManifest(decrypted.manifest);
        break;
      }

      case 'SYNC_REQUEST_RECORDS': {
        if (!this.isAuthorized) return;
        await this._sendRequestedRecords(decrypted.requests);
        break;
      }

      case 'SYNC_RECORDS_BATCH': {
        if (!this.isAuthorized) return;
        await this._applyRemoteRecords(decrypted.records);
        break;
      }

      case 'LIVE_RECORD_BROADCAST': {
        if (!this.isAuthorized) return;
        await this._applySingleLiveRecord(decrypted.record);
        break;
      }

      default:
        break;
    }
  }

  /**
   * Sends local database manifest of record IDs and timestamps
   */
  async syncNow() {
    if (!this.isConnected || !this.isAuthorized) return;
    this.isSyncing = true;
    this.emit('status', { state: 'syncing' });

    const manifest = await db.getManifest();
    const payload = await encryptJSON({ type: 'SYNC_MANIFEST', manifest }, this.cryptoKey);
    this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _processRemoteManifest(remoteManifest) {
    if (!this.isAuthorized || !remoteManifest || typeof remoteManifest !== 'object') return;

    const localManifest = await db.getManifest();
    const requests = [];

    for (const [table, remoteItems] of Object.entries(remoteManifest)) {
      if (!ALLOWED_TABLES.has(table) || !Array.isArray(remoteItems)) continue;

      const localMap = new Map((localManifest[table] || []).map((i) => [i.id, i.updatedAt]));

      for (const rItem of remoteItems) {
        if (!rItem || typeof rItem.id !== 'string' || typeof rItem.updatedAt !== 'number') continue;
        const localUpdatedAt = localMap.get(rItem.id);
        if (!localUpdatedAt || rItem.updatedAt > localUpdatedAt) {
          requests.push({ table, id: rItem.id });
        }
      }
    }

    if (requests.length > 0) {
      const payload = await encryptJSON({ type: 'SYNC_REQUEST_RECORDS', requests }, this.cryptoKey);
      this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload });
    } else {
      this.isSyncing = false;
      this.emit('status', { state: 'synced', message: 'All memories up to date!' });
    }
  }

  async _sendRequestedRecords(requests) {
    // Unauthenticated peers must NEVER receive records
    if (!this.isConnected || !this.isAuthorized || !Array.isArray(requests)) return;

    const records = [];
    for (const req of requests) {
      if (!req || typeof req !== 'object' || !ALLOWED_TABLES.has(req.table) || typeof req.id !== 'string') {
        continue;
      }

      const item = await db.table(req.table).get(req.id);
      if (item) {
        if (req.table === 'memories' && item.imageBlob) {
          const clone = { ...item };
          let binary = '';
          const bytes = new Uint8Array(clone.imageBlob);
          for (let i = 0; i < bytes.byteLength; i++) {
            binary += String.fromCharCode(bytes[i]);
          }
          clone.imageBlobBase64 = window.btoa(binary);
          delete clone.imageBlob;
          records.push({ table: req.table, data: clone });
        } else {
          records.push({ table: req.table, data: item });
        }
      }
    }

    const payload = await encryptJSON({ type: 'SYNC_RECORDS_BATCH', records }, this.cryptoKey);
    this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _applyRemoteRecords(records) {
    if (!this.isAuthorized || !Array.isArray(records)) return;

    const validRecords = [];
    for (const item of records) {
      if (!item || !ALLOWED_TABLES.has(item.table) || !this._isValidRecordSchema(item.data)) {
        continue;
      }
      validRecords.push(item);
    }

    await db.transaction('rw', db.tables, async () => {
      for (const item of validRecords) {
        const data = item.data;
        if (item.table === 'memories' && typeof data.imageBlobBase64 === 'string') {
          try {
            const binary = window.atob(data.imageBlobBase64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) {
              bytes[i] = binary.charCodeAt(i);
            }
            data.imageBlob = bytes;
            delete data.imageBlobBase64;
          } catch {
            continue;
          }
        }
        await db.table(item.table).put(data);
      }
    });

    this.isSyncing = false;
    this.emit('status', { state: 'synced', message: `Synced ${validRecords.length} updates from partner!` });
    this.emit('data-updated', { count: validRecords.length });
  }

  /**
   * Real-time broadcast: push single item when partner is online
   */
  async broadcastLiveRecord(table, record) {
    if (!this.isConnected || !this.isAuthorized || !ALLOWED_TABLES.has(table)) return;

    let payloadData = record;
    if (table === 'memories' && record.imageBlob) {
      const clone = { ...record };
      let binary = '';
      const bytes = new Uint8Array(clone.imageBlob);
      for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      clone.imageBlobBase64 = window.btoa(binary);
      delete clone.imageBlob;
      payloadData = clone;
    }

    const payload = await encryptJSON(
      { type: 'LIVE_RECORD_BROADCAST', record: { table, data: payloadData } },
      this.cryptoKey
    );
    this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _applySingleLiveRecord(record) {
    if (
      !this.isAuthorized ||
      !record ||
      !ALLOWED_TABLES.has(record.table) ||
      !this._isValidRecordSchema(record.data)
    ) {
      return;
    }

    const { table, data } = record;
    if (table === 'memories' && typeof data.imageBlobBase64 === 'string') {
      try {
        const binary = window.atob(data.imageBlobBase64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }
        data.imageBlob = bytes;
        delete data.imageBlobBase64;
      } catch {
        return;
      }
    }

    await db.table(table).put(data);
    this.emit('data-updated', { single: true, table });
  }

  /**
   * Validate record structure before writing into IndexedDB
   */
  _isValidRecordSchema(data) {
    if (!data || typeof data !== 'object') return false;
    if (typeof data.id !== 'string' || data.id.length < 1 || data.id.length > 128) return false;
    if (typeof data.updatedAt !== 'number') return false;
    if (typeof data.deleted !== 'boolean') return false;
    return true;
  }

  /**
   * Syncs relationship anniversary start date & couple names across devices
   */
  async syncVaultConfig(config) {
    if (!this.isConnected || !this.isAuthorized || !this.cryptoKey) return;
    try {
      const payload = await encryptJSON(
        {
          type: 'SYNC_CONFIG',
          config: {
            coupleNames: config?.coupleNames || '',
            startDate: config?.startDate || '',
            updatedAt: config?.updatedAt || Date.now(),
          },
        },
        this.cryptoKey
      );
      this.activeConnection?.send({ protocol: 'SWEETHEART_V1', payload });
    } catch {
      // safe fail
    }
  }

  /**
   * Full disconnect and state teardown
   */
  disconnect() {
    this._resetAuthState();
    try {
      this.activeConnection?.close();
    } catch {
      // ignore
    }
    try {
      this.peer?.destroy();
    } catch {
      // ignore
    }
    this.peer = null;
    this.activeConnection = null;
    this.isConnected = false;
    this.emit('status', { state: 'disconnected' });
  }
}

export const peerSync = new PeerSyncManager();

// Clean up WebRTC signaling socket on browser tab close or refresh to free peer ID immediately
if (typeof window !== 'undefined') {
  const cleanTeardown = () => {
    try {
      peerSync.activeConnection?.close();
      peerSync.peer?.destroy();
    } catch {}
  };
  window.addEventListener('beforeunload', cleanTeardown);
  window.addEventListener('pagehide', cleanTeardown);
}

export default peerSync;
