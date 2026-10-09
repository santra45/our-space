import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { AlertTriangle, X } from 'lucide-react';
import db, {
  SYNCED_TABLES,
  readBackupVaultIdentity,
  compareVaultIdentity,
  isUpgradeBlocked,
  subscribeUpgradeBlocked,
} from '../db';
import {
  generateSalt,
  deriveKeyFromPassphrase,
  deriveKeyWithVerification,
  normalizePassphrase,
  createCanary,
  readCanary,
  isValidSalt,
  MIN_PASSPHRASE_LENGTH,
  PBKDF2_ITERATIONS_CURRENT,
} from '../services/crypto';
import { setVaultKey, getVaultKey, clearVaultKey, subscribeVaultKey } from '../services/vaultKey';
import { requestPersistentStorage } from '../services/persistentStorage';
import {
  isBiometricAvailable,
  isBiometricEnrolled,
  enableBiometricUnlock,
  unlockWithBiometric,
  forgetBiometricUnlock,
} from '../services/biometricUnlock';
import peerSync from '../services/peerSync';

const VaultContext = createContext(null);

export const DESTROY_CONFIRMATION_PHRASE = 'ERASE OUR MEMORIES';

const MAX_COUPLE_NAMES_LENGTH = 120;

const MAX_CLOCK_SKEW_MS = 48 * 60 * 60 * 1000;

export function localDateString(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function isValidStartDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  return Number.isFinite(Date.parse(`${value}T00:00:00`));
}

function sanitizeCoupleNames(value, fallback = 'Us') {
  if (typeof value !== 'string') return fallback;
  const trimmed = value.slice(0, MAX_COUPLE_NAMES_LENGTH).trim();
  return trimmed || fallback;
}

function nextConfigTimestamp(currentConfig) {
  let base;
  try {
    base = peerSync.getSyncSafeTimestamp();
  } catch {
    base = Date.now();
  }
  const localAt =
    currentConfig && Number.isFinite(currentConfig.updatedAt) ? currentConfig.updatedAt : 0;
  return Math.max(base, localAt + 1);
}

export function VaultProvider({ children }) {
  const [vaultCheckState, setVaultCheckState] = useState('checking');
  const [vaultCheckBlocked, setVaultCheckBlocked] = useState(false);
  const [isUnlocked, setIsUnlocked] = useState(false);
  const [cryptoKey, setCryptoKey] = useState(null);
  const [vaultSalt, setVaultSalt] = useState(null);
  const [vaultConfig, setVaultConfig] = useState(null);
  const [error, setError] = useState(null);
  const [warning, setWarning] = useState(null);

  const [quickUnlock, setQuickUnlock] = useState({ available: false, enrolled: false });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const available = await isBiometricAvailable();
      if (cancelled) return;
      setQuickUnlock({ available, enrolled: available && isBiometricEnrolled(vaultSalt) });
    })();
    return () => {
      cancelled = true;
    };
  }, [vaultSalt]);

  const clearError = useCallback(() => setError(null), []);
  const clearWarning = useCallback(() => setWarning(null), []);

  const adoptKey = useCallback((key, salt, iterations, config) => {
    setVaultKey(key, { salt, iterations });
    setVaultSalt(salt);
    setCryptoKey(key);
    setVaultConfig(config);
    setVaultCheckState('present');
    setVaultCheckBlocked(false);
    setIsUnlocked(true);
  }, []);

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
          'We could not open your space. If you are in a private window, your browser may be ' +
            'blocking it.'
        );
        return false;
      }

      if (!meta || !meta.salt) {
        setError('There is nothing here yet. Start your space, or join your partner’s.');
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
          { iterations: meta.kdfIterations }
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

      return true;
    },
    [adoptKey]
  );

  const readMetaOrExplain = useCallback(async (options = {}) => {
    const quiet = options.quiet === true;
    const fail = (message) => {
      if (!quiet) setError(message);
      return null;
    };

    let meta;
    try {
      meta = await db.vaultMeta.get('config');
    } catch (err) {
      console.error('Could not read vault metadata:', err);
      return fail('We could not open your space. Try again in a moment.');
    }
    if (!meta || !meta.salt) {
      return fail('There is nothing here yet. Start your space, or join your partner’s.');
    }
    return meta;
  }, []);

  const unlockWithQuickUnlock = useCallback(async () => {
    setError(null);

    const meta = await readMetaOrExplain();
    if (!meta) return false;

    let result;
    try {
      result = await unlockWithBiometric(meta.salt);
    } catch (err) {
      const code = err && err.code;
      if (code === 'cancelled') return false;
      setQuickUnlock((prev) => ({ ...prev, enrolled: isBiometricEnrolled(meta.salt) }));
      setError(
        code === 'stale'
          ? 'Quick unlock needs setting up again on this phone. Use your passphrase just this once.'
          : code === 'unsupported' || code === 'no-prf'
            ? 'This phone cannot do quick unlock. Your passphrase still works.'
            : 'That did not work. Use your passphrase just this once.'
      );
      return false;
    }

    let payload = null;
    try {
      payload = await readCanary(result.key, meta);
    } catch {
      payload = null;
    }
    if (!payload) {
      forgetBiometricUnlock();
      setQuickUnlock((prev) => ({ ...prev, enrolled: false }));
      setError('Quick unlock needs setting up again on this phone. Use your passphrase for now.');
      return false;
    }

    adoptKey(
      result.key,
      meta.salt,
      result.iterations || meta.kdfIterations || PBKDF2_ITERATIONS_CURRENT,
      {
        coupleNames: sanitizeCoupleNames(payload.coupleNames),
        startDate: payload.startDate || '',
        updatedAt: payload.updatedAt || meta.updatedAt || 0,
      }
    );
    return true;
  }, [adoptKey, readMetaOrExplain]);

  const enableQuickUnlock = useCallback(
    async (passphrase) => {
      setError(null);

      const meta = await readMetaOrExplain({ quiet: true });
      if (!meta) return { ok: false, code: 'no-vault' };

      let derived;
      try {
        derived = await deriveKeyWithVerification(
          passphrase,
          meta.salt,
          async (candidate) => !!(await readCanary(candidate, meta)),
          { iterations: meta.kdfIterations }
        );
      } catch {
        return { ok: false, code: 'wrong-passphrase' };
      }

      try {
        await enableBiometricUnlock({
          passphrase,
          vaultSalt: meta.salt,
          iterations: derived.iterations,
          normalize: derived.normalized,
        });
      } catch (err) {
        return { ok: false, code: (err && err.code) || 'failed' };
      }

      setQuickUnlock((prev) => ({ ...prev, enrolled: true }));
      return { ok: true };
    },
    [readMetaOrExplain]
  );

  const disableQuickUnlock = useCallback(() => {
    forgetBiometricUnlock();
    setQuickUnlock((prev) => ({ ...prev, enrolled: false }));
  }, []);

  const checkCancelledRef = useRef(false);

  const checkVault = useCallback(async () => {
    setVaultCheckState('checking');

    const read = await db.readVaultIdentity();
    if (checkCancelledRef.current) return;

    if (!read.ok) {
      console.error('Could not read vault metadata:', read.error);
      setVaultCheckBlocked(isUpgradeBlocked());
      setVaultCheckState('unreadable');
      return;
    }

    const meta = read.meta;
    if (!meta) {
      setVaultCheckBlocked(false);
      setVaultCheckState('absent');
      return;
    }

    setVaultSalt(meta.salt);
    setVaultCheckBlocked(false);
    setVaultCheckState('present');

    const heldKey = getVaultKey();
    if (!heldKey) return;

    const payload = await readCanary(heldKey, meta);
    if (checkCancelledRef.current) return;
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
  }, []);

  useEffect(() => {
    checkCancelledRef.current = false;
    checkVault();
    return () => {
      checkCancelledRef.current = true;
    };
  }, [checkVault]);

  useEffect(() => subscribeUpgradeBlocked((blocked) => setVaultCheckBlocked(blocked)), []);

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

  const guardDestructiveWrite = useCallback(async (confirmDestroy) => {
    const read = await db.readVaultIdentity();

    if (!read.ok) {
      console.error('Destructive write blocked: vault metadata unreadable.', read.error);
      setError(
        'We could not read what is on this phone, so nothing was changed. Usually that means Our ' +
          'Space is open in another tab — close the others, then reload this one.'
      );
      return { blocked: true, existing: null };
    }

    if (!read.meta) return { blocked: false, existing: null };

    if (confirmDestroy !== DESTROY_CONFIRMATION_PHRASE) {
      setError(
        'There is already a space on this phone. Replacing it would make everything in it ' +
          'impossible to open again, so we need you to confirm.'
      );
      return { blocked: true, existing: read.meta };
    }

    return { blocked: false, existing: read.meta };
  }, []);

  const wipeSyncedTables = useCallback(async () => {
    for (const tableName of SYNCED_TABLES) {
      try {
        await db.table(tableName).clear();
      } catch (err) {
        console.error(`Could not clear table ${tableName}:`, err);
      }
    }
  }, []);

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

        const createdAt = Date.now();
        const configAt = nextConfigTimestamp(null);
        const config = {
          coupleNames: sanitizeCoupleNames(initialSettings.coupleNames),
          startDate: isValidStartDate(initialSettings.startDate)
            ? initialSettings.startDate
            : localDateString(),
          updatedAt: configAt,
        };

        const { canary, canaryIv } = await createCanary(key, { ...config, createdAt });

        await db.vaultMeta.put({
          id: 'config',
          salt,
          canary,
          canaryIv,
          kdfIterations: PBKDF2_ITERATIONS_CURRENT,
          updatedAt: configAt,
        });

        if (existing) await wipeSyncedTables();

        adoptKey(key, salt, PBKDF2_ITERATIONS_CURRENT, config);
        return true;
      } catch (err) {
        console.error('Failed to initialize vault:', err);
        setError('We could not set up your space. Please try again.');
        return false;
      }
    },
    [adoptKey, guardDestructiveWrite, wipeSyncedTables]
  );

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

      const read = await db.readVaultIdentity();
      if (!read.ok) {
        console.error('Pairing blocked: vault metadata unreadable.', read.error);
        setError(
          'We could not read what is on this phone, so we stopped instead of pairing. Close any ' +
            'other tabs with Our Space open, then reload and try again.'
        );
        return false;
      }
      const existing = read.meta;

      if (existing && existing.salt === salt) {
        return await unlockVault(passphrase);
      }

      if (existing) {
        const { blocked } = await guardDestructiveWrite(options.confirmDestroy);
        if (blocked) return false;
      }

      try {
        const partnerMeta =
          typeof initialSettings.canary === 'string' && typeof initialSettings.canaryIv === 'string'
            ? { canary: initialSettings.canary, canaryIv: initialSettings.canaryIv }
            : null;

        const iterations = PBKDF2_ITERATIONS_CURRENT;
        let key;

        if (partnerMeta) {
          let derived;
          try {
            derived = await deriveKeyWithVerification(
              passphrase,
              salt,
              async (candidate) => (await readCanary(candidate, partnerMeta)) !== null,
              { iterations }
            );
          } catch {
            setError(
              'That passphrase does not match your partner’s. Check it together, character for ' +
                'character, and try again.'
            );
            return false;
          }
          key = derived.key;
        } else {
          key = await deriveKeyFromPassphrase(normalized, salt, { iterations });
          setWarning(
            'Paired! We will know your passphrases match the moment your phones connect — if they ' +
              'do not, we will tell you instead of syncing.'
          );
        }

        const startDate = isValidStartDate(initialSettings.startDate)
          ? initialSettings.startDate
          : localDateString();
        const updatedAt = 0;
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

        if (existing) await wipeSyncedTables();

        adoptKey(key, salt, iterations, config);
        return true;
      } catch (err) {
        console.error('Failed to initialize from partner invite:', err);
        setError('We could not pair with your partner. Please try again.');
        return false;
      }
    },
    [adoptKey, guardDestructiveWrite, unlockVault, wipeSyncedTables]
  );

  const restoreVaultFromBackup = useCallback(
    async (tables, vaultPassphrase, options = {}) => {
      setError(null);

      const identity = readBackupVaultIdentity(tables);
      if (!identity) {
        return { ok: false, code: 'no_identity' };
      }
      if (!isValidSalt(identity.salt)) {
        return { ok: false, code: 'bad_salt' };
      }
      if (normalizePassphrase(vaultPassphrase).length < MIN_PASSPHRASE_LENGTH) {
        return { ok: false, code: 'passphrase_too_short' };
      }

      let derived;
      try {
        derived = await deriveKeyWithVerification(
          vaultPassphrase,
          identity.salt,
          async (candidate) => (await readCanary(candidate, identity)) !== null,
          { iterations: identity.kdfIterations }
        );
      } catch {
        return { ok: false, code: 'passphrase_mismatch' };
      }

      const read = await db.readVaultIdentity();
      if (!read.ok) {
        console.error('Restore blocked: vault metadata unreadable.', read.error);
        return { ok: false, code: 'unreadable' };
      }

      const relation = compareVaultIdentity(identity, read);

      if (relation === 'same') {
        return { ok: false, code: 'same_vault', relation };
      }
      if (relation === 'unknown') {
        return { ok: false, code: 'unreadable', relation };
      }

      if (relation === 'foreign' && options.confirmDestroy !== DESTROY_CONFIRMATION_PHRASE) {
        return { ok: false, code: 'needs_confirmation', relation };
      }

      try {
        const canaryPayload = await readCanary(derived.key, identity);

        await db.restoreVaultIdentity({ ...identity, kdfIterations: derived.iterations });

        await wipeSyncedTables();

        const plan = await db.planBackupMerge(tables, derived.key);
        const applied = await db.applyBackupMerge(plan);

        adoptKey(derived.key, identity.salt, derived.iterations, {
          coupleNames: sanitizeCoupleNames(canaryPayload && canaryPayload.coupleNames),
          startDate: (canaryPayload && canaryPayload.startDate) || '',
          updatedAt: (canaryPayload && canaryPayload.updatedAt) || identity.updatedAt || 0,
        });

        return {
          ok: true,
          relation,
          stats: {
            restored: Object.values(applied.written).reduce((sum, n) => sum + n, 0),
            invalid: plan.totals.invalid,
            undecryptable: plan.totals.undecryptable,
          },
        };
      } catch (err) {
        console.error('Vault restore failed:', err);
        return { ok: false, code: 'write_failed', relation, message: err.message };
      }
    },
    [adoptKey, wipeSyncedTables]
  );

  const updateVaultSettings = useCallback(
    async (newSettings) => {
      const key = cryptoKey || getVaultKey();
      if (!key) {
        setWarning('Our Space is locked. Unlock it before changing your settings.');
        return false;
      }

      try {
        const meta = await db.vaultMeta.get('config');
        if (!meta || !meta.salt) {
          throw new Error('vaultMeta config row is missing on this device');
        }

        const merged = { ...(vaultConfig || {}), ...newSettings };
        const updatedConfig = {
          coupleNames: sanitizeCoupleNames(merged.coupleNames),
          startDate: isValidStartDate(merged.startDate) ? merged.startDate : '',
          updatedAt: nextConfigTimestamp(vaultConfig),
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
          'We could not save your settings. The old ones are still in place, and your partner ' +
            'was not told.'
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

  useEffect(() => {
    if (!isUnlocked) return;
    requestPersistentStorage();
  }, [isUnlocked]);

  useEffect(() => {
    if (!isUnlocked || !cryptoKey) return undefined;

    const handleConfigSynced = async (remoteConfig) => {
      if (!remoteConfig || typeof remoteConfig !== 'object') return;

      if (!isValidStartDate(remoteConfig.startDate)) {
        setWarning('We skipped a settings change from your partner — the date did not look right.');
        return;
      }

      const remoteUpdatedAt = Number.isFinite(remoteConfig.updatedAt) ? remoteConfig.updatedAt : 0;
      if (remoteUpdatedAt > Date.now() + MAX_CLOCK_SKEW_MS) {
        setWarning(
          'We skipped a settings change from your partner — their phone’s date is set far in the ' +
            'future. Fix it on that phone and try again.'
        );
        return;
      }

      const currentLocal = vaultConfigRef.current || {};
      const localUpdatedAt = Number.isFinite(currentLocal.updatedAt) ? currentLocal.updatedAt : 0;

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
          'We could not save the settings your partner just sent. Yours are unchanged.'
        );
      }
    };

    peerSync.on('config-synced', handleConfigSynced);
    return () => {
      peerSync.off('config-synced', handleConfigSynced);
    };
  }, [isUnlocked, cryptoKey]);

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

  const isVaultInitialized =
    vaultCheckState === 'present' ? true : vaultCheckState === 'absent' ? false : null;

  return (
    <VaultContext.Provider
      value={{
        isVaultInitialized,
        vaultCheckState,
        vaultCheckBlocked,
        retryVaultCheck: checkVault,
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
        restoreVaultFromBackup,
        unlockVault,
        lockVault,
        updateVaultSettings,
        quickUnlockAvailable: quickUnlock.available,
        quickUnlockEnrolled: quickUnlock.enrolled,
        unlockWithQuickUnlock,
        enableQuickUnlock,
        disableQuickUnlock,
      }}
    >
      {children}

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
