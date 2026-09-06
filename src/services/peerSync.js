/**
 * src/services/peerSync.js
 * Mobile-First P2P WebRTC Data Replication Manager using PeerJS
 */
import Peer from 'peerjs';
import { encryptJSON, decryptJSON } from './crypto';
import db from '../db';

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
   * Initialize local WebRTC Peer on Android
   * @param {CryptoKey} cryptoKey - The derived vault key for auth & encryption
   * @param {string} [customId] - Optional custom Peer ID
   */
  async init(cryptoKey, customId = null) {
    this.cryptoKey = cryptoKey;

    if (this.peer && !this.peer.destroyed) {
      return this.myPeerId;
    }

    const iceServers = [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
      { urls: 'stun:global.stun.twilio.com:3478' },
    ];

    return new Promise((resolve, reject) => {
      // Create clean 8-character alphanumeric peer ID (e.g. "love-8f2a1b9c")
      const peerId = customId || 'love-' + Math.random().toString(36).substring(2, 8);
      
      try {
        this.peer = new Peer(peerId, {
          config: { iceServers },
          debug: 1,
        });
      } catch (err) {
        return reject(err);
      }

      this.peer.on('open', (id) => {
        this.myPeerId = id;
        this.emit('status', { state: 'ready', peerId: id });
        resolve(id);
      });

      this.peer.on('connection', (conn) => {
        this._handleIncomingConnection(conn);
      });

      this.peer.on('error', (err) => {
        console.error('[WebRTC Peer Error]', err);
        this.emit('status', { state: 'error', error: err.message });
      });

      this.peer.on('disconnected', () => {
        // Mobile reconnect handler when switching between Wi-Fi & 4G/5G
        try {
          this.peer.reconnect();
        } catch (e) {
          console.warn('Peer reconnect attempted', e);
        }
      });
    });
  }

  /**
   * Connect to partner's Peer ID
   */
  connectToPartner(partnerPeerId) {
    if (!this.peer || this.peer.destroyed) {
      throw new Error('Peer not initialized');
    }

    const cleanId = partnerPeerId.trim();
    if (!cleanId || cleanId === this.myPeerId) {
      throw new Error('Invalid Partner Peer ID');
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
    if (this.activeConnection) {
      try {
        this.activeConnection.close();
      } catch (e) {
        // ignore
      }
    }

    this.activeConnection = conn;

    conn.on('open', async () => {
      this.isConnected = true;
      this.emit('status', { state: 'connected', partnerId: conn.peer });

      if (isInitiator) {
        // Send Zero-Knowledge Auth Challenge to partner
        await this._sendAuthChallenge();
      }
    });

    conn.on('data', async (data) => {
      try {
        await this._handleMessage(data);
      } catch (err) {
        console.error('[WebRTC Message Handle Error]', err);
      }
    });

    conn.on('close', () => {
      this.isConnected = false;
      this.isAuthorized = false;
      this.isSyncing = false;
      this.emit('status', { state: 'disconnected' });
    });

    conn.on('error', (err) => {
      console.error('[WebRTC Conn Error]', err);
      this.emit('status', { state: 'error', error: err.message });
    });
  }

  /**
   * Zero-Knowledge Challenge: send encrypted timestamp nonce
   */
  async _sendAuthChallenge() {
    if (!this.activeConnection || !this.cryptoKey) return;
    const nonce = 'auth-' + Date.now() + '-' + Math.random();
    const challenge = await encryptJSON({ type: 'CHALLENGE', nonce }, this.cryptoKey);
    this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload: challenge });
  }

  async _handleMessage(msg) {
    if (!msg || msg.protocol !== 'SWEETHEART_V1' || !msg.payload) return;

    let decrypted;
    try {
      decrypted = await decryptJSON(msg.payload.ciphertext, msg.payload.iv, this.cryptoKey);
    } catch {
      // Decryption failed -> partner has mismatched passphrase
      this.emit('status', { 
        state: 'auth_failed', 
        error: 'Passphrase mismatch! Please make sure you both typed the exact same secret passphrase.' 
      });
      this.activeConnection?.close();
      return;
    }

    switch (decrypted.type) {
      case 'CHALLENGE': {
        const response = await encryptJSON(
          { type: 'CHALLENGE_RESPONSE', echo: decrypted.nonce },
          this.cryptoKey
        );
        this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload: response });
        break;
      }

      case 'CHALLENGE_RESPONSE': {
        this.isAuthorized = true;
        this.emit('status', { state: 'authorized' });
        // Trigger bidirectional differential sync
        await this.syncNow();
        break;
      }

      case 'SYNC_MANIFEST': {
        this.isAuthorized = true;
        this.emit('status', { state: 'authorized' });
        await this._processRemoteManifest(decrypted.manifest);
        break;
      }

      case 'SYNC_REQUEST_RECORDS': {
        await this._sendRequestedRecords(decrypted.requests);
        break;
      }

      case 'SYNC_RECORDS_BATCH': {
        await this._applyRemoteRecords(decrypted.records);
        break;
      }

      case 'LIVE_RECORD_BROADCAST': {
        await this._applySingleLiveRecord(decrypted.record);
        break;
      }

      default:
        console.warn('Unknown message type:', decrypted.type);
    }
  }

  /**
   * Triggers a sync by sending our local manifest to partner
   */
  async syncNow() {
    if (!this.isConnected || !this.isAuthorized) return;
    this.isSyncing = true;
    this.emit('status', { state: 'syncing' });

    const manifest = await db.getManifest();
    const payload = await encryptJSON({ type: 'SYNC_MANIFEST', manifest }, this.cryptoKey);
    this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _processRemoteManifest(remoteManifest) {
    const localManifest = await db.getManifest();
    const requests = [];

    // Find items that remote has newer or that local doesn't have
    for (const [table, remoteItems] of Object.entries(remoteManifest)) {
      const localMap = new Map((localManifest[table] || []).map((i) => [i.id, i.updatedAt]));

      for (const rItem of remoteItems) {
        const localUpdatedAt = localMap.get(rItem.id);
        if (!localUpdatedAt || rItem.updatedAt > localUpdatedAt) {
          requests.push({ table, id: rItem.id });
        }
      }
    }

    if (requests.length > 0) {
      const payload = await encryptJSON({ type: 'SYNC_REQUEST_RECORDS', requests }, this.cryptoKey);
      this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload });
    } else {
      this.isSyncing = false;
      this.emit('status', { state: 'synced', message: 'All memories up to date!' });
    }
  }

  async _sendRequestedRecords(requests) {
    const records = [];
    for (const req of requests) {
      const item = await db.table(req.table).get(req.id);
      if (item) {
        // Convert Uint8Array to base64 for JSON serialization if memory item
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
    this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _applyRemoteRecords(records) {
    await db.transaction('rw', db.tables, async () => {
      for (const item of records) {
        const data = item.data;
        if (item.table === 'memories' && data.imageBlobBase64) {
          const binary = window.atob(data.imageBlobBase64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
          }
          data.imageBlob = bytes;
          delete data.imageBlobBase64;
        }
        await db.table(item.table).put(data);
      }
    });

    this.isSyncing = false;
    this.emit('status', { state: 'synced', message: `Synced ${records.length} updates from partner!` });
    this.emit('data-updated', { count: records.length });
  }

  /**
   * Real-time broadcast: push single item when partner is online
   */
  async broadcastLiveRecord(table, record) {
    if (!this.isConnected || !this.isAuthorized) return;

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
    this.activeConnection.send({ protocol: 'SWEETHEART_V1', payload });
  }

  async _applySingleLiveRecord({ table, data }) {
    if (table === 'memories' && data.imageBlobBase64) {
      const binary = window.atob(data.imageBlobBase64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      data.imageBlob = bytes;
      delete data.imageBlobBase64;
    }

    await db.table(table).put(data);
    this.emit('data-updated', { single: true, table });
  }

  disconnect() {
    this.activeConnection?.close();
    this.peer?.destroy();
    this.peer = null;
    this.activeConnection = null;
    this.isConnected = false;
    this.isAuthorized = false;
    this.isSyncing = false;
    this.emit('status', { state: 'disconnected' });
  }
}

export const peerSync = new PeerSyncManager();
export default peerSync;
