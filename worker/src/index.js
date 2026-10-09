const MAX_OBJECT_BYTES = 16 * 1024 * 1024;

const PATH = /^\/m\/([0-9a-f]{32,64})\/([A-Za-z0-9_-]{8,64})\/(manifest|rec\/[A-Za-z0-9]{1,32}\/[A-Za-z0-9_-]{1,255})$/;

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function corsHeaders(request, env) {
  const allowed = env.ALLOWED_ORIGIN || '';
  const origin = request.headers.get('Origin') || '';
  const headers = {
    'Access-Control-Allow-Methods': 'GET, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  const list = allowed.split(',').map((s) => s.trim()).filter(Boolean);
  if (origin && list.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
}

async function readObject(store, key) {
  if (typeof store.head === 'function') {
    const object = await store.get(key);
    return object ? object.body : null;
  }
  return await store.get(key, { type: 'arrayBuffer' });
}

function reply(status, body, extra) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Cache-Control': 'no-store',
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
      return reply(404, null, cors);
    }

    const [, mailboxId, owner, tail] = match;
    const key = `${mailboxId}/${owner}/${tail}`;

    if (request.method === 'GET') {
      const body = await readObject(env.MAILBOX, key);
      if (body === null) return reply(404, null, cors);
      return reply(200, body, cors);
    }

    if (request.method === 'PUT') {
      const declared = Number(request.headers.get('Content-Length') || '0');
      if (declared > MAX_OBJECT_BYTES) return reply(413, 'Too large', cors);

      const body = await request.arrayBuffer();
      if (body.byteLength > MAX_OBJECT_BYTES) return reply(413, 'Too large', cors);

      await env.MAILBOX.put(key, body);
      return reply(204, null, cors);
    }

    return reply(405, null, cors);
  },
};
