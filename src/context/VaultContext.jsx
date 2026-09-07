/**
 * src/context/VaultContext.jsx
 * Vault key lifecycle: unlock, first-time setup, partner pairing, lock.
 *
 * KEY HANDLING (this is the security-critical part)
 * The derived AES-GCM key is NON-EXTRACTABLE and lives in exactly two places:
 * React state (so components can use it) and the module singleton in
 * services/vaultKey.js (so it survives SPA navigation). It is never written to
 * sessionStorage, localStorage, IndexedDB, cookies or the URL, and neither is
 * the passphrase. Earlier builds stashed the PLAINTEXT passphrase in
 * sessionStorage to power auto-unlock; any XSS on the origin could read it.
 * That is gone.
 *
 * The consequence, which the README states plainly: a full page reload wipes
 * the JS heap, so the passphrase must be typed again. Navigating inside the
 * app does not.
 *
 * KDF VERSIONING
 * Vaults created before the OWASP bump derive at 250,000 PBKDF2 iterations and
 * keep doing so forever; new vaults use 600,000. Unlock goes through
 * deriveKeyWithVerification(), which tries the recorded count first and falls
 * back, so nobody gets locked out and nothing has to be re-encrypted.
 *
 * DESTRUCTIVE PATHS
 * Both initializeVault() and initializeFromPartnerInvite() write a fresh salt to
 * vaultMeta. Doing that over a live vault makes every existing record
 * permanently undecryptable. Both therefore refuse to run against an existing
 * vault unless the caller passes the exact DESTROY_CONFIRMATION_PHRASE, which
 * the UI only obtains by making the user type it.
 */
import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { AlertTriangle, X } from 'lucide-react';
import db, { SYNCED_TABLES } from '../db';
import {
  generateSalt,
  deriveKeyFromPassphrase,
  deriveKeyWithVerification,
  resolveKdfIterations,
  normalizePassphrase,
  createCanary,
  readCanary,
  isValidSalt,
  MIN_PASSPHRASE_LENGTH,
  PBKDF2_ITERATIONS_CURRENT,
} from '../services/crypto';
import { setVaultKey, getVaultKey, clearVaultKey, subscribeVaultKey } from '../services/vaultKey';
import peerSync from '../services/peerSync';

const VaultContext = createContext(null);

/**
 * The user must type this, exactly, before any code path is allowed to replace
 * the vault salt on a device that already has a vault.
 */
export const DESTROY_CONFIRMATION_PHRASE = 'ERASE OUR MEMORIES';

/** Longest couple name we will accept from a peer, to bound a hostile payload. */
const MAX_COUPLE_NAMES_LENGTH = 120;

/** A partner update stamped further ahead than this is a clock-skew artefact. */
const MAX_CLOCK_SKEW_MS = 48 * 60 * 60 * 1000;

/**
 * Today's date as 'YYYY-MM-DD' in the user's OWN timezone.
 * `new Date().toISOString()` is UTC, which hands back yesterday's date for
 * every local time between midnight and the UTC offset (05:30 in IST).
 * @param {Date} [date]
 * @returns {string}
 */
export function localDateString(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** @returns {boolean} True for a well-formed calendar 'YYYY-MM-DD' string. */
function isValidStartDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  return Number.isFinite(Date.parse(`${value}T00:00:00`));
}

/** @returns {string} A bounded, trimmed couple name. */
function sanitizeCoupleNames(value, fallback = 'Us') {
  if (typeof value !== 'string') return fallback;
  const trimmed = value.slice(0, MAX_COUPLE_NAMES_LENGTH).trim();
  return trimmed || fallback;
}

export function VaultProvider({ children }) {
  const [isVaultInitialized, setIsVaultInitialized] = useState(null); // null = still checking
  const [isUnlocked, setIsUnlocked] = useState(false);
  const [cryptoKey, setCryptoKey] = useState(null);
  const [vaultSalt, setVaultSalt] = useState(null);
  const [vaultConfig, setVaultConfig] = useState(null);
  const [error, setError] = useState(null);
  const [warning, setWarning] = useState(null);

  const clearError = useCallback(() => setError(null), []);
  const clearWarning = useCallback(() => setWarning(null), []);

  /**
   * Adopts a freshly verified key into both React state and the in-memory
   * singleton. Nothing else in this file calls setVaultKey.
   */
  const adoptKey = useCallback((key, salt, iterations, config) => {
    setVaultKey(key, { salt, iterations });
    setVaultSalt(salt);
    setCryptoKey(key);
    setVaultConfig(config);
    setIsVaultInitialized(true);
    setIsUnlocked(true);
  }, []);

  /**
   * Finishes the v1 -> v2 record migration now that a key exists. Non-fatal:
   * v1 rows stay readable either way, so a failure is a warning, not a block.
   */
  const runLegacyMigration = useCallback(async (key) => {
    try {
      const stats = await db.migrateLegacyRecords(key);
      if (stats.failed > 0) {
        setWarning(
          `${stats.failed} older record${stats.failed === 1 ? '' : 's'} could not be decrypted and ` +
            'were left untouched. They were most likely written with a different passphrase. ' +
            'Nothing was deleted.'
        );
      }
    } catch (err) {
      console.error('Legacy record migration failed:', err);
      setWarning(
        'Could not finish upgrading your older records to encrypted metadata. Your data is intact ' +
          'and still readable; this will be retried next time you unlock.'
      );
    }
  }, []);

  /** Records the count we actually unlocked with, so next time is one PBKDF2 run. */
  const rememberKdfIterations = useCallback(async (meta, iterations) => {
    if (!Number.isFinite(iterations) || meta.kdfIterations === iterations) return;
    try {
      await db.vaultMeta.put({ ...meta, kdfIterations: iterations });
    } catch (err) {
      // Purely an optimisation. Losing it costs a few hundred milliseconds.
      console.warn('Could not record vault KDF iteration count:', err);
    }
  }, []);

  /**
   * Unlocks an existing vault.
   * @param {string} passphrase
   * @returns {Promise<boolean>}
   */
  const unlockVault = useCallback(
    async (passphrase) => {
      setError(null);
      if (normalizePassphrase(passphrase).length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }

      let meta;
      try {
        meta = await db.vaultMeta.get('config');
      } catch (err) {
        console.error('Could not read vault metadata:', err);
        setError(
          'Could not open the local database. If you are in a private window, the browser may be blocking storage.'
        );
        return false;
      }

      if (!meta || !meta.salt) {
        setError('There is no vault on this device yet. Create one, or join your partner’s.');
        return false;
      }

      let derived;
      let canaryPayload = null;
      try {
        derived = await deriveKeyWithVerification(
          passphrase,
          meta.salt,
          async (candidate) => {
            const payload = await readCanary(candidate, meta);
            if (!payload) return false;
            canaryPayload = payload;
            return true;
          },
          { iterations: resolveKdfIterations(meta) }
        );
      } catch {
        setError('Incorrect passphrase! Please double-check and try again.');
        return false;
      }

      adoptKey(derived.key, meta.salt, derived.iterations, {
        coupleNames: sanitizeCoupleNames(canaryPayload && canaryPayload.coupleNames),
        startDate: (canaryPayload && canaryPayload.startDate) || '',
        updatedAt: (canaryPayload && canaryPayload.updatedAt) || meta.updatedAt || 0,
      });

      await rememberKdfIterations(meta, derived.iterations);
      // Deliberately not awaited: the app is usable while old rows are re-sealed.
      runLegacyMigration(derived.key);
      return true;
    },
    [adoptKey, rememberKdfIterations, runLegacyMigration]
  );

  /**
   * On mount: find out whether a vault exists, and restore the session if the
   * key is still held in memory from before an in-app navigation. A full reload
   * clears that singleton, which is exactly what we want.
   */
  useEffect(() => {
    let cancelled = false;

    async function checkVault() {
      let meta;
      try {
        meta = await db.vaultMeta.get('config');
      } catch (err) {
        console.error('Could not read vault metadata:', err);
        if (cancelled) return;
        setIsVaultInitialized(false);
        setError('Could not open the local database on this device. Storage may be blocked or full.');
        return;
      }

      if (cancelled) return;

      if (!meta || !meta.salt) {
        setIsVaultInitialized(false);
        return;
      }

      setVaultSalt(meta.salt);
      setIsVaultInitialized(true);

      const heldKey = getVaultKey();
      if (!heldKey) return;

      // The held key must still match THIS vault: a re-initialize elsewhere in
      // the app would have replaced the salt underneath us.
      const payload = await readCanary(heldKey, meta);
      if (cancelled) return;
      if (!payload) {
        clearVaultKey();
        return;
      }

      setCryptoKey(heldKey);
      setVaultConfig({
        coupleNames: sanitizeCoupleNames(payload.coupleNames),
        startDate: payload.startDate || '',
        updatedAt: payload.updatedAt || meta.updatedAt || 0,
      });
      setIsUnlocked(true);
    }

    checkVault();
    return () => {
      cancelled = true;
    };
  }, []);

  /** If anything else drops the key, the UI must follow it back to locked. */
  useEffect(
    () =>
      subscribeVaultKey((unlocked) => {
        if (!unlocked) {
          setCryptoKey(null);
          setVaultConfig(null);
          setIsUnlocked(false);
        }
      }),
    []
  );

  /**
   * Refuses a destructive re-initialize unless the caller proved the user typed
   * the confirmation phrase.
   * @param {string|undefined} confirmDestroy
   * @returns {Promise<{ blocked: boolean, existing: Object|null }>}
   */
  const guardDestructiveWrite = useCallback(async (confirmDestroy) => {
    let existing = null;
    try {
      existing = await db.vaultMeta.get('config');
    } catch {
      existing = null;
    }

    if (!existing || !existing.salt) return { blocked: false, existing: null };

    if (confirmDestroy !== DESTROY_CONFIRMATION_PHRASE) {
      setError(
        'This device already holds a vault. Replacing it would make every existing memory ' +
          'permanently unreadable, so it needs an explicit confirmation.'
      );
      return { blocked: true, existing };
    }

    return { blocked: false, existing };
  }, []);

  /** Clears every synced table. Only ever called on a confirmed destroy. */
  const wipeSyncedTables = useCallback(async () => {
    for (const tableName of SYNCED_TABLES) {
      try {
        await db.table(tableName).clear();
      } catch (err) {
        console.error(`Could not clear table ${tableName}:`, err);
      }
    }
  }, []);

  /**
   * First-time setup: creates a brand new vault with a fresh salt.
   *
   * @param {string} passphrase
   * @param {{ coupleNames?: string, startDate?: string }} [initialSettings]
   * @param {{ confirmDestroy?: string }} [options] - Must carry
   *   DESTROY_CONFIRMATION_PHRASE when a vault already exists on this device.
   * @returns {Promise<boolean>}
   */
  const initializeVault = useCallback(
    async (passphrase, initialSettings = {}, options = {}) => {
      setError(null);
      const normalized = normalizePassphrase(passphrase);
      if (normalized.length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }

      const { blocked, existing } = await guardDestructiveWrite(options.confirmDestroy);
      if (blocked) return false;

      try {
        const salt = generateSalt();
        const key = await deriveKeyFromPassphrase(normalized, salt, {
          iterations: PBKDF2_ITERATIONS_CURRENT,
        });

        const now = Date.now();
        const config = {
          coupleNames: sanitizeCoupleNames(initialSettings.coupleNames),
          startDate: isValidStartDate(initialSettings.startDate)
            ? initialSettings.startDate
            : localDateString(),
          // Stamped now, not left undefined: an unstamped config loses every
          // merge against a partner, however old the partner's copy is.
          updatedAt: now,
        };

        const { canary, canaryIv } = await createCanary(key, { ...config, createdAt: now });

        await db.vaultMeta.put({
          id: 'config',
          salt,
          canary,
          canaryIv,
          kdfIterations: PBKDF2_ITERATIONS_CURRENT,
          updatedAt: now,
        });

        // Only after the new salt is committed. The old records are
        // cryptographically unreachable from this point on, and leaving them
        // would feed undecryptable rows straight back into sync. Wiping first
        // would throw away still-readable data if the write above failed.
        if (existing) await wipeSyncedTables();

        adoptKey(key, salt, PBKDF2_ITERATIONS_CURRENT, config);
        return true;
      } catch (err) {
        console.error('Failed to initialize vault:', err);
        setError('Could not initialize vault: ' + (err.message || 'Unknown error'));
        return false;
      }
    },
    [adoptKey, guardDestructiveWrite, wipeSyncedTables]
  );

  /**
   * Pairing: adopts the partner's salt so both devices derive the same key.
   *
   * Three distinct cases, and only one of them is destructive:
   *  1. No local vault         -> plain setup against the partner's salt.
   *  2. Local vault, SAME salt -> not destructive at all. This is a re-pair, so
   *     it is handled as an ordinary unlock and needs no confirmation.
   *  3. Local vault, DIFFERENT salt -> destroys the local vault. Gated.
   *
   * @param {string} passphrase
   * @param {string} salt - Partner's base64 vault salt.
   * @param {{ coupleNames?: string, startDate?: string, canary?: string,
   *           canaryIv?: string, kdfIterations?: number }} [initialSettings]
   * @param {{ confirmDestroy?: string }} [options]
   * @returns {Promise<boolean>}
   */
  const initializeFromPartnerInvite = useCallback(
    async (passphrase, salt, initialSettings = {}, options = {}) => {
      setError(null);
      const normalized = normalizePassphrase(passphrase);
      if (normalized.length < MIN_PASSPHRASE_LENGTH) {
        setError(`Passphrase must be at least ${MIN_PASSPHRASE_LENGTH} characters long.`);
        return false;
      }
      if (!isValidSalt(salt)) {
        setError('That invite link is malformed. Ask your partner for a fresh one.');
        return false;
      }

      let existing = null;
      try {
        existing = await db.vaultMeta.get('config');
      } catch {
        existing = null;
      }

      // Case 2: re-pairing with the vault we already have. Nothing to destroy.
      if (existing && existing.salt === salt) {
        return await unlockVault(passphrase);
      }

      // Case 3: a different salt replaces the local vault.
      if (existing && existing.salt) {
        const { blocked } = await guardDestructiveWrite(options.confirmDestroy);
        if (blocked) return false;
      }

      try {
        const partnerMeta =
          typeof initialSettings.canary === 'string' && typeof initialSettings.canaryIv === 'string'
            ? { canary: initialSettings.canary, canaryIv: initialSettings.canaryIv }
            : null;

        let key;
        let iterations;

        if (partnerMeta) {
          // The invite carries the partner's canary, so a typo is caught HERE,
          // before we write a divergent vault that will never decrypt anything.
          let derived;
          try {
            derived = await deriveKeyWithVerification(
              passphrase,
              salt,
              async (candidate) => (await readCanary(candidate, partnerMeta)) !== null,
              {
                iterations: Number.isFinite(initialSettings.kdfIterations)
                  ? initialSettings.kdfIterations
                  : PBKDF2_ITERATIONS_CURRENT,
              }
            );
          } catch {
            setError(
              'That passphrase does not match your partner’s. Check it together, character for ' +
                'character, and try again.'
            );
            return false;
          }
          key = derived.key;
          iterations = derived.iterations;
        } else {
          iterations = Number.isFinite(initialSettings.kdfIterations)
            ? initialSettings.kdfIterations
            : PBKDF2_ITERATIONS_CURRENT;
          key = await deriveKeyFromPassphrase(normalized, salt, { iterations });
          // The normal path: invite links deliberately do NOT carry the canary,
          // because publishing a ciphertext under the vault key would hand an
          // offline passphrase-cracking oracle to whoever relays the link (see
          // utils/invite.js). The mismatch is caught instead by the P2P
          // handshake, which cannot authenticate under two different keys.
          setWarning(
            'Paired. Your passphrase is confirmed the moment your phones connect — if it does not ' +
              'match your partner’s exactly, the connection will say so rather than syncing.'
          );
        }

        const startDate = isValidStartDate(initialSettings.startDate)
          ? initialSettings.startDate
          : localDateString();
        // 0 when the invite carried no real settings, so the partner's config
        // wins the first merge instead of this placeholder.
        const updatedAt = isValidStartDate(initialSettings.startDate) ? Date.now() : 0;
        const config = {
          coupleNames: sanitizeCoupleNames(initialSettings.coupleNames),
          startDate,
          updatedAt,
        };

        const { canary, canaryIv } = await createCanary(key, {
          ...config,
          createdAt: Date.now(),
        });

        await db.vaultMeta.put({
          id: 'config',
          salt,
          canary,
          canaryIv,
          kdfIterations: iterations,
          updatedAt,
        });

        // Only after the new salt is committed - see initializeVault().
        if (existing && existing.salt) await wipeSyncedTables();

        adoptKey(key, salt, iterations, config);
        runLegacyMigration(key);
        return true;
      } catch (err) {
        console.error('Failed to initialize from partner invite:', err);
        setError('Could not pair with partner: ' + (err.message || 'Unknown error'));
        return false;
      }
    },
    [adoptKey, guardDestructiveWrite, runLegacyMigration, unlockVault, wipeSyncedTables]
  );

  /**
   * Updates couple name / anniversary and pushes them to the paired partner.
   * @param {{ coupleNames?: string, startDate?: string }} newSettings
   * @returns {Promise<boolean>} False when the write failed - the caller should
   *   not assume the new values stuck.
   */
  const updateVaultSettings = useCallback(
    async (newSettings) => {
      // This runs while unlocked, where the LockScreen (the only consumer of
      // `error`) is not mounted. Failures go to `warning`, which has a toast,
      // rather than into a state nobody renders.
      const key = cryptoKey || getVaultKey();
      if (!key) {
        setWarning('The vault is locked. Unlock it before changing your settings.');
        return false;
      }

      try {
        const meta = await db.vaultMeta.get('config');
        if (!meta || !meta.salt) {
          throw new Error('Vault metadata is missing from this device.');
        }

        const merged = { ...(vaultConfig || {}), ...newSettings };
        const updatedConfig = {
          coupleNames: sanitizeCoupleNames(merged.coupleNames),
          startDate: isValidStartDate(merged.startDate) ? merged.startDate : '',
          updatedAt: Date.now(),
        };

        const { canary, canaryIv } = await createCanary(key, updatedConfig);

        await db.vaultMeta.put({
          ...meta,
          canary,
          canaryIv,
          updatedAt: updatedConfig.updatedAt,
        });

        setVaultConfig(updatedConfig);

        try {
          peerSync.syncVaultConfig(updatedConfig);
        } catch (err) {
          console.warn('Could not push settings to partner:', err);
        }

        return true;
      } catch (err) {
        console.error('Failed to save vault settings:', err);
        setWarning(
          'Could not save your settings: ' +
            (err.message || 'Unknown error') +
            '. The old values are still in place and your partner was not told.'
        );
        return false;
      }
    },
    [cryptoKey, vaultConfig]
  );

  const vaultConfigRef = useRef(vaultConfig);
  useEffect(() => {
    vaultConfigRef.current = vaultConfig;
  }, [vaultConfig]);

  // Live config updates from the paired partner.
  useEffect(() => {
    if (!isUnlocked || !cryptoKey) return undefined;

    const handleConfigSynced = async (remoteConfig) => {
      if (!remoteConfig || typeof remoteConfig !== 'object') return;

      // The wire format is attacker-influenced. Validate before it reaches state.
      if (!isValidStartDate(remoteConfig.startDate)) {
        setWarning(
          'Ignored a settings update from your partner: it carried an invalid anniversary date.'
        );
        return;
      }

      const remoteUpdatedAt = Number.isFinite(remoteConfig.updatedAt) ? remoteConfig.updatedAt : 0;
      if (remoteUpdatedAt > Date.now() + MAX_CLOCK_SKEW_MS) {
        setWarning(
          'Ignored a settings update from your partner: their device clock is set far in the ' +
            'future. Fix the date on that device and try again.'
        );
        return;
      }

      const currentLocal = vaultConfigRef.current || {};
      const localUpdatedAt = Number.isFinite(currentLocal.updatedAt) ? currentLocal.updatedAt : 0;

      // Strictly newer wins. Ties keep the local copy: restamping the merge with
      // Date.now() used to make the receiver's copy permanently "newer", which
      // flipped the direction on every reconnect and ratcheted forever.
      if (remoteUpdatedAt <= localUpdatedAt) return;

      try {
        const meta = await db.vaultMeta.get('config');
        if (!meta || !meta.salt) return;

        const merged = {
          coupleNames: sanitizeCoupleNames(
            remoteConfig.coupleNames,
            currentLocal.coupleNames || 'Us'
          ),
          startDate: remoteConfig.startDate,
          updatedAt: remoteUpdatedAt,
        };

        const { canary, canaryIv } = await createCanary(cryptoKey, merged);

        await db.vaultMeta.put({
          ...meta,
          canary,
          canaryIv,
          updatedAt: merged.updatedAt,
        });

        setVaultConfig(merged);
      } catch (err) {
        console.error('Failed to apply synced config:', err);
        setWarning(
          'Could not save the settings your partner just sent. Your own settings are unchanged.'
        );
      }
    };

    peerSync.on('config-synced', handleConfigSynced);
    return () => {
      peerSync.off('config-synced', handleConfigSynced);
    };
  }, [isUnlocked, cryptoKey]);

  /**
   * Locks the vault: drops the in-memory key, tears down P2P, clears state.
   */
  const lockVault = useCallback(() => {
    clearVaultKey();
    try {
      peerSync.destroy();
    } catch (err) {
      console.warn('Could not tear down the P2P connection cleanly:', err);
    }
    setCryptoKey(null);
    setVaultConfig(null);
    setIsUnlocked(false);
    setError(null);
    setWarning(null);
  }, []);

  return (
    <VaultContext.Provider
      value={{
        isVaultInitialized,
        isUnlocked,
        cryptoKey,
        vaultSalt,
        vaultConfig,
        error,
        warning,
        clearError,
        clearWarning,
        initializeVault,
        initializeFromPartnerInvite,
        unlockVault,
        lockVault,
        updateVaultSettings,
      }}
    >
      {children}

      {/* Decryption and migration problems used to go to console.error and
          nowhere else. They get a face now. */}
      {warning && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-[100] w-[calc(100%-2rem)] max-w-md">
          <div className="flex items-start gap-2.5 p-3 rounded-2xl bg-amber-50 border border-amber-200 shadow-lg shadow-amber-200/40">
            <AlertTriangle className="w-4 h-4 text-amber-500 flex-shrink-0 mt-0.5" />
            <p className="flex-1 text-[11px] leading-relaxed text-amber-900 font-medium">{warning}</p>
            <button
              type="button"
              onClick={clearWarning}
              aria-label="Dismiss"
              className="text-amber-500 hover:text-amber-700 flex-shrink-0"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      )}
    </VaultContext.Provider>
  );
}

export function useVault() {
  const context = useContext(VaultContext);
  if (!context) throw new Error('useVault must be used within VaultProvider');
  return context;
}

export default VaultContext;
