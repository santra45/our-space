/**
 * public/sw.js
 * Hand-written offline cache for Our Space. No build step, no dependency.
 *
 * SCOPE - what this service worker will and will not touch
 *  - It only ever intercepts SAME-ORIGIN GET requests over http/https. Anything
 *    cross-origin is passed straight through untouched, which is what keeps the
 *    PeerJS signalling traffic out of here: the broker WebSocket
 *    (wss://*.peerjs.com) is not a fetch event at all, and PeerJS's HTTPS calls
 *    to the broker are cross-origin, so both bypass the worker entirely.
 *  - It never touches IndexedDB. A service worker cannot intercept IndexedDB in
 *    the first place, so every encrypted record, photo blob and vaultMeta row is
 *    outside its reach. Nothing decrypted is ever written to the Cache Storage
 *    API - only the static app shell, which is public code anyone can download
 *    from the deployed URL.
 *  - Range requests (media seeking) are passed through, because a partial
 *    response must not be stored as if it were the whole resource.
 *  - Non-GET requests are passed through, so nothing mutating is ever replayed.
 *
 * STRATEGY
 *  - Navigations: network first, falling back to the cached shell when offline.
 *    That way a new deployment is picked up as soon as the network allows,
 *    instead of pinning users to a stale build.
 *  - /assets/* (Vite's content-hashed bundles): cache first. The hash changes
 *    whenever the content changes, so a cache hit is always correct.
 *  - Everything else same-origin: stale-while-revalidate.
 */

const CACHE_VERSION = 'our-space-v1';
const SHELL_CACHE = `${CACHE_VERSION}-shell`;
const RUNTIME_CACHE = `${CACHE_VERSION}-runtime`;

/**
 * Files fetched up front so a cold start with no network still boots.
 * Deliberately short: everything else is picked up as it is requested.
 * Each entry is added individually so one 404 cannot fail the whole install.
 */
const SHELL_ASSETS = ['/', '/index.html', '/manifest.json', '/favicon.svg'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL_CACHE);
      await Promise.all(
        SHELL_ASSETS.map(async (url) => {
          try {
            await cache.add(new Request(url, { cache: 'reload' }));
          } catch {
            // A missing optional asset must not abort installation.
          }
        })
      );
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name !== SHELL_CACHE && name !== RUNTIME_CACHE)
          .map((name) => caches.delete(name))
      );
      await self.clients.claim();
    })()
  );
});

/**
 * The page asks for the update explicitly (see main.jsx). The worker never
 * calls skipWaiting() on its own, so a running session is not swapped onto a
 * new bundle underneath itself.
 */
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

/**
 * True only for responses that are safe to persist: same-origin, 200-ish, and
 * not a partial or opaque response.
 * @param {Response} response
 * @returns {boolean}
 */
function isCacheable(response) {
  return Boolean(response) && response.ok && response.type === 'basic';
}

/**
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function networkFirstNavigation(request) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const response = await fetch(request);
    if (isCacheable(response)) {
      // Fire and forget: a failed cache write must never fail the navigation.
      cache.put('/index.html', response.clone()).catch(() => {});
    }
    return response;
  } catch (err) {
    const cached = (await cache.match(request)) || (await cache.match('/index.html')) || (await cache.match('/'));
    if (cached) return cached;
    throw err;
  }
}

/**
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function cacheFirst(request) {
  const cache = await caches.open(RUNTIME_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (isCacheable(response)) {
    cache.put(request, response.clone()).catch(() => {});
  }
  return response;
}

/**
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function staleWhileRevalidate(request) {
  const cache = await caches.open(RUNTIME_CACHE);
  const cached = await cache.match(request);
  const network = fetch(request)
    .then((response) => {
      if (isCacheable(response)) {
        cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    })
    .catch(() => null);

  if (cached) return cached;
  const response = await network;
  if (response) return response;
  throw new Error('Offline and no cached copy available');
}

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Never replay or cache anything mutating.
  if (request.method !== 'GET') return;

  // Partial responses must not stand in for whole ones.
  if (request.headers.has('range')) return;

  let url;
  try {
    url = new URL(request.url);
  } catch {
    return;
  }

  // Cross-origin (PeerJS broker, STUN, anything else) is none of our business.
  if (url.origin !== self.location.origin) return;
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(cacheFirst(request));
    return;
  }

  event.respondWith(staleWhileRevalidate(request));
});
