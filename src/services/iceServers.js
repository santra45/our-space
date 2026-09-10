/**
 * src/services/iceServers.js
 * Where the two phones look for a route to each other.
 *
 * WHY A RELAY IS NOT OPTIONAL FOR US
 * STUN only tells a phone what its own public address looks like from outside.
 * That is enough when at least one end can be reached directly - typically when
 * someone is on home Wi-Fi. It is NOT enough when both ends sit behind
 * carrier-grade NAT, which is the normal state of affairs on mobile data: there
 * is no reachable address to hand over, so the two phones simply never find
 * each other and the app can only say it could not connect.
 *
 * That case used to be a footnote here, on the assumption that the two people
 * using this are usually in the same room on the same Wi-Fi. For a couple who
 * are apart, it is the DEFAULT case - every sync crosses the internet, and both
 * ends are often on mobile data. So a relay is the difference between "works
 * when we are both on Wi-Fi" and "works".
 *
 * WHAT A RELAY CAN SEE
 * Nothing worth having. Records are already encrypted with the vault key before
 * they reach the transport, and WebRTC wraps that again in DTLS, so a relay
 * forwards ciphertext it cannot read. What it does learn is that two addresses
 * are exchanging data, and how much - the same metadata the signalling broker
 * already sees. That is the whole trade, and it only applies when the relay is
 * used at all: it is a fallback, and ICE prefers a direct route whenever one
 * exists.
 *
 * THE CREDENTIALS ARE PUBLIC, AND THAT IS FINE
 * The default relay is Metered's Open Relay, a free public service whose
 * credentials are published precisely so that anyone can use them. There is
 * nothing here to leak. Point this at your own relay through the environment
 * variables below if you would rather not share a quota with the internet.
 */

/**
 * Vite replaces `import.meta.env` at build time; plain Node leaves it undefined.
 * This module is reachable from the node test suite through peerSync, so it has
 * to survive both.
 */
const env = (typeof import.meta !== 'undefined' && import.meta.env) || {};

/**
 * STUN costs nothing and solves the easy case on its own, so it is always tried
 * first and never replaced by configuration.
 */
const STUN_URLS = Object.freeze([
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:global.stun.twilio.com:3478',
]);

/**
 * Metered's Open Relay: free, no account, 20GB of relayed traffic a month
 * shared across everyone using it. Port 443 over TCP is last on purpose - it is
 * the slowest option and also the one most likely to survive a hostile network.
 */
const DEFAULT_TURN = Object.freeze({
  urls: Object.freeze([
    'turn:openrelay.metered.ca:80',
    'turn:openrelay.metered.ca:443',
    'turn:openrelay.metered.ca:443?transport=tcp',
  ]),
  username: 'openrelayproject',
  credential: 'openrelayproject',
});

function readEnv(source, name) {
  const value = source[name];
  return typeof value === 'string' ? value.trim() : '';
}

/** Splits a comma or whitespace separated list, dropping the empties. */
function parseUrlList(raw) {
  return String(raw || '')
    .split(/[\s,]+/)
    .map((url) => url.trim())
    .filter(Boolean);
}

/**
 * The relay this build will use.
 *
 * Set all three of VITE_TURN_URLS, VITE_TURN_USERNAME and VITE_TURN_CREDENTIAL
 * to use your own. A partial set is ignored rather than half-applied: a relay
 * with the wrong credentials does not fail loudly, it just quietly never
 * connects, which is a far worse thing to ship than the public default.
 *
 * @param {Object} [overrides] - Stands in for the build environment. Only
 *   the tests pass this; the app reads the real one.
 * @returns {{ urls: string[], username: string, credential: string }}
 */
export function resolveTurnConfig(overrides) {
  const source = overrides || env;
  const urls = parseUrlList(readEnv(source, 'VITE_TURN_URLS'));
  const username = readEnv(source, 'VITE_TURN_USERNAME');
  const credential = readEnv(source, 'VITE_TURN_CREDENTIAL');

  if (urls.length > 0 && username && credential) {
    return { urls, username, credential };
  }
  if (urls.length > 0 || username || credential) {
    console.warn(
      '[iceServers] Partial TURN configuration ignored - all three of ' +
        'VITE_TURN_URLS, VITE_TURN_USERNAME and VITE_TURN_CREDENTIAL are needed.'
    );
  }

  return { ...DEFAULT_TURN, urls: [...DEFAULT_TURN.urls] };
}

/**
 * The full ICE server list handed to PeerJS.
 *
 * STUN first, relay last. ICE gathers every candidate and picks the cheapest
 * route that works, so listing a relay does not mean traffic goes through it -
 * only that there is somewhere to fall back to when there is no direct path.
 *
 * @param {Object} [overrides] - See resolveTurnConfig.
 * @returns {Array<{ urls: string|string[], username?: string, credential?: string }>}
 */
export function buildIceServers(overrides) {
  const servers = STUN_URLS.map((urls) => ({ urls }));
  const turn = resolveTurnConfig(overrides);

  if (turn && turn.urls.length > 0) {
    servers.push({
      urls: turn.urls,
      username: turn.username,
      credential: turn.credential,
    });
  }

  return servers;
}

/** @returns {boolean} Whether this build has anywhere to fall back to. */
export function hasTurnConfigured(overrides) {
  const turn = resolveTurnConfig(overrides);
  return !!(turn && turn.urls.length > 0);
}

export default { buildIceServers, resolveTurnConfig, hasTurnConfigured };
