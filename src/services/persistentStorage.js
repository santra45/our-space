/**
 * src/services/persistentStorage.js
 * Asks the browser to keep this site's storage instead of treating it as
 * disposable.
 *
 * WHY THIS EXISTS
 * Unless a site asks, its IndexedDB is "best-effort": the browser may evict it
 * when the device runs low on space, without telling anyone. For this app that
 * is the whole vault - the salt, every sealed record and every photo. The phone
 * then opens on an empty lock screen, which anyone would reasonably read as
 * "set it up again", and that is exactly how a phone ends up on a second,
 * separate space that its partner can never see.
 *
 * Persistent storage is exempt from that eviction. Chromium grants it without
 * a prompt to sites it considers important, and an installed app qualifies;
 * Firefox asks the user. It does NOT survive the user, or a cleaner app,
 * clearing site data on purpose. Nothing can.
 *
 * Never throws and never blocks: an unsupported browser or a refusal leaves the
 * app exactly as it was before this existed.
 */

/**
 * @param {{ storage?: StorageManager }} [options] - `storage` is injectable so
 *   the suite can run this without a browser. Defaults to navigator.storage.
 * @returns {Promise<'persisted'|'granted'|'denied'|'unsupported'>}
 *   `persisted` means it already was, so nothing was asked.
 */
export async function requestPersistentStorage(options = {}) {
  const storage =
    'storage' in options ? options.storage : globalThis.navigator && globalThis.navigator.storage;
  if (!storage || typeof storage.persist !== 'function') return 'unsupported';

  try {
    if (typeof storage.persisted === 'function' && (await storage.persisted())) {
      return 'persisted';
    }
    return (await storage.persist()) ? 'granted' : 'denied';
  } catch {
    return 'unsupported';
  }
}
