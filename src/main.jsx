/**
 * src/main.jsx
 * React entry point, plus registration of the offline service worker.
 *
 * The worker (public/sw.js) is registered in PRODUCTION BUILDS ONLY. During
 * `vite dev` the module graph is served unbundled and rewritten on every save,
 * so a cache-first worker there would serve stale modules and fight HMR.
 */
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import './index.css';

/**
 * Registers the offline cache worker.
 *
 * `updateViaCache: 'none'` stops the browser from serving sw.js itself out of
 * the HTTP cache, so an updated worker is always noticed. When a replacement
 * worker finishes installing while an older one is already in control we ask it
 * to take over immediately: the app ships as a single content-hashed bundle and
 * navigations are network-first, so there is no half-updated state to land in.
 * We deliberately do NOT force a reload - the user is never yanked out of what
 * they were doing.
 */
function registerServiceWorker() {
  if (!import.meta.env.PROD) return;
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;

  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('/sw.js', { scope: '/', updateViaCache: 'none' })
      .then((registration) => {
        registration.addEventListener('updatefound', () => {
          const incoming = registration.installing;
          if (!incoming) return;
          incoming.addEventListener('statechange', () => {
            if (incoming.state === 'installed' && navigator.serviceWorker.controller) {
              incoming.postMessage({ type: 'SKIP_WAITING' });
            }
          });
        });
      })
      .catch(() => {
        // Offline caching is an enhancement. If it fails the app still runs.
      });
  });
}

registerServiceWorker();

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
