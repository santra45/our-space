/**
 * src/context/SyncContext.jsx
 * Connects peerSync lifecycle to React state and monitors URL hash for auto-pairing links
 */
import React, { createContext, useContext, useState, useEffect } from 'react';
import peerSync from '../services/peerSync';
import { useVault } from './VaultContext';
import { parseInvite } from '../utils/invite';

const SyncContext = createContext(null);

export function SyncProvider({ children }) {
  const { cryptoKey, isUnlocked, vaultConfig } = useVault();
  const [myPeerId, setMyPeerId] = useState(null);
  const [partnerId, setPartnerId] = useState(() => {
    try {
      return localStorage.getItem('sweetheart_paired_partner_id') || null;
    } catch {
      return null;
    }
  });
  const [syncStatus, setSyncStatus] = useState({ state: 'disconnected' });
  const [lastSyncNotice, setLastSyncNotice] = useState(null);
  const [connectionType, setConnectionType] = useState(null); // 'direct' | 'relayed' | null

  // Initialize peer when vault is unlocked
  useEffect(() => {
    if (!isUnlocked || !cryptoKey) {
      peerSync.disconnect();
      setMyPeerId(null);
      setSyncStatus({ state: 'disconnected' });
      setConnectionType(null);
      return;
    }

    let isMounted = true;

    // Listen to PeerSync events
    peerSync.on('status', (status) => {
      if (!isMounted) return;
      setSyncStatus(status);
      if (status.peerId) setMyPeerId(status.peerId);
      if (status.partnerId) {
        setPartnerId(status.partnerId);
        try {
          localStorage.setItem('sweetheart_paired_partner_id', status.partnerId);
        } catch {}
      }
      if (status.state === 'authorized') {
        if (vaultConfig) {
          peerSync.syncVaultConfig(vaultConfig);
        }
      }
      if (status.message) setLastSyncNotice(status.message);
      if (status.connectionType) setConnectionType(status.connectionType);
      if (status.state === 'disconnected') setConnectionType(null);
    });

    peerSync.on('data-updated', (data) => {
      if (!isMounted) return;
      setLastSyncNotice(`Synced ${data.count || 1} new item(s) from partner 💕`);
      setTimeout(() => setLastSyncNotice(null), 4000);
    });

    // Start peer
    peerSync.init(cryptoKey).then((id) => {
      if (!isMounted) return;
      setMyPeerId(id);

      // Check for pending partner connect from LockScreen invite or URL hash
      let targetPeerId = null;
      try {
        const pending = sessionStorage.getItem('pending_partner_connect');
        if (pending) {
          sessionStorage.removeItem('pending_partner_connect');
          targetPeerId = pending.trim();
        }
      } catch {}

      const hash = window.location.hash;
      if (hash) {
        const parsed = parseInvite(hash);
        if (parsed && parsed.partnerPeerId) {
          targetPeerId = parsed.partnerPeerId;
        }
        // Sanitize URL by clearing hash
        try {
          history.replaceState(null, document.title, window.location.pathname);
        } catch {}
      }

      // If no invite in hash or session, check stored paired partner
      if (!targetPeerId) {
        try {
          const savedPartner = localStorage.getItem('sweetheart_paired_partner_id');
          if (savedPartner && savedPartner !== id) {
            targetPeerId = savedPartner.trim();
          }
        } catch {}
      }

      if (targetPeerId && targetPeerId !== id) {
        setPartnerId(targetPeerId);
        setTimeout(() => {
          peerSync.connectToPartner(targetPeerId);
        }, 800);
      }
    }).catch(() => {
      // safe fail
    });

    return () => {
      isMounted = false;
    };
  }, [isUnlocked, cryptoKey, vaultConfig]);

  const connectToPartner = (id) => {
    peerSync.connectToPartner(id);
  };

  const reconnectToPartner = () => {
    let target = partnerId;
    if (!target) {
      try {
        target = localStorage.getItem('sweetheart_paired_partner_id');
      } catch {}
    }
    if (target && target !== myPeerId) {
      peerSync.connectToPartner(target);
    }
  };

  const unpairPartner = () => {
    try {
      localStorage.removeItem('sweetheart_paired_partner_id');
      sessionStorage.removeItem('pending_partner_connect');
    } catch {}
    setPartnerId(null);
    peerSync.disconnect();
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
        reconnectToPartner,
        unpairPartner,
        syncNow,
        disconnect,
        connectionType,
        isDirectP2P: connectionType === 'direct',
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
