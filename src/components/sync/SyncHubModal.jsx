/**
 * src/components/sync/SyncHubModal.jsx
 * P2P WebRTC connection hub: QR code generation, WhatsApp share link, sync
 * controls, and encrypted vault backup/restore.
 *
 * Connection indicators here are driven by `isAuthorized` only. peerSync reports
 * `handshaking` for a data channel that opened but has not proved it holds the
 * vault key; rendering that as "Connected to Partner" told the user a stranger
 * was their partner.
 *
 * The backup passphrase is collected through a masked in-app prompt with a
 * confirm field and is verified against the live vault canary before a single
 * byte is written. A typo used to produce a .vault file that nobody, including
 * its owner, could ever open.
 */
import React, { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import {
  X,
  Share2,
  Camera,
  RefreshCw,
  AlertTriangle,
  Copy,
  Download,
  Upload,
  ShieldCheck,
  ShieldAlert,
  Zap,
  HelpCircle,
  Eye,
  EyeOff,
  Loader2,
} from 'lucide-react';
import QRCode from 'qrcode';
import { useSync } from '../../context/SyncContext';
import { useVault } from '../../context/VaultContext';
import { buildInviteUrl, parseInvite } from '../../utils/invite';
import BouncyButton from '../common/BouncyButton';
import QRScannerModal from './QRScannerModal';
import { useHaptics } from '../../hooks/useHaptics';
import db, {
  MAX_BACKUP_FILE_BYTES,
  readBackupVaultIdentity,
  compareVaultIdentity,
} from '../../db';
import {
  createEncryptedBackup,
  decryptBackupContainer,
  verifyPassphraseAgainstMeta,
  resolveKdfIterations,
  normalizePassphrase,
  MIN_PASSPHRASE_LENGTH,
} from '../../services/crypto';

const MAX_BACKUP_FILE_MB = Math.round(MAX_BACKUP_FILE_BYTES / (1024 * 1024));

/**
 * Masked passphrase prompt. Replaces window.prompt, which rendered the vault
 * passphrase as plain text on screen and offered no way to confirm it.
 */
function PassphrasePrompt({
  title,
  description,
  requireConfirm,
  submitLabel,
  busy,
  error,
  onSubmit,
  onCancel,
}) {
  const [value, setValue] = useState('');
  const [confirmValue, setConfirmValue] = useState('');
  const [reveal, setReveal] = useState(false);

  const normalized = normalizePassphrase(value);
  const tooShort = normalized.length < MIN_PASSPHRASE_LENGTH;
  const mismatch = requireConfirm && confirmValue.length > 0 && value !== confirmValue;
  const canSubmit = !busy && !tooShort && (!requireConfirm || (confirmValue.length > 0 && !mismatch));

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!canSubmit) return;
    onSubmit(value);
  };

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <motion.form
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        onSubmit={handleSubmit}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100"
      >
        <h3 className="text-base font-bold text-slate-800">{title}</h3>
        <p className="mt-1 text-[11px] text-slate-500 leading-relaxed">{description}</p>

        <div className="mt-3 relative">
          <input
            type={reveal ? 'text' : 'password'}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            autoFocus
            autoComplete="off"
            spellCheck={false}
            placeholder="Secret passphrase"
            className="w-full px-3 py-2.5 pr-10 text-sm bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
          />
          <button
            type="button"
            onClick={() => setReveal((r) => !r)}
            aria-label={reveal ? 'Hide passphrase' : 'Show passphrase'}
            className="absolute right-2 top-1/2 -translate-y-1/2 w-7 h-7 rounded-lg text-slate-400 hover:text-slate-600 flex items-center justify-center"
          >
            {reveal ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
          </button>
        </div>

        {requireConfirm && (
          <input
            type={reveal ? 'text' : 'password'}
            value={confirmValue}
            onChange={(e) => setConfirmValue(e.target.value)}
            autoComplete="off"
            spellCheck={false}
            placeholder="Type it again to confirm"
            className="mt-2 w-full px-3 py-2.5 text-sm bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
          />
        )}

        {value.length > 0 && tooShort && (
          <p className="mt-2 text-[10px] font-semibold text-amber-600">
            At least {MIN_PASSPHRASE_LENGTH} characters.
          </p>
        )}
        {mismatch && (
          <p className="mt-2 text-[10px] font-semibold text-rose-600">
            The two entries do not match.
          </p>
        )}
        {error && (
          <p className="mt-2 px-3 py-2 text-[10px] font-semibold text-rose-700 bg-rose-50 border border-rose-200 rounded-xl leading-relaxed">
            {error}
          </p>
        )}

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!canSubmit}
            className="py-2.5 rounded-2xl bg-blush-500 text-white text-xs font-bold shadow-sm shadow-blush-300/50 hover:bg-blush-600 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
          >
            {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>{busy ? 'Working...' : submitLabel}</span>
          </button>
        </div>
      </motion.form>
    </div>
  );
}

/**
 * The preview a merge-import must survive before a single row is written.
 *
 * Counts, not reassurance. `stale` is the number the old blind bulkPut would
 * have silently overwritten with older data, and `undecryptable` is the tell
 * that the file belongs to a different vault entirely.
 *
 * Every `relation` compareVaultIdentity can return has a branch here. 'unknown'
 * used to have none, so a file whose origin could not be established rendered
 * identically to the user's own backup - same counts, no banner, live Merge
 * button. It now says so out loud.
 *
 * DELIBERATE: 'unknown' gets a LOUD banner but NOT the confirmation phrase a
 * salt replacement gets, and the Merge button stays live. The reasoning, since
 * the opposite choice is the tempting one:
 *
 *   - Identity is a label; the gate is per-row. planBackupMerge queues a row
 *     only when it carries a complete authenticated payload AND that payload
 *     decrypts under this device's live key. Forging one needs the key. So a
 *     queued row was provably written by THIS vault, whatever the file's
 *     (missing) vaultMeta claims, and a hostile unlabelled file can at worst
 *     replay rows the user already owns - which `incomingWins` then rejects
 *     unless they are genuinely newer than the local copy.
 *   - Nothing here writes a salt or clears a table, so there is no destructive
 *     outcome for a phrase to guard. Asking for one anyway would train the user
 *     to type it past a file that is already proven safe, and that devalues the
 *     same phrase where it guards something real.
 *
 * What unknown origin actually costs is the ability to EXPLAIN a large
 * `undecryptable` count, so that is what the banner talks about.
 */
function ImportPreview({ plan, relation, busy, onConfirm, onCancel }) {
  const { added, updated, stale, invalid, undecryptable } = plan.totals;
  const willWrite = added + updated;
  const foreign = relation === 'foreign';

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 max-h-[85vh] overflow-y-auto"
      >
        <h3 className="text-base font-bold text-slate-800">Review this restore</h3>
        <p className="mt-1 text-[11px] text-slate-500 leading-relaxed">
          Nothing has been written yet. This is what the merge would do.
        </p>

        {foreign && (
          <div className="mt-3 p-3 rounded-xl bg-rose-50 border-2 border-rose-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-rose-800 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">Different vault</p>
              <p className="mt-1">
                This backup was made by a <strong>different vault</strong> than the one on this
                device. Its records are encrypted under a key this device does not have, and some of
                them share fixed ids with yours (the starter bucket-list items, the date roulette
                pick), so a blind restore would replace your copies with rows nothing here can read —
                they would simply vanish from every screen with no error.
              </p>
              {/* Describes the counters printed below rather than promising a
                  result independently of them. The old copy asserted "every
                  record failed" as an unconditional guarantee, sitting directly
                  above numbers that are computed separately - a string that can
                  disagree with the data under it is a defect even while it
                  happens to be true. */}
              <p className="mt-1 font-bold">
                {willWrite === 0
                  ? 'Nothing from it can be written: the counts below are the finished result of ' +
                    'checking every record in the file against your key, and none of them passed.'
                  : `The counts below are the finished result of checking every record in this ` +
                    `file against your key, and ${willWrite} of them passed. A backup from a ` +
                    `different vault should have none — read the numbers before you accept them.`}
              </p>
            </div>
          </div>
        )}

        {relation === 'unknown' && (
          <div className="mt-3 p-3 rounded-xl bg-amber-50 border-2 border-amber-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-amber-900 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">Origin not established</p>
              <p className="mt-1">
                This file carries no readable vault identity — the part naming the vault it came
                from is missing or incomplete — so it could not be matched against the vault on
                this device. <strong>Every backup this app has ever written carries one</strong>,
                so this file has been altered, truncated, or made by something else.
              </p>
              <p className="mt-1">
                That does not loosen anything below. A record is still only written when it decrypts
                and authenticates under <strong>your current key</strong>, which no other vault can
                produce — so anything that does get written is provably yours. If the counts below
                are mostly &quot;could not be decrypted&quot;, this file is not yours and you should
                cancel.
              </p>
            </div>
          </div>
        )}

        {relation === 'no-local-vault' && (
          <div className="mt-3 p-2.5 rounded-xl bg-amber-50 border border-amber-200 text-[11px] text-amber-900 leading-relaxed">
            This device has no vault identity recorded, so the backup could not be matched against
            one. Only records that decrypt with your current key will be written.
          </div>
        )}

        <div className="mt-3 grid grid-cols-2 gap-2 text-center">
          <div className="p-2.5 rounded-xl bg-emerald-50 border border-emerald-100">
            <p className="text-lg font-extrabold text-emerald-700">{added}</p>
            <p className="text-[10px] font-bold text-emerald-800 uppercase tracking-wide">Added</p>
          </div>
          <div className="p-2.5 rounded-xl bg-indigo-50 border border-indigo-100">
            <p className="text-lg font-extrabold text-indigo-700">{updated}</p>
            <p className="text-[10px] font-bold text-indigo-800 uppercase tracking-wide">Updated</p>
          </div>
        </div>

        <ul className="mt-2 space-y-1 text-[11px] text-slate-600">
          <li className="flex justify-between gap-2 px-1">
            <span>Older than what you already have — kept as-is</span>
            <span className="font-bold text-slate-800">{stale}</span>
          </li>
          <li className="flex justify-between gap-2 px-1">
            <span>Could not be decrypted by this vault — refused</span>
            <span className={`font-bold ${undecryptable > 0 ? 'text-rose-600' : 'text-slate-800'}`}>
              {undecryptable}
            </span>
          </li>
          <li className="flex justify-between gap-2 px-1">
            <span>Malformed or out-of-range — refused</span>
            <span className="font-bold text-slate-800">{invalid}</span>
          </li>
        </ul>

        <p className="mt-3 text-[10px] text-slate-500 leading-relaxed">
          Newer local edits are never replaced by older ones from the file — the same rule your two
          phones use when they sync. Your vault key is not touched by a merge; to rebuild a vault
          from a rescue file, lock the app and use &quot;Restore from a rescue backup&quot; on the
          lock screen instead.
        </p>

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={busy || willWrite === 0}
            className="py-2.5 rounded-2xl bg-blush-500 text-white text-xs font-bold shadow-sm shadow-blush-300/50 hover:bg-blush-600 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
          >
            {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>
              {willWrite === 0 ? 'Nothing to write' : busy ? 'Merging...' : `Merge ${willWrite}`}
            </span>
          </button>
        </div>
      </motion.div>
    </div>
  );
}

export function SyncHubModal({ isOpen, onClose }) {
  const {
    myPeerId,
    partnerId,
    syncStatus,
    isAuthorized,
    isHandshaking,
    isConnecting,
    syncError,
    syncWarning,
    clearSyncError,
    connectToPartner,
    reconnectToPartner,
    unpairPartner,
    syncNow,
    connectionType,
  } = useSync();
  const { vaultSalt, vaultConfig, cryptoKey } = useVault();
  const [partnerInputId, setPartnerInputId] = useState('');
  const [isScannerOpen, setIsScannerOpen] = useState(false);
  const [copySuccess, setCopySuccess] = useState(false);
  const [codeCopied, setCodeCopied] = useState(false);
  const [backupNotice, setBackupNotice] = useState('');
  const [backupError, setBackupError] = useState('');
  const [pairError, setPairError] = useState('');

  // { mode: 'export' | 'import', container?: Object }
  const [passphrasePrompt, setPassphrasePrompt] = useState(null);
  const [promptBusy, setPromptBusy] = useState(false);
  const [promptError, setPromptError] = useState('');

  /**
   * This vault's PBKDF2 iteration count, carried in the invite.
   *
   * It is REQUIRED for correctness, not an optimisation. A vault created before
   * the OWASP bump derives at 250,000 and keeps doing so forever. A partner
   * joining it with no recorded count would derive at 600,000, get a different
   * key, and never authorise - with nothing in the join UI to explain why. Like
   * the salt, the count is a public KDF parameter and secret-free.
   *
   * The passphrase CANARY is deliberately NOT carried here. See buildInviteUrl.
   */
  const [inviteKdfIterations, setInviteKdfIterations] = useState(null);
  const [inviteMetaError, setInviteMetaError] = useState('');

  // { plan, relation, identity }
  const [importPreview, setImportPreview] = useState(null);
  const [importBusy, setImportBusy] = useState(false);

  const qrCanvasRef = useRef(null);
  const { tap, celebration } = useHaptics();

  useEffect(() => {
    if (!isOpen) return undefined;
    let cancelled = false;
    setInviteMetaError('');

    db.vaultMeta
      .get('config')
      .then((meta) => {
        if (cancelled) return;
        if (!meta || !meta.salt) {
          setInviteMetaError('This device has no vault key material, so it cannot invite anyone.');
          return;
        }
        // resolveKdfIterations always answers: a row without the field predates
        // it and is therefore 250,000. So the ONLY way to end up without a count
        // is a failed read, handled below.
        setInviteKdfIterations(resolveKdfIterations(meta));
      })
      .catch((err) => {
        if (cancelled) return;
        console.error('Could not read the vault KDF iteration count:', err);
        setInviteMetaError(
          'Could not read this vault’s key settings, so no invite can be built right now. ' +
            'Close any other tab running Our Space and reopen this hub.'
        );
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen]);

  /**
   * REG-3: the invite is not built until the KDF count has actually resolved.
   *
   * This used to be computed on first render with `inviteKdfIterations` still
   * null, so `#kdf=` was omitted from both the link and the QR for as long as the
   * async vaultMeta read took. A link copied in that window hands a legacy
   * 250,000-iteration vault to a joiner who then derives at 600,000, gets a
   * different key, and hits a permanent passphrase_mismatch with nothing in the
   * UI to explain it. An invite missing the count is worse than no invite, so
   * until it resolves there is no invite.
   */
  const inviteReady = Boolean(myPeerId) && Boolean(vaultSalt) && Number.isFinite(inviteKdfIterations);

  const shareUrl = inviteReady
    ? buildInviteUrl(myPeerId, vaultSalt, {
        startDate: vaultConfig?.startDate,
        coupleNames: vaultConfig?.coupleNames,
        kdfIterations: inviteKdfIterations,
      })
    : '';

  // Render QR Code on canvas
  useEffect(() => {
    if (!isOpen || !inviteReady || !shareUrl || !qrCanvasRef.current) return;

    QRCode.toCanvas(
      qrCanvasRef.current,
      shareUrl,
      {
        width: 190,
        // The QR spec requires a four-module quiet zone; `margin: 1` supplied
        // one and made the symbol harder to acquire against a light background.
        margin: 2,
        errorCorrectionLevel: 'M',
        color: {
          dark: '#1e293b',
          light: '#ffffff',
        },
      },
      (error) => {
        if (error) console.error('QR code generation error:', error);
      }
    );
  }, [isOpen, inviteReady, shareUrl]);

  // WhatsApp / Native Web Share API trigger
  const handleShareInvite = async () => {
    tap();
    if (!inviteReady) {
      setPairError(
        inviteMetaError ||
          'Still reading this vault’s key settings. An invite sent without them would fail to pair, ' +
            'so it is not built yet — try again in a moment.'
      );
      return;
    }
    const shareData = {
      title: 'Our Private Space 💕',
      text: 'Connect with me on our private space app! Tap to pair our phones directly:',
      url: shareUrl,
    };

    if (navigator.share) {
      try {
        await navigator.share(shareData);
        celebration();
        return;
      } catch {
        // user cancelled or share failed, fallback to copy
      }
    }

    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopySuccess(true);
      setTimeout(() => setCopySuccess(false), 2500);
    } catch {
      setPairError('Could not copy the link. Long-press your pairing code above to copy it instead.');
    }
  };

  const handleCopyCode = async () => {
    if (!myPeerId) return;
    tap();
    try {
      await navigator.clipboard.writeText(myPeerId);
      setCodeCopied(true);
      setTimeout(() => setCodeCopied(false), 2000);
    } catch {
      // clipboard blocked; the id is visible on the button anyway
    }
  };

  const handleManualConnect = (e) => {
    e.preventDefault();
    setPairError('');
    const raw = partnerInputId.trim();
    if (!raw) return;

    const parsed = parseInvite(raw);
    if (!parsed || !parsed.partnerPeerId) {
      setPairError(
        'That does not look like a pairing code or invite link. Paste the whole link your partner shared, or their code from the hub.'
      );
      return;
    }

    tap();
    connectToPartner(parsed.partnerPeerId);
  };

  /** Receives the RAW scanned payload; parseInvite is the only parser. */
  const handleScanSuccess = (scannedPayload) => {
    setIsScannerOpen(false);
    setPairError('');
    const parsed = parseInvite(scannedPayload);
    if (!parsed || !parsed.partnerPeerId) {
      setPairError('That QR code is not an Our Space pairing invite.');
      return;
    }
    celebration();
    connectToPartner(parsed.partnerPeerId);
  };

  /* --------------------------------------------------------------------- *
   * Encrypted backup
   * --------------------------------------------------------------------- */

  const closePrompt = () => {
    setPassphrasePrompt(null);
    setPromptError('');
    setPromptBusy(false);
  };

  const handleExportBackup = () => {
    tap();
    setBackupNotice('');
    setBackupError('');
    setPromptError('');
    setPassphrasePrompt({ mode: 'export' });
  };

  const runExport = async (passphrase) => {
    setPromptBusy(true);
    setPromptError('');
    let url = null;
    try {
      // D3: prove the typed passphrase actually opens THIS vault before writing
      // anything. Without this, one typo produces an undecryptable .vault.
      const meta = await db.vaultMeta.get('config');
      if (!meta || !meta.salt) {
        setPromptError('This vault has no key material on this device, so a backup cannot be verified.');
        return;
      }

      const matches = await verifyPassphraseAgainstMeta(passphrase, meta);
      if (!matches) {
        setPromptError(
          'That is not this vault’s passphrase. The backup must use the same passphrase you unlock with, otherwise nothing could ever restore it.'
        );
        return;
      }

      const rawData = await db.exportRawDataForBackup();
      const container = await createEncryptedBackup(rawData, passphrase);
      // Round-trip the container before handing it over.
      await decryptBackupContainer(container, passphrase);

      const blob = new Blob([JSON.stringify(container)], { type: 'application/json' });
      url = URL.createObjectURL(blob);

      // P5: Firefox aborts a download whose anchor was never in the document,
      // and aborts it again if the object URL is revoked in the same tick.
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `OurSpace-Encrypted-${new Date().toISOString().split('T')[0]}.vault`;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();

      closePrompt();
      setBackupNotice('Encrypted .vault backup created and verified. Only that passphrase can open it.');
      celebration();
    } catch (err) {
      setPromptError('Could not create the backup: ' + (err?.message || 'unknown error'));
    } finally {
      if (url) setTimeout(() => URL.revokeObjectURL(url), 60000);
      setPromptBusy(false);
    }
  };

  const handleImportBackup = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    setBackupNotice('');
    setBackupError('');
    setPromptError('');

    // P5: without a cap, readAsText on a multi-GB file pulls it all into a
    // string and hangs the tab before anything is even validated.
    if (file.size > MAX_BACKUP_FILE_BYTES) {
      setBackupError(
        `That file is ${Math.round(file.size / (1024 * 1024))}MB. Backups are capped at ${MAX_BACKUP_FILE_MB}MB.`
      );
      return;
    }

    try {
      tap();
      const text = await file.text();
      let container;
      try {
        container = JSON.parse(text);
      } catch {
        setBackupError('That file is not a valid .vault backup (it is not readable JSON).');
        return;
      }
      if (!container || typeof container !== 'object' || Array.isArray(container)) {
        setBackupError('That file is not a valid .vault backup.');
        return;
      }
      setPassphrasePrompt({ mode: 'import', container });
    } catch (err) {
      setBackupError('Could not read that file: ' + (err?.message || 'unknown error'));
    }
  };

  /**
   * PLANS the import. Writes nothing.
   *
   * The old version went straight from this passphrase prompt to a bulkPut over
   * the live tables - no check that the file came from this vault, no timestamp
   * comparison, no preview, no confirmation. With the deterministic seed ids this
   * build introduced (bkt-default-1..6, roulette-current), two DIFFERENT vaults
   * collide on primary key, so importing a friend's backup replaced live rows
   * with rows encrypted under a key this device does not have. Every read path
   * skips undecryptable rows silently, so those items just disappeared.
   *
   * Now: verify identity, verify every record decrypts here, compare timestamps
   * with the sync engine's own rule, then show the user the damage before asking.
   */
  const runImport = async (passphrase) => {
    setPromptBusy(true);
    setPromptError('');
    try {
      // Decrypt and verify the 128-bit GCM tag. Wrong key or tampering throws.
      const decrypted = await decryptBackupContainer(passphrasePrompt.container, passphrase);

      if (!cryptoKey) {
        setPromptError('The vault is locked, so a backup cannot be verified. Unlock and try again.');
        return;
      }

      const identity = readBackupVaultIdentity(decrypted.tables);
      const localRead = await db.readVaultIdentity();
      const relation = compareVaultIdentity(identity, localRead);

      // Fail closed: if we cannot read our own identity we cannot tell whether
      // this file belongs here, and a wrong answer costs the user their photos.
      if (relation === 'unknown' && !localRead.ok) {
        setPromptError(
          'This device’s vault could not be read, so the backup could not be checked against it. ' +
            'Nothing was written. Close any other tab running Our Space and try again.'
        );
        return;
      }

      const plan = await db.planBackupMerge(decrypted.tables, cryptoKey);
      closePrompt();
      setImportPreview({ plan, relation, identity });
    } catch (err) {
      setPromptError(
        'Backup rejected: ' + (err?.message || 'incorrect passphrase or corrupted backup file')
      );
    } finally {
      setPromptBusy(false);
    }
  };

  /** Applies a plan the user has now seen and accepted. */
  const confirmImport = async () => {
    if (!importPreview) return;
    setImportBusy(true);
    setBackupError('');
    try {
      const result = await db.applyBackupMerge(importPreview.plan);
      const written = Object.values(result.written || {}).reduce((sum, n) => sum + n, 0);
      const supersededNote = result.supersededSincePreview
        ? ` ${result.supersededSincePreview} were superseded by a newer copy that arrived while you were reading this, and were left alone.`
        : '';
      setImportPreview(null);
      setBackupNotice(`Merged ${written} record(s) from that backup.${supersededNote}`);
      celebration();
    } catch (err) {
      setImportPreview(null);
      setBackupError('The merge failed: ' + (err?.message || 'unknown error'));
    } finally {
      setImportBusy(false);
    }
  };

  if (!isOpen) return null;

  /* --------------------------------------------------------------------- *
   * Status rendering
   * --------------------------------------------------------------------- */

  let statusDot = 'bg-amber-400';
  let statusLabel = 'Awaiting Connection';
  if (isAuthorized) {
    statusDot = 'bg-emerald-500 animate-pulse';
    statusLabel = 'Connected to Partner';
  } else if (isHandshaking) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Verifying partner (not trusted yet)...';
  } else if (isConnecting) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Connecting to Partner...';
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 max-h-[90vh] overflow-y-auto relative"
      >
        <button
          onClick={() => {
            tap();
            onClose();
          }}
          className="absolute top-4 right-4 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200"
        >
          <X className="w-4 h-4" />
        </button>

        <div className="text-center mb-4">
          <h3 className="text-base font-bold text-slate-800">Pair &amp; Sync Hub</h3>
          <p className="text-xs text-slate-400">Direct peer-to-peer connection</p>
        </div>

        {/* Live Status */}
        <div className="mb-4 p-3.5 rounded-2xl bg-blush-50/60 border border-blush-100 space-y-2.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className={`w-2.5 h-2.5 rounded-full ${statusDot}`} />
              <span className="text-xs font-bold text-slate-700">{statusLabel}</span>
            </div>

            {isAuthorized && (
              <button
                onClick={() => {
                  tap();
                  syncNow();
                }}
                className="text-xs font-semibold text-blush-600 inline-flex items-center gap-1 hover:underline"
              >
                <RefreshCw className="w-3 h-3" />
                <span>Sync Now</span>
              </button>
            )}
          </div>

          {/* X3: the route badge reports what was actually measured. */}
          {isAuthorized && (
            <div className="pt-2 border-t border-blush-100/70 text-[11px] space-y-1">
              <div className="flex items-center justify-between gap-2">
                <span className="text-slate-500 font-medium shrink-0">Connection Route:</span>
                {connectionType === 'direct' ? (
                  <span className="inline-flex items-center gap-1 font-bold text-emerald-700 bg-emerald-100/80 px-2.5 py-0.5 rounded-full border border-emerald-200 shadow-sm">
                    <Zap className="w-3 h-3 text-amber-500 fill-amber-400" />
                    <span>Direct P2P ⚡</span>
                  </span>
                ) : connectionType === 'relayed' ? (
                  <span className="inline-flex items-center gap-1 font-semibold text-indigo-700 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200">
                    <ShieldCheck className="w-3 h-3 text-indigo-500" />
                    <span>Relayed 🛡️</span>
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full border border-slate-200">
                    <HelpCircle className="w-3 h-3 text-slate-400" />
                    <span>Unknown</span>
                  </span>
                )}
              </div>
              {connectionType !== 'direct' && connectionType !== 'relayed' && (
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  The browser has not reported which network path this connection took. Your data is
                  end-to-end encrypted either way, but this app cannot honestly claim the link is
                  phone-to-phone right now.
                </p>
              )}
            </div>
          )}

          {/* Paired Partner Info & Reconnect Button */}
          {partnerId && (
            <div className="pt-2 border-t border-blush-100/70 text-[11px] flex items-center justify-between">
              <div className="flex items-center gap-1.5 overflow-hidden">
                <span className="text-slate-500 font-medium">Partner:</span>
                <span className="font-mono text-slate-700 font-bold truncate max-w-[130px]">
                  {partnerId}
                </span>
              </div>
              <div className="flex items-center gap-2">
                {!isAuthorized && (
                  <button
                    type="button"
                    onClick={() => {
                      tap();
                      reconnectToPartner();
                    }}
                    className="inline-flex items-center gap-1 font-bold text-blush-600 hover:text-blush-700 underline text-xs"
                  >
                    <RefreshCw className="w-3 h-3" />
                    <span>Reconnect</span>
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => {
                    if (window.confirm('Unpair from this partner device?')) {
                      unpairPartner();
                    }
                  }}
                  className="text-slate-400 hover:text-slate-600 text-[10px]"
                >
                  Unpair
                </button>
              </div>
            </div>
          )}

          {/* X4: fatal sync problems. peerSync emits these as auth_failed /
              ice_failed / error, none of which the old gate ever matched. */}
          {syncError && (
            <div className="pt-1.5">
              <div className="flex items-start gap-2 p-2.5 rounded-xl bg-rose-50 border border-rose-200">
                <AlertTriangle className="w-3.5 h-3.5 text-rose-500 mt-0.5 shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-[11px] font-bold text-rose-700 leading-relaxed">
                    {syncError.text}
                  </p>
                  {syncError.code === 'passphrase_mismatch' && (
                    <p className="text-[10px] text-rose-600 mt-1 leading-relaxed">
                      Both phones must use the exact same secret passphrase. Re-enter it on one
                      device from the lock screen, then pair again.
                    </p>
                  )}
                  <div className="flex items-center gap-3 mt-1.5">
                    {partnerId && (
                      <button
                        type="button"
                        onClick={() => {
                          tap();
                          reconnectToPartner();
                        }}
                        className="text-[10px] font-bold text-rose-700 underline"
                      >
                        Try again
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => {
                        tap();
                        clearSyncError();
                      }}
                      className="text-[10px] font-bold text-rose-600 underline"
                    >
                      Dismiss
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Non-fatal problem alongside a live connection. */}
          {!syncError && syncWarning && (
            <div className="pt-1.5 flex items-start gap-2 text-[10px] text-amber-700 bg-amber-50 p-2 rounded-xl border border-amber-200/60 leading-relaxed">
              <ShieldAlert className="w-3 h-3 mt-0.5 shrink-0 text-amber-500" />
              <span>{syncWarning.text}</span>
            </div>
          )}

          {syncStatus.state === 'syncing' && (
            <p className="text-[10px] text-slate-500 font-medium">Syncing with your partner...</p>
          )}
        </div>

        {/* My QR Code Card */}
        <div className="text-center bg-slate-50 p-4 rounded-2xl border border-slate-200/70 mb-4">
          <p className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-2">
            Your Device Pairing QR
          </p>
          {/* No QR until the invite is complete. A code that scans into a
              kdf-less link is a silent pairing failure on the other phone. */}
          {inviteReady ? (
            <div className="inline-block p-2 bg-white rounded-xl shadow-sm border border-slate-200">
              <canvas ref={qrCanvasRef} className="mx-auto block" />
            </div>
          ) : (
            <div className="inline-flex flex-col items-center justify-center gap-2 w-[206px] h-[206px] bg-white rounded-xl shadow-sm border border-slate-200 px-4">
              {inviteMetaError ? (
                <>
                  <AlertTriangle className="w-5 h-5 text-amber-500" />
                  <p className="text-[10px] text-slate-500 leading-relaxed">{inviteMetaError}</p>
                </>
              ) : (
                <>
                  <Loader2 className="w-5 h-5 text-slate-300 animate-spin" />
                  <p className="text-[10px] text-slate-400 leading-relaxed">
                    Preparing your invite…
                  </p>
                </>
              )}
            </div>
          )}

          <div className="mt-3 flex items-center justify-center gap-2">
            <button
              onClick={handleCopyCode}
              type="button"
              className="inline-flex items-center gap-1.5 text-xs font-mono font-bold text-slate-600 bg-white px-3 py-1.5 rounded-lg border border-slate-200 hover:bg-slate-50 transition"
              title="Click to copy your Device ID"
            >
              <span>{myPeerId || 'Generating...'}</span>
              <Copy className="w-3.5 h-3.5 text-slate-400" />
            </button>
            {codeCopied && <span className="text-[10px] text-emerald-600 font-bold">Copied ID!</span>}
          </div>

          {/* 1-Tap Share via WhatsApp / Messaging */}
          <div className="mt-3">
            <BouncyButton
              onClick={handleShareInvite}
              disabled={!inviteReady}
              className="w-full py-2.5 text-xs gap-1.5 font-bold shadow-sm disabled:opacity-50"
            >
              <Share2 className="w-4 h-4" />
              <span>
                {copySuccess
                  ? 'Link Copied to Clipboard!'
                  : inviteReady
                    ? 'Share Pairing Link (WhatsApp)'
                    : 'Preparing invite…'}
              </span>
            </BouncyButton>
          </div>
        </div>

        {/* Connect to Partner Section */}
        <div className="space-y-3 mb-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-700">Connect to Partner's Phone</span>
            <button
              onClick={() => {
                tap();
                setPairError('');
                setIsScannerOpen(true);
              }}
              className="inline-flex items-center gap-1 text-xs font-bold text-blush-600 hover:text-blush-700"
            >
              <Camera className="w-3.5 h-3.5" />
              <span>Scan Her QR</span>
            </button>
          </div>

          <form onSubmit={handleManualConnect} className="flex gap-2">
            <input
              type="text"
              value={partnerInputId}
              onChange={(e) => setPartnerInputId(e.target.value)}
              placeholder="Paste Partner's ID or Link..."
              className="flex-1 px-3 py-2 text-xs bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blush-400"
            />
            <BouncyButton type="submit" className="py-2 px-4 text-xs font-bold">
              Pair
            </BouncyButton>
          </form>

          {pairError && (
            <p className="text-[10px] text-rose-600 font-semibold leading-relaxed">{pairError}</p>
          )}

          <p className="text-[10px] text-slate-400 leading-relaxed">
            Pairing opens a direct link, which shares your IP address with that device. Only pair
            with a code you recognise.
          </p>
        </div>

        {/* Encrypted Backup & Restore section */}
        <div className="pt-3 border-t border-slate-100">
          <p className="text-[11px] font-bold text-slate-600 mb-2 flex items-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            <span>Encrypted Vault Backup (Failsafe)</span>
          </p>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={handleExportBackup}
              className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export .vault</span>
            </button>

            <label className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
              <Upload className="w-3.5 h-3.5" />
              <span>Import .vault</span>
              <input
                type="file"
                accept=".vault,.json,application/json"
                onChange={handleImportBackup}
                className="hidden"
              />
            </label>
          </div>

          {backupError && (
            <p className="text-[10px] text-rose-600 font-semibold text-center mt-2 leading-relaxed">
              {backupError}
            </p>
          )}
          {backupNotice && (
            <p className="text-[10px] text-emerald-600 font-medium text-center mt-2 leading-relaxed">
              {backupNotice}
            </p>
          )}
        </div>
      </motion.div>

      {/* In-app camera scanner modal */}
      <QRScannerModal
        isOpen={isScannerOpen}
        onClose={() => setIsScannerOpen(false)}
        onScanSuccess={handleScanSuccess}
      />

      {/* D3: masked passphrase entry, verified before anything is written. */}
      {passphrasePrompt?.mode === 'export' && (
        <PassphrasePrompt
          title="Encrypt this backup"
          description="Use the same passphrase you unlock this vault with. It is checked against your vault before the file is written, so a typo cannot produce a backup nobody can open."
          requireConfirm
          submitLabel="Create backup"
          busy={promptBusy}
          error={promptError}
          onSubmit={runExport}
          onCancel={closePrompt}
        />
      )}

      {passphrasePrompt?.mode === 'import' && (
        <PassphrasePrompt
          title="Unlock this backup"
          description="Enter the passphrase this .vault file was encrypted with. Nothing is written yet — you will see exactly what would change before anything is merged. A merge never replaces your current vault key."
          requireConfirm={false}
          submitLabel="Check backup"
          busy={promptBusy}
          error={promptError}
          onSubmit={runImport}
          onCancel={closePrompt}
        />
      )}

      {/* RISK-1: the confirmation step the import never had. */}
      {importPreview && (
        <ImportPreview
          plan={importPreview.plan}
          relation={importPreview.relation}
          busy={importBusy}
          onConfirm={confirmImport}
          onCancel={() => setImportPreview(null)}
        />
      )}
    </div>
  );
}

export default SyncHubModal;
