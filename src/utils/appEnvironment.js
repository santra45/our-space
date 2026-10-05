/**
 * src/utils/appEnvironment.js
 * What kind of window the app is running in.
 *
 * Every check takes its environment as an argument, defaulting to the real
 * one, so the suite can exercise it without a browser.
 */

const INSTALLED_DISPLAY_MODES = ['standalone', 'fullscreen', 'minimal-ui'];

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
