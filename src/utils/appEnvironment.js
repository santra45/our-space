const INSTALLED_DISPLAY_MODES = ['standalone', 'fullscreen', 'minimal-ui'];

const IN_APP_BROWSERS = [
  ['Instagram', /\bInstagram\b/],
  ['Messenger', /Orca-Android|MessengerForiOS|MessengerLite/],
  ['Facebook', /FBAN\/|FBAV\/|FB_IAB\//],
  ['Snapchat', /\bSnapchat\b/],
  ['TikTok', /musical_ly|BytedanceWebview/],
  ['LinkedIn', /\bLinkedInApp\b/],
  ['LINE', /\bLine\/\d/],
];

export function isInstalledApp(env = globalThis) {
  if (env && typeof env.matchMedia === 'function') {
    for (const mode of INSTALLED_DISPLAY_MODES) {
      try {
        if (env.matchMedia(`(display-mode: ${mode})`).matches) return true;
      } catch {
      }
    }
  }
  return Boolean(env && env.navigator && env.navigator.standalone === true);
}

export function detectInAppBrowser(
  userAgent = globalThis.navigator && globalThis.navigator.userAgent
) {
  if (typeof userAgent !== 'string' || userAgent.length === 0) return null;
  for (const [app, pattern] of IN_APP_BROWSERS) {
    if (pattern.test(userAgent)) return { app };
  }
  if (/; wv\)/.test(userAgent)) return { app: null };
  return null;
}
