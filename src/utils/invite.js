/**
 * src/utils/invite.js
 * Utilities for formatting and parsing P2P pairing invite links and codes
 * Ensures zero knowledge: hash fragments (#) are never sent to web servers
 */

export const PEER_ID_REGEX = /^[a-zA-Z0-9_-]{4,64}$/;

/**
 * Builds the full invite URL containing peer ID and vault salt in the URL hash.
 * Fragments (#) are never sent to the web server, preserving zero knowledge.
 */
export function buildInviteUrl(peerId, salt, baseUrl = null) {
  const base = baseUrl || (typeof window !== 'undefined' ? `${window.location.origin}${window.location.pathname}` : 'https://ourspace.app/');
  const hashParams = new URLSearchParams();
  if (peerId) hashParams.set('connect', peerId);
  if (salt) hashParams.set('salt', salt);
  return `${base}#${hashParams.toString()}`;
}

/**
 * Parses an invite from:
 * 1. Full URL (e.g. https://domain.com/#connect=love-123&salt=abc)
 * 2. Hash string (#connect=love-123&salt=abc)
 * 3. Query string (connect=love-123&salt=abc)
 * 4. Composite code (love-123.abc)
 * 5. Plain Peer ID (love-123)
 * @param {string} input
 * @returns {{ partnerPeerId: string, salt: string | null } | null}
 */
export function parseInvite(input) {
  if (!input || typeof input !== 'string') return null;
  const text = input.trim();
  if (!text) return null;

  // Case 1 & 2: Contains '#'
  if (text.includes('#')) {
    const hashPart = text.substring(text.indexOf('#') + 1);
    const params = new URLSearchParams(hashPart);
    const connect = params.get('connect');
    const salt = params.get('salt');
    if (connect && PEER_ID_REGEX.test(connect.trim())) {
      return {
        partnerPeerId: connect.trim(),
        salt: salt ? salt.trim() : null,
      };
    }
  }

  // Case 3: URLSearchParams format (e.g. connect=love-123&salt=abc)
  if (text.includes('connect=')) {
    const cleanQuery = text.startsWith('?') ? text.substring(1) : text;
    const params = new URLSearchParams(cleanQuery);
    const connect = params.get('connect');
    const salt = params.get('salt');
    if (connect && PEER_ID_REGEX.test(connect.trim())) {
      return {
        partnerPeerId: connect.trim(),
        salt: salt ? salt.trim() : null,
      };
    }
  }

  // Case 4: Composite code "peerId.salt"
  if (text.includes('.') && !text.startsWith('http')) {
    const [idPart, ...saltParts] = text.split('.');
    const saltPart = saltParts.join('.');
    if (PEER_ID_REGEX.test(idPart.trim())) {
      return {
        partnerPeerId: idPart.trim(),
        salt: saltPart.trim() || null,
      };
    }
  }

  // Case 5: Plain Peer ID
  if (PEER_ID_REGEX.test(text)) {
    return {
      partnerPeerId: text,
      salt: null,
    };
  }

  return null;
}
