/**
 * src/utils/invite.js
 * Builds and parses the P2P pairing invite (link, QR payload, composite code).
 *
 * WHY THIS FILE IS SECURITY-SENSITIVE
 * Everything it returns is attacker-controlled the moment a user opens a link
 * somebody sent them. Two of those fields feed cryptography directly:
 *
 *  - `salt` becomes the PBKDF2 salt for the joining device's vault key. An
 *    unvalidated salt used to flow straight through to `atob()`, so a 3-character
 *    string produced a 2-byte salt and a silently-wrong key, and a non-base64
 *    character threw out of vault initialization. Every return path now gates on
 *    `isValidSalt()` (base64 of exactly 16 bytes) and drops a malformed salt.
 *
 *  - `kdfIterations` says which PBKDF2 count the inviter's vault uses. This is
 *    required, not an optimisation: a vault created before the OWASP bump
 *    derives at 250,000, and a joiner who assumed 600,000 would silently produce
 *    a different key. Like the salt it is a public KDF parameter.
 *
 * WHY THE CANARY IS PARSED BUT NEVER SENT
 * `canary`/`canaryIv` would let a joiner prove the typed passphrase matches the
 * inviter's at the moment of typing. Parsing them is supported, and
 * VaultContext verifies them when present - but nothing in this app puts them
 * in a link, deliberately. The canary is a ciphertext under the vault key, so
 * publishing it hands an OFFLINE passphrase-cracking oracle to every party that
 * relays the invite: the messenger, anyone forwarded the link, anyone who
 * photographs the QR. Against a human-chosen phrase that is a real attack, and
 * the vault passphrase is the only secret this product has.
 *
 * The typo it would catch is already caught: the P2P handshake encrypts every
 * frame under the vault key, so mismatched passphrases fail authentication and
 * surface as `passphrase_mismatch` seconds later. Trading the single secret's
 * offline strength for a slightly earlier error message is a bad deal. The
 * parameter stays supported for a future flow that can deliver it over an
 * already-authenticated channel, where it costs nothing.
 *
 * The salt is canonicalised to standard base64 on the way out of `parseInvite`.
 * It is compared as a STRING elsewhere (`existing.salt === salt` decides whether
 * a re-pair is destructive), so a transport that swapped `+/` for `-_` would
 * otherwise make an identical vault look like a foreign one and prompt the user
 * to erase it.
 *
 * Zero knowledge: all of this rides in the URL fragment, which browsers never
 * send to a web server. It does travel through whatever chat app relays the
 * link - see the README's invite-link note.
 */
// Explicit `.js` extension (the only one in src/): it lets Node resolve this
// module directly, so the invite parser - the one place that turns a stranger's
// link into cryptographic inputs - is covered by test-crypto.mjs rather than by
// hope. Vite resolves it identically.
import { isValidBase64, isValidSalt, bufferToBase64, base64ToBuffer } from '../services/crypto.js';

export const PEER_ID_REGEX = /^[a-zA-Z0-9_-]{4,64}$/;

/** AES-GCM IV length, in bytes. `canaryIv` must be exactly this. */
const IV_BYTES = 12;

/**
 * Shortest id accepted from the ambiguous "peerId.salt" composite form.
 *
 * Generated ids are `love-` plus 16 base32 characters, so this only rejects
 * things no real id looks like. Without it `parseInvite('ourspace.app')` split
 * into a valid-looking id and a salt of `'app'`, and any bare domain, filename
 * or version string a user pasted became an "invite" that created a vault
 * permanently divergent from the partner's.
 */
const MIN_COMPOSITE_ID_LENGTH = 8;

/** Ceiling on any single field parsed out of a link, to bound a hostile payload. */
const MAX_FIELD_LENGTH = 2048;

/** Longest couple name accepted from an invite. Matches VaultContext. */
const MAX_COUPLE_NAMES_LENGTH = 120;

/** Bounds on a KDF iteration count carried by an invite. Matches resolveKdfIterations. */
const MIN_KDF_ITERATIONS = 1000;
const MAX_KDF_ITERATIONS = 10000000;

/**
 * Re-encodes base64 into its canonical standard-alphabet, padded form.
 * @param {unknown} value
 * @param {number} [byteLength] - Required exact decoded length, when known.
 * @returns {string|null} Null when `value` is not valid base64 of that length.
 */
function canonicalBase64(value, byteLength) {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_FIELD_LENGTH) {
    return null;
  }
  if (!isValidBase64(value, byteLength)) return null;
  try {
    return bufferToBase64(base64ToBuffer(value));
  } catch {
    return null;
  }
}

/** @returns {string|null} A canonical 16-byte vault salt, or null. */
function cleanSalt(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!isValidSalt(trimmed)) return null;
  return canonicalBase64(trimmed, 16);
}

/** @returns {string|null} A 'YYYY-MM-DD' calendar date, or null. */
function cleanStartDate(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return null;
  return Number.isFinite(Date.parse(`${trimmed}T00:00:00`)) ? trimmed : null;
}

/** @returns {string|null} A bounded couple-name string, or null. */
function cleanCoupleNames(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.slice(0, MAX_COUPLE_NAMES_LENGTH).trim();
  return trimmed || null;
}

/**
 * Rewrites base64 into the URL-safe alphabet with padding stripped, for the
 * wire only. `parseInvite` canonicalises it straight back, so nothing
 * downstream ever sees the URL-safe form.
 *
 * This is purely about transport: standard base64 contains `+`, `/` and `=`,
 * which URLSearchParams percent-encodes to three characters each. On a QR code
 * that is wasted modules, and in a chat client that "helpfully" reformats a
 * link it is a whole class of mangling bugs that simply cannot happen now.
 *
 * @param {unknown} value
 * @returns {string|null}
 */
function toUrlSafe(value) {
  if (typeof value !== 'string' || value.length === 0) return null;
  return value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * @returns {number|null} A sane PBKDF2 iteration count, or null.
 * Strict on purpose: `parseInt` would happily turn '600000; DROP' into 600000
 * and '1e9' into 1, and this value decides how a vault key is derived.
 */
function cleanIterations(value) {
  let parsed = null;
  if (typeof value === 'number') {
    parsed = value;
  } else if (typeof value === 'string' && /^\d{1,9}$/.test(value.trim())) {
    parsed = Number(value.trim());
  }
  if (!Number.isInteger(parsed)) return null;
  if (parsed < MIN_KDF_ITERATIONS || parsed > MAX_KDF_ITERATIONS) return null;
  return parsed;
}

/**
 * Normalises one parsed invite. A malformed optional field is DROPPED rather
 * than passed through, so a caller can never derive against a hostile salt.
 * @returns {Object|null}
 */
function buildInvite(peerId, raw = {}) {
  const id = typeof peerId === 'string' ? peerId.trim() : '';
  if (!PEER_ID_REGEX.test(id)) return null;

  // The canary and its IV are one artefact: half of a passphrase proof proves
  // nothing, and a caller that saw only `canary` populated could reasonably
  // believe verification was available when it is not. All or neither.
  const canary = canonicalBase64(raw.canary);
  const canaryIv = canonicalBase64(raw.canaryIv, IV_BYTES);
  const hasProof = Boolean(canary && canaryIv);

  return {
    partnerPeerId: id,
    salt: cleanSalt(raw.salt),
    startDate: cleanStartDate(raw.startDate),
    coupleNames: cleanCoupleNames(raw.coupleNames),
    canary: hasProof ? canary : null,
    canaryIv: hasProof ? canaryIv : null,
    kdfIterations: cleanIterations(raw.kdfIterations),
  };
}

/** Pulls the invite fields out of a URLSearchParams. */
function fromParams(params) {
  return buildInvite(params.get('connect'), {
    salt: params.get('salt'),
    startDate: params.get('start'),
    coupleNames: params.get('names'),
    canary: params.get('canary'),
    canaryIv: params.get('civ'),
    kdfIterations: params.get('kdf'),
  });
}

/**
 * Builds the full invite URL. Everything rides in the hash fragment, which is
 * never transmitted to a web server.
 *
 * @param {string} peerId
 * @param {string} salt - The inviter's vault salt (base64, 16 bytes).
 * @param {{ baseUrl?: string, startDate?: string, coupleNames?: string,
 *           canary?: string, canaryIv?: string, kdfIterations?: number }|string} [optionsOrBaseUrl]
 * @returns {string}
 */
export function buildInviteUrl(peerId, salt, optionsOrBaseUrl = null) {
  let baseUrl = null;
  let startDate = null;
  let coupleNames = null;
  let canary = null;
  let canaryIv = null;
  let kdfIterations = null;

  if (typeof optionsOrBaseUrl === 'string') {
    baseUrl = optionsOrBaseUrl;
  } else if (optionsOrBaseUrl && typeof optionsOrBaseUrl === 'object') {
    baseUrl = optionsOrBaseUrl.baseUrl;
    startDate = optionsOrBaseUrl.startDate;
    coupleNames = optionsOrBaseUrl.coupleNames;
    canary = optionsOrBaseUrl.canary;
    canaryIv = optionsOrBaseUrl.canaryIv;
    kdfIterations = optionsOrBaseUrl.kdfIterations;
  }

  const base =
    baseUrl ||
    (typeof window !== 'undefined'
      ? `${window.location.origin}${window.location.pathname}`
      : 'https://ourspace.app/');

  const hashParams = new URLSearchParams();
  if (peerId) hashParams.set('connect', peerId);
  if (salt) hashParams.set('salt', toUrlSafe(salt) || salt);
  if (startDate) hashParams.set('start', startDate);
  if (coupleNames) hashParams.set('names', coupleNames);
  if (Number.isFinite(kdfIterations)) hashParams.set('kdf', String(kdfIterations));
  // NOTHING in this app passes these, on purpose - see the canary note in the
  // module header. Supported so a future flow that has an already-authenticated
  // channel can reuse this builder without publishing an offline oracle.
  if (canary && canaryIv) {
    hashParams.set('canary', toUrlSafe(canary) || canary);
    hashParams.set('civ', toUrlSafe(canaryIv) || canaryIv);
  }

  return `${base}#${hashParams.toString()}`;
}

/**
 * Parses an invite from:
 *  1. A full URL          https://domain.com/#connect=love-123&salt=abc
 *  2. A hash string       #connect=love-123&salt=abc
 *  3. A query string      connect=love-123&salt=abc
 *  4. A composite code    love-123.abc
 *  5. A bare peer id      love-123
 *
 * Optional fields that fail validation are returned as null. A peer id that
 * fails validation makes the whole invite null - there is nothing to dial.
 *
 * @param {string} input
 * @returns {{ partnerPeerId: string, salt: string|null, startDate: string|null,
 *             coupleNames: string|null, canary: string|null, canaryIv: string|null,
 *             kdfIterations: number|null } | null}
 */
export function parseInvite(input) {
  if (!input || typeof input !== 'string') return null;
  const text = input.trim();
  if (!text) return null;

  // Case 1 & 2: contains '#'
  if (text.includes('#')) {
    const parsed = fromParams(new URLSearchParams(text.substring(text.indexOf('#') + 1)));
    if (parsed) return parsed;
  }

  // Case 3: bare query-string form
  if (text.includes('connect=')) {
    const cleanQuery = text.startsWith('?') ? text.substring(1) : text;
    const parsed = fromParams(new URLSearchParams(cleanQuery));
    if (parsed) return parsed;
  }

  // Case 4: composite "peerId.salt".
  // Deliberately strict: BOTH halves must validate. Accepting a valid-looking
  // id with an unvalidated salt is how 'ourspace.app' used to become an invite.
  if (text.includes('.') && !text.startsWith('http')) {
    const separator = text.indexOf('.');
    const idPart = text.slice(0, separator).trim();
    const saltPart = text.slice(separator + 1).trim();
    if (idPart.length >= MIN_COMPOSITE_ID_LENGTH && cleanSalt(saltPart)) {
      const parsed = buildInvite(idPart, { salt: saltPart });
      if (parsed) return parsed;
    }
  }

  // Case 5: bare peer id
  return buildInvite(text);
}

export default { PEER_ID_REGEX, buildInviteUrl, parseInvite };
