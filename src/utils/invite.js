import { isValidBase64, isValidSalt, bufferToBase64, base64ToBuffer } from '../services/crypto.js';

export const PEER_ID_REGEX = /^[a-zA-Z0-9_-]{4,64}$/;

const IV_BYTES = 12;

const MIN_COMPOSITE_ID_LENGTH = 8;

const MAX_FIELD_LENGTH = 2048;

const MAX_COUPLE_NAMES_LENGTH = 120;

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

function cleanSalt(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!isValidSalt(trimmed)) return null;
  return canonicalBase64(trimmed, 16);
}

function cleanStartDate(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return null;
  return Number.isFinite(Date.parse(`${trimmed}T00:00:00`)) ? trimmed : null;
}

function cleanCoupleNames(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.slice(0, MAX_COUPLE_NAMES_LENGTH).trim();
  return trimmed || null;
}

function toUrlSafe(value) {
  if (typeof value !== 'string' || value.length === 0) return null;
  return value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function buildInvite(peerId, raw = {}) {
  const id = typeof peerId === 'string' ? peerId.trim() : '';
  if (!PEER_ID_REGEX.test(id)) return null;

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
  };
}

function fromParams(params) {
  return buildInvite(params.get('connect'), {
    salt: params.get('salt'),
    startDate: params.get('start'),
    coupleNames: params.get('names'),
    canary: params.get('canary'),
    canaryIv: params.get('civ'),
  });
}

export function buildInviteUrl(peerId, salt, optionsOrBaseUrl = null) {
  let baseUrl = null;
  let startDate = null;
  let coupleNames = null;
  let canary = null;
  let canaryIv = null;

  if (typeof optionsOrBaseUrl === 'string') {
    baseUrl = optionsOrBaseUrl;
  } else if (optionsOrBaseUrl && typeof optionsOrBaseUrl === 'object') {
    baseUrl = optionsOrBaseUrl.baseUrl;
    startDate = optionsOrBaseUrl.startDate;
    coupleNames = optionsOrBaseUrl.coupleNames;
    canary = optionsOrBaseUrl.canary;
    canaryIv = optionsOrBaseUrl.canaryIv;
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
  if (canary && canaryIv) {
    hashParams.set('canary', toUrlSafe(canary) || canary);
    hashParams.set('civ', toUrlSafe(canaryIv) || canaryIv);
  }

  return `${base}#${hashParams.toString()}`;
}

export function parseInvite(input) {
  if (!input || typeof input !== 'string') return null;
  const text = input.trim();
  if (!text) return null;

  if (text.includes('#')) {
    const parsed = fromParams(new URLSearchParams(text.substring(text.indexOf('#') + 1)));
    if (parsed) return parsed;
  }

  if (text.includes('connect=')) {
    const cleanQuery = text.startsWith('?') ? text.substring(1) : text;
    const parsed = fromParams(new URLSearchParams(cleanQuery));
    if (parsed) return parsed;
  }

  if (text.includes('.') && !text.startsWith('http')) {
    const separator = text.indexOf('.');
    const idPart = text.slice(0, separator).trim();
    const saltPart = text.slice(separator + 1).trim();
    if (idPart.length >= MIN_COMPOSITE_ID_LENGTH && cleanSalt(saltPart)) {
      const parsed = buildInvite(idPart, { salt: saltPart });
      if (parsed) return parsed;
    }
  }

  return buildInvite(text);
}

export default { PEER_ID_REGEX, buildInviteUrl, parseInvite };
