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
