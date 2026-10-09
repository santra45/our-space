const env = (typeof import.meta !== 'undefined' && import.meta.env) || {};

const STUN_URLS = Object.freeze([
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:global.stun.twilio.com:3478',
]);

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

function parseUrlList(raw) {
  return String(raw || '')
    .split(/[\s,]+/)
    .map((url) => url.trim())
    .filter(Boolean);
}

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

export function hasTurnConfigured(overrides) {
  const turn = resolveTurnConfig(overrides);
  return !!(turn && turn.urls.length > 0);
}

export default { buildIceServers, resolveTurnConfig, hasTurnConfigured };
