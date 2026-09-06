import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import db from '../db';
import {
  generateSalt,
  deriveKeyFromPassphrase,
  encryptJSON,
  decryptJSON,
  MIN_PASSPHRASE_LENGTH,
} from '../services/crypto';
import peerSync from '../services/peerSync';

const VaultContext = createContext(null);

const CANARY_SECRET = 'SWEETHEART_CANARY_VALIDATION_TOKEN';

export function VaultProvider({ children }) {
  const [isVaultInitialized, setIsVaultInitialized] = useState(null); // null = checking, true/false
  const [isUnlocked, setIsUnlocked] = useState(false);
  const [cryptoKey, setCryptoKey] = useState(null);
  const [vaultSalt, setVaultSalt] = useState(null);
  const [vaultConfig, setVaultConfig] = useState(null);
  const [error, setError] = useState(null);

  /**
   * Unlock existing vault with passphrase
   */
  const unlockVault = async (passphrase) => {
    try {
      setError(null);
      if (!passphrase || passphrase.length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }
      const meta = await db.vaultMeta.get('config');
      if (!meta || !meta.salt) {
        throw new Error('Vault is not yet initialized.');
      }

      const key = await deriveKeyFromPassphrase(passphrase, meta.salt);

      // Verify passphrase by attempting to decrypt the canary token
      try {
        const decrypted = await decryptJSON(meta.canary, meta.canaryIv, key);
        if (decrypted.token !== CANARY_SECRET) {
          throw new Error('Canary mismatch');
        }

        try {
          sessionStorage.setItem('sweetheart_session_key', passphrase);
        } catch {}

        setVaultSalt(meta.salt);
        setCryptoKey(key);
        setVaultConfig({
          coupleNames: decrypted.coupleNames || 'Us',
          startDate: decrypted.startDate || '',
          updatedAt: decrypted.updatedAt || meta.updatedAt || 0,
        });
        setIsUnlocked(true);
        return true;
      } catch {
        setError('Incorrect passphrase! Please double-check and try again.');
        return false;
      }
    } catch (err) {
      setError(err.message || 'Unlock failed');
      return false;
    }
  };

  // Check if vault has already been set up in this browser's IndexedDB and auto-unlock if active session
  useEffect(() => {
    async function checkVault() {
      try {
        const meta = await db.vaultMeta.get('config');
        if (meta && meta.salt) {
          setVaultSalt(meta.salt);
          setIsVaultInitialized(true);

          // If browser tab refreshed within same session, auto-unlock!
          try {
            const savedSessionKey = sessionStorage.getItem('sweetheart_session_key');
            if (savedSessionKey) {
              await unlockVault(savedSessionKey);
            }
          } catch {}
        } else {
          setIsVaultInitialized(false);
        }
      } catch {
        setIsVaultInitialized(false);
      }
    }
    checkVault();
  }, []);

  /**
   * First time setup: Initialize a brand new shared vault with passphrase
   */
  const initializeVault = async (passphrase, initialSettings = {}) => {
    try {
      setError(null);
      if (!passphrase || passphrase.length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }
      const salt = generateSalt();
      const key = await deriveKeyFromPassphrase(passphrase, salt);

      // Encrypt canary token for instant passphrase verification upon future unlocks
      const canaryEncrypted = await encryptJSON(
        {
          token: CANARY_SECRET,
          coupleNames: initialSettings.coupleNames || 'Us',
          startDate: initialSettings.startDate || new Date().toISOString().split('T')[0],
          createdAt: Date.now(),
        },
        key
      );

      const meta = {
        id: 'config',
        salt,
        canary: canaryEncrypted.ciphertext,
        canaryIv: canaryEncrypted.iv,
        updatedAt: Date.now(),
      };

      await db.vaultMeta.put(meta);

      try {
        sessionStorage.setItem('sweetheart_session_key', passphrase);
      } catch {}

      setVaultSalt(salt);
      setCryptoKey(key);
      setVaultConfig({
        coupleNames: initialSettings.coupleNames || 'Us',
        startDate: initialSettings.startDate || new Date().toISOString().split('T')[0],
      });
      setIsVaultInitialized(true);
      setIsUnlocked(true);
      return true;
    } catch (err) {
      console.error('Failed to initialize vault:', err);
      setError('Could not initialize vault: ' + err.message);
      return false;
    }
  };

  /**
   * Partner invite setup: Initialize or join vault using partner's salt
   */
  const initializeFromPartnerInvite = async (passphrase, salt, initialSettings = {}) => {
    try {
      setError(null);
      if (!passphrase || passphrase.length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }
      if (!salt || typeof salt !== 'string') {
        setError('Invalid invite salt. Please request a fresh invite link.');
        return false;
      }

      const key = await deriveKeyFromPassphrase(passphrase, salt);

      const coupleNames = initialSettings.coupleNames || 'Us';
      const startDate = initialSettings.startDate || new Date().toISOString().split('T')[0];
      const updatedAt = initialSettings.startDate ? Date.now() : 0;

      const canaryEncrypted = await encryptJSON(
        {
          token: CANARY_SECRET,
          coupleNames,
          startDate,
          createdAt: Date.now(),
          updatedAt,
        },
        key
      );

      const meta = {
        id: 'config',
        salt,
        canary: canaryEncrypted.ciphertext,
        canaryIv: canaryEncrypted.iv,
        updatedAt,
      };

      await db.vaultMeta.put(meta);

      try {
        sessionStorage.setItem('sweetheart_session_key', passphrase);
      } catch {}

      setVaultSalt(salt);
      setCryptoKey(key);
      setVaultConfig({
        coupleNames,
        startDate,
        updatedAt,
      });
      setIsVaultInitialized(true);
      setIsUnlocked(true);
      return true;
    } catch (err) {
      console.error('Failed to initialize from partner invite:', err);
      setError('Could not pair with partner: ' + (err.message || 'Unknown error'));
      return false;
    }
  };

  /**
   * Update vault settings (names, anniversary start date)
   */
  const updateVaultSettings = async (newSettings) => {
    if (!cryptoKey) return;
    try {
      const meta = await db.vaultMeta.get('config');
      const updatedConfig = { ...vaultConfig, ...newSettings, updatedAt: Date.now() };
      
      const canaryEncrypted = await encryptJSON(
        {
          token: CANARY_SECRET,
          ...updatedConfig,
        },
        cryptoKey
      );

      await db.vaultMeta.put({
        ...meta,
        canary: canaryEncrypted.ciphertext,
        canaryIv: canaryEncrypted.iv,
        updatedAt: updatedConfig.updatedAt,
      });

      setVaultConfig(updatedConfig);

      // Broadcast live to connected partner over P2P!
      peerSync.syncVaultConfig(updatedConfig);
    } catch {
      // safe fail
    }
  };

  const vaultConfigRef = useRef(vaultConfig);
  useEffect(() => {
    vaultConfigRef.current = vaultConfig;
  }, [vaultConfig]);

  // Listen for live config updates from paired partner
  useEffect(() => {
    if (!isUnlocked || !cryptoKey) return;

    const handleConfigSynced = async (remoteConfig) => {
      if (!remoteConfig || !remoteConfig.startDate) return;
      try {
        const meta = await db.vaultMeta.get('config');
        if (!meta) return;

        const currentLocal = vaultConfigRef.current || {};
        const localUpdatedAt = currentLocal.updatedAt || 0;
        const remoteUpdatedAt = remoteConfig.updatedAt || 0;

        const isLocalDefault = !currentLocal.startDate || currentLocal.startDate === new Date().toISOString().split('T')[0];

        if (remoteUpdatedAt >= localUpdatedAt || isLocalDefault) {
          const merged = {
            ...currentLocal,
            coupleNames: remoteConfig.coupleNames || currentLocal.coupleNames || 'Us',
            startDate: remoteConfig.startDate,
            updatedAt: Math.max(remoteUpdatedAt, Date.now()),
          };

          const canaryEncrypted = await encryptJSON(
            {
              token: CANARY_SECRET,
              ...merged,
            },
            cryptoKey
          );

          await db.vaultMeta.put({
            ...meta,
            canary: canaryEncrypted.ciphertext,
            canaryIv: canaryEncrypted.iv,
            updatedAt: merged.updatedAt,
          });

          setVaultConfig(merged);
        }
      } catch (err) {
        console.error('Failed to apply synced config:', err);
      }
    };

    peerSync.on('config-synced', handleConfigSynced);

    return () => {
      peerSync.off('config-synced', handleConfigSynced);
    };
  }, [isUnlocked, cryptoKey]);

  /**
   * Lock vault, immediately terminate P2P connections, and clear sensitive memory state
   */
  const lockVault = () => {
    try {
      sessionStorage.removeItem('sweetheart_session_key');
    } catch {}
    try {
      peerSync.destroy();
    } catch {
      // safe fail
    }
    setCryptoKey(null);
    setVaultConfig(null);
    setIsUnlocked(false);
    setError(null);
  };

  return (
    <VaultContext.Provider
      value={{
        isVaultInitialized,
        isUnlocked,
        cryptoKey,
        vaultSalt,
        vaultConfig,
        error,
        initializeVault,
        initializeFromPartnerInvite,
        unlockVault,
        lockVault,
        updateVaultSettings,
      }}
    >
      {children}
    </VaultContext.Provider>
  );
}

export function useVault() {
  const context = useContext(VaultContext);
  if (!context) throw new Error('useVault must be used within VaultProvider');
  return context;
}

export default VaultContext;
