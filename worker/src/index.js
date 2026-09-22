/**
 * worker/src/index.js
 * The mailbox. A shelf that holds sealed envelopes and cannot read one.
 *
 * WHAT THIS IS FOR
 * Our Space syncs phone-to-phone over WebRTC, which requires both phones awake,
 * both apps open, at the same moment. For two people in one house that is a
 * minor annoyance. For two people in different time zones it is the reason the
 * app stops getting used. This removes the "at the same moment" part and
 * nothing else.
 *
 * WHAT IT IS NOT
 * It is not a queue and it is not a server that knows anything. It stores
 * opaque bytes at exact keys and hands them back. It cannot list a bucket, it
 * cannot read a record, it does not know who you are, how many of you there
 * are, or that any of this has to do with a relationship.
 *
 * WHY NOTHING IS EVER DELETED ON DELIVERY
 * The obvious design is a queue: push a change, the other phone collects it,
 * erase it. That needs an acknowledgement, and an acknowledgement that goes
 * missing either erases something that was never applied or delivers it twice.
 * It also breaks the moment one person has two devices, because whichever one
 * collects first destroys the copy the other one needed.
 *
 * So this is a MIRROR. Each device publishes its current state and overwrites
 * in place. Reading the same object twice is a no-op, delivery needs no
 * bookkeeping, and an interrupted sync resumes by simply starting again. A
 * deletion travels as a TOMBSTONE that gets written like any other record -
 * which is why this Worker deliberately implements no DELETE at all. Removing
 * an object would mean the other phone never learns the record died, and a
 * deleted letter would come back to life on the next sync.
 *
 * WHAT STOPS A STRANGER READING IT
 * The path. Every mailbox lives under a 256-bit id derived from the vault key
 * (see src/services/mailbox.js), so finding one means guessing it, and this
 * Worker will not enumerate: there is no list route and an unknown key is a
 * flat 404. Everything inside is AES-GCM ciphertext produced on a phone, so a
 * guessed path yields bytes nobody can open. The app's existing rules treat
 * every inbound record as hostile regardless, which is what lets this thing be
 * deployed by someone who has not audited it.
 *
 * ABOUT THE TOKEN, HONESTLY
 * MAILBOX_TOKEN is compiled into a browser bundle on the client side, so it is
 * public to anyone who opens devtools. It is here to stop a passer-by burning
 * the request quota, not to keep a secret. The path is the credential. Do not
 * mistake the token for security, and do not reuse a real password for it.
 *
 * DEPLOY
 *   cd worker
 *   npx wrangler r2 bucket create our-space-mailbox
 *   npx wrangler secret put MAILBOX_TOKEN     # any long random string
 *   npx wrangler deploy
 */

/** Ceiling on one stored object. A photo record is the large case, ~12MB after base64. */
const MAX_OBJECT_BYTES = 16 * 1024 * 1024;

/** `/m/<mailboxId>/<owner>/manifest` or `/m/<mailboxId>/<owner>/rec/<table>/<key>`. */
const PATH = /^\/m\/([0-9a-f]{32,64})\/([A-Za-z0-9_-]{8,64})\/(manifest|rec\/[A-Za-z0-9]{1,32}\/[A-Za-z0-9_-]{1,255})$/;

/**
 * Constant-time string compare.
 *
 * An early-exit compare leaks the token a character at a time to anyone willing
 * to measure. The token is not much of a secret (see above), but writing the
 * fast version here is how the habit leaks into somewhere it matters.
 */
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * CORS. The app is the only caller and it is served from one known origin, so
 * ALLOWED_ORIGIN is checked rather than reflected - reflecting the request's
 * own Origin is the same as allowing everyone, which is the default people
 * reach for and then never revisit.
 */
function corsHeaders(request, env) {
  const allowed = env.ALLOWED_ORIGIN || '';
  const origin = request.headers.get('Origin') || '';
  const headers = {
    'Access-Control-Allow-Methods': 'GET, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  // A comma-separated list, so a preview deployment can be added without
  // opening the Worker to the whole web.
  const list = allowed.split(',').map((s) => s.trim()).filter(Boolean);
  if (origin && list.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
}

function reply(status, body, extra) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Cache-Control': 'no-store',
      // Nothing here is a document, and a browser must never be tempted to
      // treat a stored blob as one.
      'X-Content-Type-Options': 'nosniff',
      ...extra,
    },
  });
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    if (!cors['Access-Control-Allow-Origin']) {
      // Not a browser we recognise. Say as little as possible.
      return reply(403, null, cors);
    }

    if (!env.MAILBOX || !env.MAILBOX_TOKEN) {
      return reply(500, 'Worker is not configured', cors);
    }

    const auth = request.headers.get('Authorization') || '';
    if (!safeEqual(auth, `Bearer ${env.MAILBOX_TOKEN}`)) {
      return reply(401, null, cors);
    }

    const url = new URL(request.url);
    const match = PATH.exec(url.pathname);
    if (!match) {
      // Covers every shape this Worker refuses to serve, including anything
      // that looks like a listing. There is no route that enumerates.
      return reply(404, null, cors);
    }

    const [, mailboxId, owner, tail] = match;
    const key = `${mailboxId}/${owner}/${tail}`;

    if (request.method === 'GET') {
      const object = await env.MAILBOX.get(key);
      // A missing object is the ordinary case, not an error: it is what the
      // other phone sees before you have ever published.
      if (!object) return reply(404, null, cors);
      return reply(200, object.body, {
        ...cors,
        ETag: object.httpEtag,
      });
    }

    if (request.method === 'PUT') {
      const declared = Number(request.headers.get('Content-Length') || '0');
      if (declared > MAX_OBJECT_BYTES) return reply(413, 'Too large', cors);

      // Content-Length can be absent or a lie, so the body is read and measured
      // before anything is stored. Without this a chunked upload walks straight
      // past the check above.
      const body = await request.arrayBuffer();
      if (body.byteLength > MAX_OBJECT_BYTES) return reply(413, 'Too large', cors);

      await env.MAILBOX.put(key, body);
      return reply(204, null, cors);
    }

    // DELETE is deliberately absent. A deletion in this app travels as a
    // tombstone record that is WRITTEN, not as an object that disappears - see
    // the header comment.
    return reply(405, null, cors);
  },
};
