import React, { createContext, useContext, useState, useEffect } from 'react';
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

  // Check if vault has already been set up in this browser's IndexedDB
  useEffect(() => {
    async function checkVault() {
      try {
        const meta = await db.vaultMeta.get('config');
        if (meta && meta.salt) {
          setVaultSalt(meta.salt);
          setIsVaultInitialized(true);
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
      console.error('Failed to initialize from partner invite:', err);
      setError('Could not pair with partner: ' + (err.message || 'Unknown error'));
      return false;
    }
  };

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

        setVaultSalt(meta.salt);
        setCryptoKey(key);
        setVaultConfig({
          coupleNames: decrypted.coupleNames || 'Us',
          startDate: decrypted.startDate || '',
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

  /**
   * Update vault settings (names, anniversary start date)
   */
  const updateVaultSettings = async (newSettings) => {
    if (!cryptoKey) return;
    try {
      const meta = await db.vaultMeta.get('config');
      const updatedConfig = { ...vaultConfig, ...newSettings };
      
      const canaryEncrypted = await encryptJSON(
        {
          token: CANARY_SECRET,
          ...updatedConfig,
          updatedAt: Date.now(),
        },
        cryptoKey
      );

      await db.vaultMeta.put({
        ...meta,
        canary: canaryEncrypted.ciphertext,
        canaryIv: canaryEncrypted.iv,
        updatedAt: Date.now(),
      });

      setVaultConfig(updatedConfig);
    } catch {
      // safe fail
    }
  };

  /**
   * Lock vault, immediately terminate P2P connections, and clear sensitive memory state
   */
  const lockVault = () => {
    try {
      peerSync.disconnect();
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
