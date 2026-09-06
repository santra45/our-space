/**
 * src/context/SyncContext.jsx
 * Connects peerSync lifecycle to React state and monitors URL hash for auto-pairing links
 */
import React, { createContext, useContext, useState, useEffect } from 'react';
import peerSync from '../services/peerSync';
import { useVault } from './VaultContext';

const SyncContext = createContext(null);

export function SyncProvider({ children }) {
  const { cryptoKey, isUnlocked } = useVault();
  const [myPeerId, setMyPeerId] = useState(null);
  const [partnerId, setPartnerId] = useState(null);
  const [syncStatus, setSyncStatus] = useState({ state: 'disconnected' });
  const [lastSyncNotice, setLastSyncNotice] = useState(null);

  // Initialize peer when vault is unlocked
  useEffect(() => {
    if (!isUnlocked || !cryptoKey) {
      peerSync.disconnect();
      setMyPeerId(null);
      setPartnerId(null);
      setSyncStatus({ state: 'disconnected' });
      return;
    }

    let isMounted = true;

    // Listen to PeerSync events
    peerSync.on('status', (status) => {
      if (!isMounted) return;
      setSyncStatus(status);
      if (status.peerId) setMyPeerId(status.peerId);
      if (status.partnerId) setPartnerId(status.partnerId);
      if (status.message) setLastSyncNotice(status.message);
    });

    peerSync.on('data-updated', (data) => {
      if (!isMounted) return;
      setLastSyncNotice(`Synced ${data.count || 1} new item(s) from partner 💕`);
      setTimeout(() => setLastSyncNotice(null), 4000);
    });

const PEER_ID_REGEX = /^[a-zA-Z0-9_-]{4,64}$/;

    // Start peer
    peerSync.init(cryptoKey).then((id) => {
      if (!isMounted) return;
      setMyPeerId(id);

      // Auto-connect if URL hash has #connect=PEER_ID (e.g. from WhatsApp invite link)
      const hash = window.location.hash;
      if (hash && hash.startsWith('#connect=')) {
        const targetPeerId = hash.replace('#connect=', '').trim();
        // Clear hash immediately so URL is sanitized
        history.replaceState(null, document.title, window.location.pathname);

        if (targetPeerId && targetPeerId !== id && PEER_ID_REGEX.test(targetPeerId)) {
          setTimeout(() => {
            peerSync.connectToPartner(targetPeerId);
          }, 800);
        }
      }
    }).catch(() => {
      // safe fail
    });

    return () => {
      isMounted = false;
    };
  }, [isUnlocked, cryptoKey]);

  const connectToPartner = (id) => {
    peerSync.connectToPartner(id);
  };

  const syncNow = () => {
    peerSync.syncNow();
  };

  const disconnect = () => {
    peerSync.disconnect();
  };

  return (
    <SyncContext.Provider
      value={{
        myPeerId,
        partnerId,
        syncStatus,
        lastSyncNotice,
        connectToPartner,
        syncNow,
        disconnect,
        isPartnerConnected: syncStatus.state === 'connected' || syncStatus.state === 'authorized' || syncStatus.state === 'synced' || syncStatus.state === 'syncing',
        isAuthorized: syncStatus.state === 'authorized' || syncStatus.state === 'synced' || syncStatus.state === 'syncing',
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
