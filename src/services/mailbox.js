/**
 * src/services/mailbox.js
 * Sync that does not need both of you awake.
 *
 * THE PROBLEM THIS SOLVES, AND THE ONLY ONE
 * peerSync connects the two phones directly, which means both phones on, both
 * apps open, at the same moment. Between two time zones that overlap is small
 * and getting the timing right stops being romantic very quickly. The mailbox
 * removes the "at the same moment" requirement. It does NOT make a phone buzz -
 * the other person still finds out when they next open the app.
 *
 * A MIRROR, NOT A QUEUE
 * Each device publishes its own state and overwrites in place; the other reads
 * whenever it likes. Reading twice is a no-op, so nothing needs deleting on
 * delivery, nothing needs acknowledging, and an interrupted sync resumes by
 * simply running again from nothing. A queue would have needed an ack - and an
 * ack that goes missing either erases a record that was never applied or
 * delivers it twice - and it would have broken outright the moment one person
 * used both a phone and a laptop.
 *
 * THIS FILE ADDS NO NEW TRUST, AND THAT IS THE POINT
 * It decides what to fetch with peerSync's own manifest diff, and it applies
 * what it fetched with db.planBackupMerge / applyBackupMerge - the same two
 * pieces that already handle a restored backup and a live partner. Every rule
 * that protects the vault (sealed headers, table binding, photo digests,
 * last-write-wins, the refusal to let an unverified binding overwrite anything)
 * runs unchanged and was already tested. A relay can therefore be dishonest
 * without being dangerous: the worst it manages is going quiet, which is
 * indistinguishable from "not synced yet", or replaying something stale, which
 * loses on a timestamp sealed inside the ciphertext.
 *
 * WHAT LEAVES THE DEVICE
 * Record envelopes, byte for byte as they sit in IndexedDB - already encrypted,
 * not re-encrypted here - and a manifest that is itself encrypted, because a
 * plaintext one would tell the relay how many records you have and when each
 * was last touched.
 *
 * IF IT IS NOT CONFIGURED
 * Every function here returns a disabled result and the app behaves exactly as
 * it did before. That is deliberate: this is an optional accelerator bolted
 * beside the real sync, never a dependency of it.
 */

import db, { SYNCED_TABLES } from '../db/index.js';
import { bufferToBase64, encryptJSON, decryptJSON } from './crypto.js';
import peerSync from './peerSync.js';

/** Domain separation. One label per derived value, so knowing one reveals nothing. */
const MAILBOX_ID_CONTEXT = 'our-space/mailbox/id/v1';

/** Ceiling that matches the Worker's. Anything larger is refused before upload. */
export const MAX_OBJECT_BYTES = 16 * 1024 * 1024;

/**
 * Tables published before photos.
 *
 * Every one of these is kilobytes. `memories` is the outlier - a single record
 * can be twelve megabytes after base64 - so it goes last and on its own, and a
 * publish that dies partway has already delivered the letters, the answers and
 * the milestones rather than having spent the whole connection on one photo.
 */
const TEXT_TABLES = SYNCED_TABLES.filter((name) => name !== 'memories');

const webCrypto = () => (typeof window !== 'undefined' ? window.crypto : globalThis.crypto);

/* --------------------------------------------------------------- config */

function readEnv(name) {
  try {
    return import.meta.env ? import.meta.env[name] : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Where the mailbox lives, or null when there is not one.
 *
 * BOTH values are required. A URL with no token gets a 401 on every call, which
 * would surface as "sync is broken" rather than "sync is not set up" - the same
 * half-configured trap iceServers.js refuses for TURN credentials.
 */
export function getMailboxConfig(overrides) {
  const url = (overrides && overrides.url) || readEnv('VITE_MAILBOX_URL');
  const token = (overrides && overrides.token) || readEnv('VITE_MAILBOX_TOKEN');

  if (typeof url !== 'string' || !url || typeof token !== 'string' || !token) return null;

  // A trailing slash here produces `//m/...` on every request, which some edge
  // routers normalise and some do not.
  return { url: url.replace(/\/+$/, ''), token };
}

/** @returns {boolean} Whether a mailbox is configured at all. */
export function isMailboxEnabled(overrides) {
  return getMailboxConfig(overrides) !== null;
}

/* ------------------------------------------------------------ addressing */

/**
 * The mailbox id for this vault: 256 bits derived from the vault key.
 *
 * This is the whole access control. Without the passphrase you cannot derive
 * it, and the Worker has no route that lists anything, so a mailbox that is not
 * guessed is a mailbox that cannot be found. What is inside is ciphertext
 * regardless.
 *
 * The vault key is non-extractable so it cannot be hashed directly. It can
 * encrypt, and AES-GCM over a fixed plaintext with a fixed IV is deterministic
 * - the same trick the daily question uses to agree on an order with no server,
 * and safe for the same reason: one use, one constant plaintext, and the output
 * is an address rather than a secret.
 *
 * @param {CryptoKey} cryptoKey
 * @returns {Promise<string>} 64 hex characters.
 */
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

/**
 * base64url of a record id, so any id the app can mint is a legal path segment.
 *
 * Record ids are not constrained to URL-safe characters anywhere in this app,
 * and percent-encoding would leave `%` in a path the Worker pattern-matches.
 * Not reversible here, and it does not need to be: the manifest carries the
 * real ids and a reader builds the key the same way.
 */
export function recordKey(id) {
  const bytes = new TextEncoder().encode(String(id));
  return bufferToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/* --------------------------------------------------------------- transport */

async function request(config, method, path, body) {
  const response = await fetch(`${config.url}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${config.token}`,
      ...(body ? { 'Content-Type': 'application/octet-stream' } : {}),
    },
    body,
    // The mailbox is a different origin and holds nothing tied to a session.
    // Sending credentials would only widen what a misconfigured Worker could be
    // talked into doing.
    credentials: 'omit',
    cache: 'no-store',
  });
  return response;
}

/* ---------------------------------------------------------------- publish */

/**
 * The only fields that may leave this device.
 *
 * An ALLOWLIST, not a list of things to strip, for the same reason peerSync
 * uses one: a field added to a row later is then absent from the mailbox by
 * default rather than published by default. Getting that backwards is how
 * something ends up on a relay because nobody remembered to exclude it.
 */
const WIRE_FIELDS = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

/**
 * Row -> the shape planBackupMerge accepts.
 *
 * `_del` is deliberately NOT here. It is the 0/1 mirror of `deleted` that
 * exists only because IndexedDB refuses boolean index keys - local bookkeeping,
 * which peerSync strips for the same reason, and which the receiving side
 * recomputes from `deleted` regardless. Publishing it put a redundant field on
 * a relay on every single record.
 */
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

/**
 * Publishes this device's records and then announces them.
 *
 * ORDER MATTERS AND IT IS NOT THE OBVIOUS ONE. Records go up first and the
 * manifest last, and the manifest lists only the records whose upload was
 * actually confirmed. Written the other way round, a publish that dies halfway
 * leaves a manifest promising records that are not there, and the other phone
 * spends every sync from then on requesting objects that 404. This way the
 * manifest is never a promise that has not already been kept, and a partial
 * publish is simply a smaller one.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string, overrides?: Object,
 *   includePhotos?: boolean, store?: Object }} args
 * @returns {Promise<{ ok: boolean, reason?: string, uploaded: number, skipped: number }>}
 */
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

  // What we last managed to publish. Fetched rather than remembered locally, so
  // a device whose storage was cleared re-publishes instead of believing a
  // mailbox it has never filled is already full.
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
      // Unchanged since the last publish. The overwhelming majority of records
      // on the overwhelming majority of runs.
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
        // The Worker would refuse it anyway. Counted rather than thrown: one
        // oversized photo must not stop the letters going out.
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
        // Offline, or the Worker is down. Everything already confirmed still
        // gets announced below, so the run is partial rather than wasted.
        skipped++;
      }
    }
  }

  // Photos excluded from this run keep whatever was published before, so
  // skipping them does not retract them from the other phone.
  if (args && args.includePhotos === false && published && published.memories) {
    confirmed.memories = published.memories;
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

/* ------------------------------------------------------------------ fetch */

/** Reads and decrypts a manifest, treating absent and unreadable alike. */
async function readManifest(config, base, cryptoKey) {
  let response;
  try {
    response = await request(config, 'GET', `${base}/manifest`);
  } catch {
    return null;
  }
  // 404 is the ordinary case before anyone has published, not a failure.
  if (!response.ok) return null;

  try {
    const sealed = JSON.parse(await response.text());
    const manifest = await decryptJSON(sealed.ciphertext, sealed.iv, cryptoKey);
    if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) return null;
    return manifest;
  } catch {
    // Someone else's bytes, a truncated upload, or a key that does not open it.
    // All three mean the same thing here: there is nothing to read.
    return null;
  }
}

/**
 * Collects whatever the other device has published that this one does not have.
 *
 * @param {{ cryptoKey: CryptoKey, partnerId: string, overrides?: Object, store?: Object }} args
 * @returns {Promise<{ ok: boolean, reason?: string, applied: number, fetched: number }>}
 */
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

  // peerSync's own diff, not a second copy of it. The rule that decides whether
  // an incoming record is worth having - including the tie-break that lets a
  // same-millisecond deletion beat an edit - is subtle enough that two
  // implementations of it would eventually disagree, and the disagreement would
  // show up as records that sync over a cable but not through the mailbox.
  const wanted = await peerSync.diffAgainstLocal(remote);
  if (wanted.length === 0) return { ok: true, applied: 0, fetched: 0 };

  const tables = {};
  let fetched = 0;

  for (const { table, id } of wanted) {
    try {
      const response = await request(config, 'GET', `${base}/rec/${table}/${recordKey(id)}`);
      // A 404 means the manifest promised something the records do not have.
      // Skipped rather than treated as an error: the next publish fixes it.
      if (!response.ok) continue;
      const record = JSON.parse(await response.text());
      if (!tables[table]) tables[table] = [];
      tables[table].push(record);
      fetched++;
    } catch {
      // One record failing must not abandon the others already in hand.
    }
  }

  if (fetched === 0) return { ok: true, applied: 0, fetched: 0 };

  // The backup merge path, unchanged. It sanitises every field, verifies the
  // envelope's integrity against the vault key, refuses a row sealed for a
  // different table, refuses an unverified binding an overwrite, and settles
  // the rest with peerSync's precedence rule.
  const plan = await store.planBackupMerge(tables, cryptoKey);
  const result = await store.applyBackupMerge(plan);

  // `written` is per-table counts of rows that actually landed, which is not
  // the same as the plan's totals: the precedence rule is re-applied inside the
  // transaction, so a live sync that arrived in between can legitimately
  // supersede a write this plan intended. Report what was written, not what was
  // hoped for.
  const applied = Object.values((result && result.written) || {}).reduce(
    (sum, n) => sum + (Number.isFinite(n) ? n : 0),
    0
  );

  if (applied > 0) {
    try {
      peerSync.emit('data-updated', { count: applied, source: 'mailbox' });
    } catch {
      // Nothing is listening. The records are written either way.
    }
  }

  return { ok: true, applied, fetched, totals: plan.totals };
}

/**
 * One round trip: take what is waiting, then leave what is ours.
 *
 * COLLECT FIRST, on purpose. If publishing came first, a device that has been
 * offline would push its older state before learning what changed while it was
 * away. Last-write-wins settles it either way, but the other phone would
 * briefly see a manifest that had gone backwards.
 *
 * IT READS BOTH SLOTS, INCLUDING ITS OWN, and that is not a waste.
 *
 * The two slot ids are derived from the vault key (services/people.js), so both
 * phones know both addresses without ever having spoken. Reading the partner's
 * is the point. Reading our own costs one manifest request and buys two things:
 * a device that has not worked out which person it is yet can still pull the
 * people records that would tell it, which is how the whole thing bootstraps;
 * and a phone whose storage was wiped restores itself from what it published
 * before, instead of starting empty and publishing that emptiness.
 *
 * There is no ping-pong risk in reading our own slot. Collect only applies
 * records that are newer than what is here, and publish only uploads records
 * that changed, so a device already in step does both and writes nothing.
 *
 * @param {{ cryptoKey: CryptoKey, ownerId: string|null, slots: Array<string>,
 *   overrides?: Object, includePhotos?: boolean, store?: Object }} args
 */
export async function syncMailbox(args) {
  const slots = Array.isArray(args && args.slots) ? args.slots : [];
  const collected = [];

  for (const slot of slots) {
    if (!slot) continue;
    collected.push(await collect({ ...args, partnerId: slot }));
  }

  // Nothing to publish until this device knows which of the two people it is.
  // Publishing under a device tag instead would put records at an address the
  // other phone has no reason to ever look at.
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
