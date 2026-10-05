/**
 * src/utils/appEnvironment.js
 * What kind of window the app is running in.
 *
 * Every check takes its environment as an argument, defaulting to the real
 * one, so the suite can exercise it without a browser.
 */

const INSTALLED_DISPLAY_MODES = ['standalone', 'fullscreen', 'minimal-ui'];

/**
 * Apps that open links in their own built-in browser instead of the phone's.
 * Each of those keeps its own storage, separate from Chrome or Safari, so a
 * space set up inside one stays stuck there while the installed app comes up
 * empty. Checked in order, so Messenger is named before the Facebook tokens it
 * shares.
 */
const IN_APP_BROWSERS = [
  ['Instagram', /\bInstagram\b/],
  ['Messenger', /Orca-Android|MessengerForiOS|MessengerLite/],
  ['Facebook', /FBAN\/|FBAV\/|FB_IAB\//],
  ['Snapchat', /\bSnapchat\b/],
  ['TikTok', /musical_ly|BytedanceWebview/],
  ['LinkedIn', /\bLinkedInApp\b/],
  ['LINE', /\bLine\/\d/],
];

/**
 * True when the app was opened as an installed app (from its home screen icon)
 * rather than in a browser tab.
 *
 * @param {{ matchMedia?: (query: string) => { matches: boolean }, navigator?: { standalone?: boolean } }} [env]
 * @returns {boolean}
 */
export function isInstalledApp(env = globalThis) {
  if (env && typeof env.matchMedia === 'function') {
    for (const mode of INSTALLED_DISPLAY_MODES) {
      try {
        if (env.matchMedia(`(display-mode: ${mode})`).matches) return true;
      } catch {
        // A browser that cannot answer the query is not an installed app.
      }
    }
  }
  // iOS reports a home screen launch here instead of through display-mode.
  return Boolean(env && env.navigator && env.navigator.standalone === true);
}

/**
 * Whether this page is running inside another app's built-in browser.
 *
 * @param {string} [userAgent] - Defaults to the real one.
 * @returns {{ app: string|null }|null} null in an ordinary browser or the
 *   installed app; otherwise the app's name when we recognise it, or
 *   `app: null` for an Android WebView we cannot name.
 */
export function detectInAppBrowser(
  userAgent = globalThis.navigator && globalThis.navigator.userAgent
) {
  if (typeof userAgent !== 'string' || userAgent.length === 0) return null;
  for (const [app, pattern] of IN_APP_BROWSERS) {
    if (pattern.test(userAgent)) return { app };
  }
  // Android's WebView marks itself with "wv". Chrome, Samsung Internet,
  // Firefox, a Chrome tab opened by another app, and the installed app do not.
  if (/; wv\)/.test(userAgent)) return { app: null };
  return null;
}
