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
  Trash2,
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
 * `tampered` is counted and rendered APART from `undecryptable`, and the split
 * lives in db/index.js's verifyRowIntegrity rather than here. One line used to
 * carry both: every integrity failure landed in `undecryptable` under the label
 * "Could not be decrypted by this vault", including rows that decrypted
 * perfectly under the live key and were refused because their header, their
 * photo bytes or their table disagreed with the envelope. So the single row
 * that proves someone edited the user's file was reported to them as "wrong
 * key" - the most reassuring possible reading of the least reassuring fact.
 *
 * A MERGE CAN DESTROY, AND THAT IS THE HEADLINE NUMBER.
 * `planBackupMerge` classifies a write that tombstones a live row as `deleted`,
 * separately from `updated` (db/index.js, the `row.deleted === true &&
 * existing.deleted !== true` branch). Before that counter was rendered here,
 * importing a backup taken AFTER a deletion showed the user "Updated 2" and then
 * dropped two photos on confirm. No attacker is required for that: device A
 * deletes a photo and exports, the user imports that export on device B which
 * still holds the only copy, and B obeys the tombstone. So `deleted` gets its
 * own loud tile, its own sentence, and its own acknowledgement.
 *
 * Every `relation` compareVaultIdentity can return has a branch here. 'unknown'
 * used to have none, so a file whose origin could not be established rendered
 * identically to the user's own backup - same counts, no banner, live Merge
 * button. It now says so out loud.
 *
 * BUT ORIGIN IS THE WRONG THING TO KEY A WARNING ON, AND THAT WAS THE HOLE.
 * Keying the only unproven-origin banner on relation === 'unknown' left the
 * CREATE path silent, and the create path is the permissive one by design. The
 * re-seal kill chain fixed in d9239ab arrived exactly there: a file whose own
 * vaultMeta classifies as 'same' - which costs a forger nothing, because
 * readBackupVaultIdentity reads that identity out of the file itself - showing
 * "Added: 2, Deleted permanently: 0" and no banner whatsoever. So the second
 * banner is keyed on `added > 0` instead, with no reference to origin at all,
 * and it names the thing the counts do not: a created record is a real record on
 * this device, and this device hands its records to the partner (db/index.js
 * getManifest enumerates every primary key in every synced table; peerSync
 * `_handleSyncRequest` serves `db.table(req.table).get(req.id)` for anything the
 * partner asks for).
 *
 * DELIBERATE: the extra confirmation is keyed on WHAT THE PLAN DOES, not on the
 * file's label. 'unknown' gets a loud banner but no gate beyond the preview
 * itself; a plan with `deleted > 0` gets a gate whatever its origin says. The
 * reasoning, since the opposite choice is the tempting one:
 *
 *   - A label gate is bypassable by the attacker it is aimed at. Identity is
 *     read out of the file's own vaultMeta (readBackupVaultIdentity), so anyone
 *     who can build a hostile file can simply leave a matching vaultMeta in
 *     place and classify as 'same'. Gating on 'unknown' would therefore stop
 *     only the forger who volunteered to be caught, while charging every honest
 *     user with a truncated file.
 *   - The per-row gate is what actually holds, and it is two-tier. Every
 *     candidate must carry ciphertext that AES-GCM verifies under THIS device's
 *     live key (planBackupMerge -> verifyRowIntegrity ->
 *     recordCarriesAuthenticatedPayload + decryptRecord). On top of that, a row
 *     may only OVERWRITE OR TOMBSTONE a row that already exists when its
 *     plaintext id / updatedAt / deleted header is sealed inside that same
 *     ciphertext - `recordHasAuthenticatedHeader`, i.e. a v2 envelope, enforced
 *     at plan time and re-asserted inside the applyBackupMerge transaction. A
 *     v1 row may still create at an unused id, which is what keeps restoring an
 *     old backup working.
 *   - Neither tier stops the loss this dialog is really about. A genuinely newer
 *     tombstone is not an attack, it is the sync rule working, and it is exactly
 *     what erases the last copy of a photo when the user imports device A's
 *     post-deletion export onto device B. No cryptographic gate can refuse that
 *     on the user's behalf; only the user can. That is an argument for naming
 *     the destruction, not for a confirmation PHRASE - a phrase is reserved for
 *     replacing the vault salt, where the loss is total and instant, and reusing
 *     it here would train the user to type it past routine merges. So the
 *     destructive count is named in its own tile, in an acknowledgement that
 *     must be ticked, on the button, and in the post-merge notice.
 *
 * DO NOT re-derive the record gates anywhere in the rendered copy beyond the two
 * places that already do it: the second sentence of the "Origin not established"
 * banner, and the second sentence of the "would be created" banner. How strong
 * an envelope is belongs to crypto.js and has changed more than once; a UI
 * paragraph that restates it goes stale in silence, and this component has
 * already shipped one such false guarantee. Both surviving restatements are
 * deliberately the SAME sentence about the same rule - may create; may overwrite
 * or delete only with a sealed header on vault-authored content - so there is
 * one claim to re-check, not two.
 */
function ImportPreview({ plan, relation, busy, onConfirm, onCancel }) {
  // Defaulted, not destructured raw: an older plan object missing a counter would
  // otherwise make `willWrite` NaN, which is neither 0 nor a number - the button
  // would light up and offer to "Merge NaN".
  const t = plan.totals || {};
  const added = t.added || 0;
  const updated = t.updated || 0;
  const deleted = t.deleted || 0;
  const stale = t.stale || 0;
  const invalid = t.invalid || 0;
  const undecryptable = t.undecryptable || 0;
  const tampered = t.tampered || 0;
  const unauthenticated = t.unauthenticated || 0;
  // Deletions are writes. Excluding them from this total once made a merge whose
  // entire effect was destroying rows render as "Nothing to write".
  const willWrite = added + updated + deleted;
  // Every reason a row can be held back, added up. The individual counts stay
  // exactly as the plan reports them; only the DISPLAY is collapsed to one line.
  const leftOut = stale + invalid + undecryptable + tampered + unauthenticated;
  const destructive = deleted > 0;
  const foreign = relation === 'foreign';
  const [ackDelete, setAckDelete] = useState(false);
  const [showWhy, setShowWhy] = useState(false);

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100 max-h-[85vh] overflow-y-auto"
      >
        <h3 className="text-base font-bold text-slate-800">Before we add these</h3>
        <p className="mt-1 text-[11px] text-slate-500 leading-relaxed">
          Nothing has been added yet. Here is what would happen.
        </p>

        {foreign && (
          <div className="mt-3 p-3 rounded-xl bg-rose-50 border-2 border-rose-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-rose-800 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">This is from somewhere else</p>
              <p className="mt-1">
                This file came from a different space, not yours. If you were not expecting it,
                please tap Cancel.
              </p>
            </div>
          </div>
        )}

        {relation === 'unknown' && (
          <div className="mt-3 p-3 rounded-xl bg-amber-50 border-2 border-amber-300 flex items-start gap-2">
            <ShieldAlert className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
            <div className="text-[11px] text-amber-900 leading-relaxed">
              <p className="font-extrabold uppercase tracking-wide">We are not sure where this is from</p>
              <p className="mt-1">
                This file does not say which space it belongs to. Only things that open with your
                passphrase can be added. If you were not expecting it, please tap Cancel.
              </p>
            </div>
          </div>
        )}

        {relation === 'no-local-vault' && (
          <div className="mt-3 p-2.5 rounded-xl bg-amber-50 border border-amber-200 text-[11px] text-amber-900 leading-relaxed">
            We could not match this file to this phone. Only the things that open with your
            passphrase will be added.
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

        {/* Deliberately NOT a third cell in the grid above. This number is not a
            peer of "Added" and "Updated" - it is the only one that destroys
            something, so it gets full width, a different colour, and a sentence
            saying what is lost. A user scanning three equal tiles reads three
            equal outcomes. */}
        <div
          className={`mt-2 p-3 rounded-xl border-2 flex items-start gap-2.5 ${
            destructive ? 'bg-rose-50 border-rose-300' : 'bg-slate-50 border-slate-200'
          }`}
        >
          <Trash2
            className={`w-4 h-4 shrink-0 mt-0.5 ${destructive ? 'text-rose-600' : 'text-slate-400'}`}
          />
          <div className="min-w-0 flex-1">
            <p className="flex items-baseline justify-between gap-2">
              <span
                className={`text-[10px] font-extrabold uppercase tracking-wide ${
                  destructive ? 'text-rose-800' : 'text-slate-500'
                }`}
              >
                Removed for good
              </span>
              <span
                className={`text-lg font-extrabold leading-none ${
                  destructive ? 'text-rose-700' : 'text-slate-400'
                }`}
              >
                {deleted}
              </span>
            </p>
            <p
              className={`mt-1 text-[11px] leading-relaxed ${
                destructive ? 'text-rose-800' : 'text-slate-500'
              }`}
            >
              {/* The timeline runs the other way round: a tombstone inside the
                  file was necessarily written BEFORE the file was exported. The
                  deletion is newer than YOUR copy, not newer than the file. */}
              {/* U2: this reassurance is about DELETION only. It never meant
                  "this import is harmless" - created rows still travel on to the
                  partner's phone. The paragraph that used to spell that out has
                  been dropped from the UI as unreadable jargon; the rule itself
                  is unchanged in db/index.js. */}
              {destructive
                ? `This will remove ${deleted} ${deleted === 1 ? 'thing' : 'things'} you still ` +
                  `have, here and on the other phone. That cannot be undone.`
                : 'Nothing you still have gets removed.'}
            </p>
          </div>
        </div>

        {/* The five per-reason counters above are still computed - they are the
            numbers the plan is made of - but the user gets one friendly line and
            an optional plain-English "why". Five forensic categories on a
            scrapbook screen is a security console, not a love letter. */}
        {leftOut > 0 && (
          <div className="mt-2 px-1">
            <div className="flex items-baseline justify-between gap-2 text-[11px] text-slate-600">
              <span>
                {leftOut} {leftOut === 1 ? 'thing was' : 'things were'} left out
              </span>
              <button
                type="button"
                onClick={() => setShowWhy((v) => !v)}
                className="text-[10px] font-bold text-slate-400 hover:text-slate-600 underline"
              >
                Why?
              </button>
            </div>
            {showWhy && (
              <p className="mt-1 text-[10px] text-slate-500 leading-relaxed">
                Some are older than the copies you already have, and some could not be opened with
                your passphrase.
              </p>
            )}
          </div>
        )}

        {/* The long explanations that used to live here (what a created row can
            and cannot do, how last-write-wins works, which id/updatedAt/deleted
            fields are sealed) were internal reasoning rendered at the user. The
            RULES are unchanged and enforced in db/index.js planBackupMerge; only
            the essay is gone. */}

        {/* The gate is on the destructive outcome, not on the file's label - see
            the block comment above. It is a deliberate act naming the count, not
            a confirmation phrase: a phrase belongs to salt replacement, and
            spending it here would teach the user to type it past routine imports. */}
        {destructive && (
          <label className="mt-3 flex items-start gap-2 p-2.5 rounded-xl bg-rose-50 border border-rose-200 cursor-pointer">
            <input
              type="checkbox"
              checked={ackDelete}
              onChange={(e) => setAckDelete(e.target.checked)}
              disabled={busy}
              className="mt-0.5 w-3.5 h-3.5 shrink-0 accent-rose-600"
            />
            <span className="text-[11px] font-bold text-rose-800 leading-relaxed">
              I understand {deleted} {deleted === 1 ? 'thing' : 'things'} I still have will be gone
              for good.
            </span>
          </label>
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
            type="button"
            onClick={onConfirm}
            disabled={busy || willWrite === 0 || (destructive && !ackDelete)}
            className={`py-2.5 rounded-2xl text-white text-xs font-bold shadow-sm disabled:opacity-50 inline-flex items-center justify-center gap-1.5 ${
              destructive
                ? 'bg-rose-600 shadow-rose-300/50 hover:bg-rose-700'
                : 'bg-blush-500 shadow-blush-300/50 hover:bg-blush-600'
            }`}
          >
            {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>
              {willWrite === 0
                ? 'Nothing to add'
                : busy
                  ? 'Adding…'
                  : destructive
                    ? `Add, removing ${deleted}`
                    : `Add ${willWrite}`}
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
          setInviteMetaError('Nothing is set up on this phone yet, so we cannot make an invite.');
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
          'We could not get your invite ready. Close any other tabs with Our Space open, then ' +
            'open this again.'
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
        inviteMetaError || 'Your invite is not quite ready. Give it a second and try again.'
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
        'That does not look like a pairing code or invite link. Paste the whole link your partner sent you, or their code.'
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
        setPromptError('Nothing is set up on this phone yet, so there is nothing to save.');
        return;
      }

      const matches = await verifyPassphraseAgainstMeta(passphrase, meta);
      if (!matches) {
        setPromptError(
          'That is not the passphrase you open Our Space with. The copy has to use the same one, or nothing could ever bring it back.'
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
      anchor.download = `our-space-${new Date().toISOString().split('T')[0]}.vault`;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();

      closePrompt();
      setBackupNotice('Copy saved. Only that passphrase opens it. 💕');
      celebration();
    } catch (err) {
      console.error('Could not create the backup:', err);
      setPromptError('We could not save that copy. Please try again.');
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
        `That file is ${Math.round(file.size / (1024 * 1024))}MB — a bit big. The most we can take is ${MAX_BACKUP_FILE_MB}MB.`
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
        setBackupError('That does not look like a file Our Space saved.');
        return;
      }
      if (!container || typeof container !== 'object' || Array.isArray(container)) {
        setBackupError('That does not look like a file Our Space saved.');
        return;
      }
      setPassphrasePrompt({ mode: 'import', container });
    } catch (err) {
      console.error('Could not read that file:', err);
      setBackupError('We could not read that file. Please try another one.');
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
        setPromptError('Our Space is locked right now. Unlock it and try again.');
        return;
      }

      const identity = readBackupVaultIdentity(decrypted.tables);
      const localRead = await db.readVaultIdentity();
      const relation = compareVaultIdentity(identity, localRead);

      // Fail closed: if we cannot read our own identity we cannot tell whether
      // this file belongs here, and a wrong answer costs the user their photos.
      if (relation === 'unknown' && !localRead.ok) {
        setPromptError(
          'We could not read what is already on this phone, so we stopped. Nothing changed. Close ' +
            'any other tabs with Our Space open and try again.'
        );
        return;
      }

      const plan = await db.planBackupMerge(decrypted.tables, cryptoKey);
      closePrompt();
      setImportPreview({ plan, relation, identity });
    } catch (err) {
      console.error('Could not open that backup file:', err);
      setPromptError('We could not open that file. Check the passphrase and try again.');
    } finally {
      setPromptBusy(false);
    }
  };

  /**
   * Applies a plan the user has now seen and accepted.
   *
   * The notice has to name deletions. It used to say "Merged N record(s)" after
   * a merge whose entire effect was tombstoning N live rows - the one word the
   * user needed was the one word missing.
   *
   * applyBackupMerge reports only how many rows it wrote per table, not how many
   * of those were tombstones, so the exact figure is derived rather than
   * reported: every planned write lands unless it was superseded between the
   * preview and the confirm, so with `supersededSincePreview === 0` the planned
   * `deleted` count IS what happened, and otherwise it is an upper bound. Say
   * which of the two this was instead of picking one and hoping.
   */
  const confirmImport = async () => {
    if (!importPreview) return;
    const plannedDeletes = importPreview.plan?.totals?.deleted || 0;
    setImportBusy(true);
    setBackupError('');
    try {
      const result = await db.applyBackupMerge(importPreview.plan);
      const written = Object.values(result.written || {}).reduce((sum, n) => sum + n, 0);
      const supersededNote = result.supersededSincePreview
        ? ` ${result.supersededSincePreview} already had a newer copy here, so we left those alone.`
        : '';
      const deleteNote =
        plannedDeletes > 0
          ? result.supersededSincePreview
            ? ` Up to ${plannedDeletes} of them removed something you had.`
            : ` ${plannedDeletes} of them removed something you had — those are gone for good.`
          : '';
      setImportPreview(null);
      setBackupNotice(`Added ${written} ${written === 1 ? 'thing' : 'things'}.${deleteNote}${supersededNote}`);
      // No celebration buzz for a merge that erased something. The haptic is
      // part of the message, and congratulating a data loss is a lie told in
      // vibration.
      if (plannedDeletes > 0) tap();
      else celebration();
    } catch (err) {
      console.error('The backup merge failed:', err);
      setImportPreview(null);
      setBackupError('That did not finish. Please try again.');
    } finally {
      setImportBusy(false);
    }
  };

  if (!isOpen) return null;

  /* --------------------------------------------------------------------- *
   * Status rendering
   * --------------------------------------------------------------------- */

  let statusDot = 'bg-amber-400';
  let statusLabel = 'Waiting to connect';
  if (isAuthorized) {
    statusDot = 'bg-emerald-500 animate-pulse';
    statusLabel = 'Connected to Partner';
  } else if (isHandshaking) {
    statusDot = 'bg-amber-500 animate-ping';
    statusLabel = 'Making sure it is them…';
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
          <p className="text-xs text-slate-400">Your two phones, straight to each other</p>
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
                <span className="text-slate-500 font-medium shrink-0">How you are connected:</span>
                {connectionType === 'direct' ? (
                  <span className="inline-flex items-center gap-1 font-bold text-emerald-700 bg-emerald-100/80 px-2.5 py-0.5 rounded-full border border-emerald-200 shadow-sm">
                    <Zap className="w-3 h-3 text-amber-500 fill-amber-400" />
                    <span>Phone to phone ⚡</span>
                  </span>
                ) : connectionType === 'relayed' ? (
                  <span className="inline-flex items-center gap-1 font-semibold text-indigo-700 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200">
                    <ShieldCheck className="w-3 h-3 text-indigo-500" />
                    <span>Via a helper 🛡️</span>
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full border border-slate-200">
                    <HelpCircle className="w-3 h-3 text-slate-400" />
                    <span>Not sure</span>
                  </span>
                )}
              </div>
              {connectionType !== 'direct' && connectionType !== 'relayed' && (
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  Connected. We cannot tell exactly how it routed, but your things are still
                  private.
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
            Only pair with a code you recognise.
          </p>
        </div>

        {/* Encrypted Backup & Restore section */}
        <div className="pt-3 border-t border-slate-100">
          <p className="text-[11px] font-bold text-slate-600 mb-2 flex items-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            <span>Keep a copy, just in case</span>
          </p>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={handleExportBackup}
              className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Save a copy</span>
            </button>

            <label className="flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-slate-200 text-[11px] font-semibold text-slate-600 hover:bg-slate-50 cursor-pointer">
              <Upload className="w-3.5 h-3.5" />
              <span>Bring in a copy</span>
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
          title="Lock this copy"
          description="Use the same passphrase you open Our Space with. We check it before writing the file, so a typo cannot leave you with a copy nobody can open."
          requireConfirm
          submitLabel="Save the copy"
          busy={promptBusy}
          error={promptError}
          onSubmit={runExport}
          onCancel={closePrompt}
        />
      )}

      {passphrasePrompt?.mode === 'import' && (
        <PassphrasePrompt
          title="Open this copy"
          description="Enter the passphrase this file was saved with. Nothing is added yet — you will see exactly what would change first."
          requireConfirm={false}
          submitLabel="Take a look"
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
