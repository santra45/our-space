import db, { SYNCED_TABLES } from '../db/index.js';
import { bufferToBase64, encryptJSON, decryptJSON } from './crypto.js';
import peerSync from './peerSync.js';

const MAILBOX_ID_CONTEXT = 'our-space/mailbox/id/v1';

export const MAX_OBJECT_BYTES = 16 * 1024 * 1024;

const TEXT_TABLES = SYNCED_TABLES.filter((name) => name !== 'memories');

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

function readEnv(name) {
  try {
    return import.meta.env ? import.meta.env[name] : undefined;
  } catch {
    return undefined;
  }
}

export function getMailboxConfig(overrides) {
  const url = (overrides && overrides.url) || readEnv('VITE_MAILBOX_URL');
  const token = (overrides && overrides.token) || readEnv('VITE_MAILBOX_TOKEN');

  if (typeof url !== 'string' || !url || typeof token !== 'string' || !token) return null;

  return { url: url.replace(/\/+$/, ''), token };
}

export function isMailboxEnabled(overrides) {
  return getMailboxConfig(overrides) !== null;
}

export async function deriveMailboxId(cryptoKey) {
  if (!cryptoKey) throw new Error('deriveMailboxId: vault is locked');
  const sealed = await webCrypto().subtle.encrypt(
    { name: 'AES-GCM', iv: new Uint8Array(12) },
    cryptoKey,
    new TextEncoder().encode(MAILBOX_ID_CONTEXT)
  );
  const digest = new Uint8Array(await webCrypto().subtle.digest('SHA-256', sealed));
  return Array.from(digest)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function recordKey(id) {
  const bytes = new TextEncoder().encode(String(id));
  return bufferToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function request(config, method, path, body) {
  const response = await fetch(`${config.url}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${config.token}`,
      ...(body ? { 'Content-Type': 'application/octet-stream' } : {}),
    },
    body,
    credentials: 'omit',
    cache: 'no-store',
  });
  return response;
}

const WIRE_FIELDS = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

function toWire(tableName, row) {
  const wire = {};
  for (const field of WIRE_FIELDS) {
    if (row[field] !== undefined) wire[field] = row[field];
  }
  if (tableName === 'memories' && row.imageBlob) {
    wire.imageBlobBase64 = bufferToBase64(row.imageBlob);
  }
  return wire;
}

function sameManifest(prev, next) {
  if (!prev || typeof prev !== 'object') return false;
  const tables = new Set([...Object.keys(prev), ...Object.keys(next)]);
  for (const tableName of tables) {
    const before = Array.isArray(prev[tableName]) ? prev[tableName] : [];
    const after = Array.isArray(next[tableName]) ? next[tableName] : [];
    if (before.length !== after.length) return false;
    const versions = new Map(before.map((e) => [e.id, e.updatedAt]));
    for (const entry of after) {
      if (!versions.has(entry.id) || versions.get(entry.id) !== entry.updatedAt) return false;
    }
  }
  return true;
}

export async function publish(args) {
  const { cryptoKey, ownerId } = args || {};
  const config = getMailboxConfig(args && args.overrides);
  const idle = { ok: false, uploaded: 0, skipped: 0 };

  if (!config) return { ...idle, reason: 'disabled' };
  if (!cryptoKey) return { ...idle, reason: 'locked' };
  if (!ownerId) return { ...idle, reason: 'no-owner' };

  const store = (args && args.store) || db;
  const mailboxId = await deriveMailboxId(cryptoKey);
  const base = `/m/${mailboxId}/${ownerId}`;

  const published = await readManifest(config, base, cryptoKey);

  const local = await store.getManifest();
  const confirmed = {};
  let uploaded = 0;
  let skipped = 0;

  const tables = args && args.includePhotos === false ? TEXT_TABLES : [...TEXT_TABLES, 'memories'];

  for (const tableName of tables) {
    const entries = local[tableName] || [];
    const already = new Map(
      ((published && published[tableName]) || []).map((e) => [e.id, e.updatedAt])
    );
    confirmed[tableName] = [];

    for (const entry of entries) {
      if (already.get(entry.id) === entry.updatedAt) {
        confirmed[tableName].push(entry);
        continue;
      }

      const row = await store.table(tableName).get(entry.id);
      if (!row) continue;

      let body;
      try {
        body = JSON.stringify(toWire(tableName, row));
      } catch {
        skipped++;
        continue;
      }

      if (body.length > MAX_OBJECT_BYTES) {
        skipped++;
        continue;
      }

      try {
        const response = await request(config, 'PUT', `${base}/rec/${tableName}/${recordKey(entry.id)}`, body);
        if (!response.ok) {
          skipped++;
          continue;
        }
        uploaded++;
        confirmed[tableName].push(entry);
      } catch {
        skipped++;
      }
    }
  }

  if (args && args.includePhotos === false && published && published.memories) {
    confirmed.memories = published.memories;
  }

  if (uploaded === 0 && sameManifest(published, confirmed)) {
    return { ok: true, uploaded, skipped, unchanged: true };
  }

  try {
    const sealed = await encryptJSON(confirmed, cryptoKey);
    const response = await request(config, 'PUT', `${base}/manifest`, JSON.stringify(sealed));
    if (!response.ok) return { ok: false, reason: 'manifest-failed', uploaded, skipped };
  } catch {
    return { ok: false, reason: 'offline', uploaded, skipped };
  }

  return { ok: true, uploaded, skipped };
}

async function readManifest(config, base, cryptoKey) {
  let response;
  try {
    response = await request(config, 'GET', `${base}/manifest`);
  } catch {
    return null;
  }
  if (!response.ok) return null;

  try {
    const sealed = JSON.parse(await response.text());
    const manifest = await decryptJSON(sealed.ciphertext, sealed.iv, cryptoKey);
    if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) return null;
    return manifest;
  } catch {
    return null;
  }
}

export async function collect(args) {
  const { cryptoKey, partnerId } = args || {};
  const config = getMailboxConfig(args && args.overrides);
  const idle = { ok: false, applied: 0, fetched: 0 };

  if (!config) return { ...idle, reason: 'disabled' };
  if (!cryptoKey) return { ...idle, reason: 'locked' };
  if (!partnerId) return { ...idle, reason: 'no-partner' };

  const store = (args && args.store) || db;
  const mailboxId = await deriveMailboxId(cryptoKey);
  const base = `/m/${mailboxId}/${partnerId}`;

  const remote = await readManifest(config, base, cryptoKey);
  if (!remote) return { ok: true, reason: 'nothing-published', applied: 0, fetched: 0 };

  const wanted = await peerSync.diffAgainstLocal(remote);
  if (wanted.length === 0) return { ok: true, applied: 0, fetched: 0 };

  const tables = {};
  let fetched = 0;

  for (const { table, id } of wanted) {
    try {
      const response = await request(config, 'GET', `${base}/rec/${table}/${recordKey(id)}`);
      if (!response.ok) continue;
      const record = JSON.parse(await response.text());
      if (!tables[table]) tables[table] = [];
      tables[table].push(record);
      fetched++;
    } catch {
    }
  }

  if (fetched === 0) return { ok: true, applied: 0, fetched: 0 };

  const plan = await store.planBackupMerge(tables, cryptoKey);
  const result = await store.applyBackupMerge(plan);

  const applied = Object.values((result && result.written) || {}).reduce(
    (sum, n) => sum + (Number.isFinite(n) ? n : 0),
    0
  );

  if (applied > 0) {
    try {
      peerSync.emit('data-updated', { count: applied, source: 'mailbox' });
    } catch {
    }
  }

  return { ok: true, applied, fetched, totals: plan.totals };
}

export async function syncMailbox(args) {
  const slots = Array.isArray(args && args.slots) ? args.slots : [];
  const collected = [];

  for (const slot of slots) {
    if (!slot) continue;
    collected.push(await collect({ ...args, partnerId: slot }));
  }

  const published = args && args.ownerId ? await publish(args) : { ok: false, reason: 'no-owner' };

  return {
    collected,
    published,
    applied: collected.reduce((sum, r) => sum + (r.applied || 0), 0),
    uploaded: published.uploaded || 0,
  };
}

export default {
  MAX_OBJECT_BYTES,
  isMailboxEnabled,
  getMailboxConfig,
  deriveMailboxId,
  recordKey,
  publish,
  collect,
  syncMailbox,
};
