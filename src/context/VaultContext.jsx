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
 * initializeVault(), initializeFromPartnerInvite() and restoreVaultFromBackup()
 * all write a salt to vaultMeta. Doing that over a live vault makes every
 * existing record permanently undecryptable. All three therefore refuse to run
 * against an existing vault unless the caller passes the exact
 * DESTROY_CONFIRMATION_PHRASE, which the UI only obtains by making the user
 * type it.
 *
 * THOSE GATES FAIL CLOSED
 * Each gate depends on reading vaultMeta. A read that FAILS is not evidence that
 * there is nothing to lose - a version upgrade blocked by another open tab looks
 * exactly like a blank device. Every read here goes through db.readVaultIdentity(),
 * which reports "could not tell" as its own outcome, and every caller treats that
 * outcome as a reason to stop.
 */
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

/**
 * A monotonic timestamp for the VAULT CONFIG last-write-wins channel.
 *
 * coupleNames / startDate merge on `updatedAt` exactly like records do, but on a
 * separate channel that used to stamp raw Date.now(). That handed the merge
 * permanently to whichever device had the faster clock: its edits were always
 * "newer", and the slower device could never win however recently it typed.
 * Borrowing peerSync's clock floor makes this device's stamps monotonic and
 * ahead of anything the partner has issued, and the +1 over the current config
 * guarantees an edit always beats the value it is replacing.
 *
 * EVERY config stamp goes through here now, including the two that create a
 * config (initializeVault and initializeFromPartnerInvite). They used to stamp
 * raw Date.now() while the edit path was careful, which is exactly the
 * inconsistency that lets a first write be un-beatable.
 *
 * DELIBERATELY NOT DONE: feeding an inbound partner config into a clock floor.
 * Two reasons, and the second one is why it would be pointless even if it were
 * safe.
 *   1. peerSync keeps ONE high-water mark, `_observedRemoteMax`, and every
 *      record write consults it. Raising it from the config channel would let a
 *      single settings message from a peer with a broken (or hostile) clock
 *      ratchet the timestamp on every future PHOTO and LETTER this device
 *      writes, permanently and irreversibly. Couple names are cosmetic; records
 *      are the irreplaceable part. Never trade the second for the first.
 *   2. A floor only raises OUR OWN stamps. The failure it would supposedly fix -
 *      a partner's genuinely newer settings losing to our inflated placeholder -
 *      is decided by the receiver comparing the two numbers, so pushing our
 *      number even higher makes the partner lose harder, not less. The real fix
 *      is not to inflate the placeholder in the first place; see
 *      initializeFromPartnerInvite.
 *
 * @param {{ updatedAt?: number }|null} currentConfig
 * @returns {number}
 */
function nextConfigTimestamp(currentConfig) {
  let base;
  try {
    base = peerSync.getSyncSafeTimestamp();
  } catch {
    // peerSync is not up yet. Still monotonic against our own config below.
    base = Date.now();
  }
  const localAt =
    currentConfig && Number.isFinite(currentConfig.updatedAt) ? currentConfig.updatedAt : 0;
  return Math.max(base, localAt + 1);
}

export function VaultProvider({ children }) {
  /**
   * 'checking' | 'present' | 'absent' | 'unreadable'
   *
   * 'unreadable' is the important one and is deliberately NOT collapsed into
   * 'absent'. See the header note about failing closed.
   */
  const [vaultCheckState, setVaultCheckState] = useState('checking');
  const [vaultCheckBlocked, setVaultCheckBlocked] = useState(false);
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
    setVaultCheckState('present');
    setVaultCheckBlocked(false);
    setIsUnlocked(true);
  }, []);

  /**
   * Finishes the v1 -> v2 record migration now that a key exists. Non-fatal:
   * v1 rows stay readable either way, so a failure is a warning, not a block.
   *
   * BOTH counters the sweep returns are rendered, and they mean opposite things.
   * `failed` is a row this key could not open at all - a filing mistake, almost
   * always a record written under a different passphrase. `tampered` is a row
   * that opened perfectly and then disagreed with its own seal, which is a
   * person. The sweep refuses to re-seal those (db/index.js, the
   * `plain._headerTampered === true` branch: it increments `stats.tampered` and
   * `continue`s before the re-encrypt, because re-sealing would rebuild the
   * envelope around the CURRENT bytes and authenticate the edit).
   *
   * This counter went to nowhere at all until now, and the failure mode was the
   * quietest one in the app: `_headerTampered` folds in a swapped binary field
   * and a cross-table replay as well as a rewritten header (crypto.js, where
   * `out._headerTampered` ORs in `binaryCheck.tampered` and `out._tableTampered`),
   * and every one of the five screens that renders records skips such a row
   * (BucketList, SecretCapsule, MilestoneTracker, PolaroidWall, DateRoulette all
   * test `_headerTampered` before displaying). So a photo whose bytes were
   * swapped in place simply stopped appearing, with nothing anywhere saying why
   * - indistinguishable from a rendering bug, which is the reading that costs
   * the user nothing to accept.
   */
  const runLegacyMigration = useCallback(async (key) => {
    try {
      const stats = await db.migrateLegacyRecords(key);
      const notes = [];

      if (stats.failed > 0) {
        const many = stats.failed !== 1;
        notes.push(
          `${stats.failed} older record${many ? 's' : ''} could not be decrypted and ` +
            `${many ? 'were' : 'was'} left untouched — most likely written with a different ` +
            'passphrase.'
        );
      }

      if (stats.tampered > 0) {
        const many = stats.tampered !== 1;
        notes.push(
          `${stats.tampered} record${many ? 's' : ''} opened with your passphrase but ` +
            `${many ? 'no longer match' : 'no longer matches'} what was sealed inside ` +
            `${many ? 'them' : 'it'}: a rewritten id, date or delete flag, photo bytes swapped ` +
            `after the fact, or an envelope sealed for a different list. That is why ` +
            `${many ? 'they are' : 'it is'} missing from your screens instead of showing up ` +
            `wrong — every screen refuses ${many ? 'them' : 'it'}. ${many ? 'They were' : 'It was'} ` +
            `left exactly as ${many ? 'they are' : 'it is'} and deliberately not re-sealed, which ` +
            `is what makes your partner’s phone refuse ${many ? 'them' : 'it'} too if this one ` +
            'sends it on.'
        );
      }

      if (notes.length > 0) setWarning(`${notes.join(' ')} Nothing was deleted.`);
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

  const checkCancelledRef = useRef(false);

  /**
   * Finds out whether a vault exists, and restores the session if the key is
   * still held in memory from before an in-app navigation. A full reload clears
   * that singleton, which is exactly what we want.
   *
   * A FAILED READ RESOLVES TO 'unreadable', NEVER 'absent'. Reporting "no vault"
   * on a read error is what routed a returning user to the CREATE VAULT form,
   * one confirmation phrase away from writing a fresh salt over everything they
   * own. The most likely cause is not a broken device at all: it is the v1 -> v2
   * schema upgrade being blocked by another tab still holding the old version,
   * which Dexie tells us about explicitly.
   */
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

    // The held key must still match THIS vault: a re-initialize elsewhere in
    // the app would have replaced the salt underneath us.
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

  /** If the block clears (the other tab closes), stop claiming it is blocked. */
  useEffect(() => subscribeUpgradeBlocked((blocked) => setVaultCheckBlocked(blocked)), []);

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
   *
   * FAILS CLOSED. The previous version did `catch { existing = null }` and then
   * returned `blocked: false` - so the gate that exists to protect a live vault
   * granted permission precisely when it could not see the vault it was
   * protecting. A blocked schema upgrade (another tab holding v1 open) makes
   * that read throw, and the same error routes the user to the create-vault form
   * in the first place; once the block cleared, a fresh salt landed on a fully
   * populated vault with no confirmation ever demanded.
   *
   * "Could not read" is now its own answer, and its answer is no.
   *
   * @param {string|undefined} confirmDestroy
   * @returns {Promise<{ blocked: boolean, existing: Object|null }>}
   */
  const guardDestructiveWrite = useCallback(async (confirmDestroy) => {
    const read = await db.readVaultIdentity();

    if (!read.ok) {
      console.error('Destructive write blocked: vault metadata unreadable.', read.error);
      setError(
        'This device’s vault could not be read, so nothing was changed. That usually means Our ' +
          'Space is open in another tab or window — close every other copy, then reload this one. ' +
          'Until it can be read, replacing the vault is refused: a read error is not proof there ' +
          'is nothing here to lose.'
      );
      return { blocked: true, existing: null };
    }

    if (!read.meta) return { blocked: false, existing: null };

    if (confirmDestroy !== DESTROY_CONFIRMATION_PHRASE) {
      setError(
        'This device already holds a vault. Replacing it would make every existing memory ' +
          'permanently unreadable, so it needs an explicit confirmation.'
      );
      return { blocked: true, existing: read.meta };
    }

    return { blocked: false, existing: read.meta };
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

        // These settings were genuinely typed here, so they are a real authored
        // write and get a real monotonic stamp - the same helper the edit path
        // uses, not raw Date.now(). `createdAt` stays wall-clock because it is
        // descriptive: nothing merges on it.
        const createdAt = Date.now();
        const configAt = nextConfigTimestamp(null);
        const config = {
          coupleNames: sanitizeCoupleNames(initialSettings.coupleNames),
          startDate: isValidStartDate(initialSettings.startDate)
            ? initialSettings.startDate
            : localDateString(),
          // Stamped now, not left undefined: an unstamped config loses every
          // merge against a partner, however old the partner's copy is.
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

      // Same fail-closed read as guardDestructiveWrite. Swallowing this error
      // used to do double damage: it skipped the confirmation gate AND, because
      // `existing` was left null, it skipped wipeSyncedTables() below - so the
      // old rows survived under a salt that could no longer decrypt them and
      // fed undecryptable garbage straight back into sync.
      const read = await db.readVaultIdentity();
      if (!read.ok) {
        console.error('Pairing blocked: vault metadata unreadable.', read.error);
        setError(
          'This device’s vault could not be read, so pairing was refused. Close any other tab or ' +
            'window running Our Space and reload. Pairing would replace this device’s encryption ' +
            'key, and that is not safe to do while we cannot see what is already stored here.'
        );
        return false;
      }
      const existing = read.meta;

      // Case 2: re-pairing with the vault we already have. Nothing to destroy.
      if (existing && existing.salt === salt) {
        return await unlockVault(passphrase);
      }

      // Case 3: a different salt replaces the local vault.
      if (existing) {
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
        // ALWAYS 0, whether or not the invite carried settings.
        //
        // Nothing in this config was authored on this device: it is either a
        // default, or the INVITER'S OWN names and anniversary echoed back out of
        // the link they sent. Stamping it Date.now() made a joiner with a fast
        // clock claim authorship of the inviter's settings at a time the inviter
        // could not beat, so the inviter's real config lost the
        // `remoteUpdatedAt <= localUpdatedAt` test on every sync until wall clock
        // caught up. 0 loses the first merge by construction, which is the
        // correct outcome for a copy: the device that actually authored the
        // settings keeps them. The joiner still SEES the right names immediately
        // - this number decides merges, not what is on screen - and the joiner's
        // own first edit goes through nextConfigTimestamp and beats 0 easily.
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

        // Only after the new salt is committed - see initializeVault().
        if (existing) await wipeSyncedTables();

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
   * RESTORE A VAULT IDENTITY FROM A RESCUE BACKUP.
   *
   * This is the flow the LockScreen's rescue backup has always promised and the
   * code never had. A .vault container carries `vaultMeta` (see EXPORTED_TABLES),
   * so it holds the salt, canary and KDF count that the records inside it were
   * encrypted under. Every other code path deliberately refuses to write that
   * back; this one adopts it on purpose, because adopting it is the ONLY way the
   * ciphertext in the file is ever readable again.
   *
   * It is a separate operation from the ordinary merge-import, not a hidden
   * branch of it: a merge keeps the vault key you already have, a restore
   * replaces it. Conflating them is how "restore" quietly becomes "destroy".
   *
   * SAFETY ORDER, and why each step is where it is:
   *   1. Prove the passphrase against the BACKUP'S OWN canary first. If the key
   *      cannot be shown to open this container, adopting its salt would produce
   *      a vault whose contents nobody can read - the exact trap this replaces.
   *      Nothing is written before this passes.
   *   2. Read the live identity with a fail-closed read. "Cannot tell" stops us.
   *   3. Refuse outright when the backup is for the vault already on this device
   *      - a merge-import is the right tool there and does not touch the key.
   *   4. Demand the destroy phrase when a DIFFERENT live vault would be replaced.
   *   5. Commit the identity, THEN wipe, THEN write the records. Wiping first
   *      would throw away readable data if the identity write failed.
   *
   * @param {Record<string, Object[]>} tables - `tables` from a decrypted container.
   * @param {string} vaultPassphrase - The passphrase the RECORDS were encrypted
   *   under, which is not necessarily the passphrase the FILE was encrypted with.
   * @param {{ confirmDestroy?: string }} [options]
   * @returns {Promise<{ ok: boolean, code?: string, relation?: string, stats?: Object }>}
   */
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

      // 1. Prove the key opens this container's own canary.
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

      // 2. Fail-closed read of what is already here.
      const read = await db.readVaultIdentity();
      if (!read.ok) {
        console.error('Restore blocked: vault metadata unreadable.', read.error);
        return { ok: false, code: 'unreadable' };
      }

      const relation = compareVaultIdentity(identity, read);

      // 3. Same vault: a restore would be a pointless re-key, and would revert
      //    the live canary (and with it coupleNames/startDate) to the backup's.
      if (relation === 'same') {
        return { ok: false, code: 'same_vault', relation };
      }
      if (relation === 'unknown') {
        return { ok: false, code: 'unreadable', relation };
      }

      // 4. Replacing a different live vault needs the phrase, same as any other
      //    salt replacement on this device.
      if (relation === 'foreign' && options.confirmDestroy !== DESTROY_CONFIRMATION_PHRASE) {
        return { ok: false, code: 'needs_confirmation', relation };
      }

      try {
        const canaryPayload = await readCanary(derived.key, identity);

        // 5a. Commit the identity first.
        await db.restoreVaultIdentity({ ...identity, kdfIterations: derived.iterations });

        // 5b. Then clear the tables. Anything still here belongs to the vault we
        //     just replaced, so it is unreadable from now on either way; leaving
        //     it would feed undecryptable rows straight back into sync. This runs
        //     even on a device that reported no vault, because a previous destroy
        //     can leave orphaned rows behind with no vaultMeta to point at them.
        //
        //     UNCONDITIONAL ON PURPOSE, including relation === 'no-local-vault'.
        //     Making it conditional would need a proof that a device with no
        //     vaultMeta also has no rows, and there is none: vaultMeta and the
        //     record tables are separate stores with no foreign key, so a partial
        //     wipe, an aborted transaction or a hand-cleared vaultMeta leaves
        //     rows behind whose key no longer exists anywhere in the world. They
        //     can never be read again, but they CAN be re-broadcast at a partner
        //     as undecryptable garbage. Safety over convenience: the cost of the
        //     wipe is zero (nothing readable is lost - by definition), and the
        //     LockScreen copy for this branch now says the clearing happens
        //     rather than promising it does not.
        await wipeSyncedTables();

        // 5c. Then write the records, through the same validation and integrity
        //     checks a merge-import uses - now keyed by the restored key.
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
          // Not Date.now(): see nextConfigTimestamp. Raw wall-clock here handed
          // the coupleNames/startDate merge permanently to the faster clock.
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

  /**
   * Kept for the screens that only need the three-way answer. `null` now means
   * "we do not know" for BOTH reasons - still checking, or the read failed - so
   * anything that could destroy data must consult `vaultCheckState` instead and
   * treat 'unreadable' as a stop.
   */
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
