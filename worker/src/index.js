const MAX_OBJECT_BYTES = 16 * 1024 * 1024;

const MAX_PUSH_TOKEN_CHARS = 4096;

const PATH =
  /^\/m\/([0-9a-f]{32,64})\/([A-Za-z0-9_-]{8,64})\/(manifest|rec\/[A-Za-z0-9]{1,32}\/[A-Za-z0-9_-]{1,255}|push\/[A-Za-z0-9_-]{8,64})$/;

const PUSH_TOKEN = /^[A-Za-z0-9_:.-]+$/;

const PUSH_MESSAGE = {
  title: 'Our Space 💕',
  body: 'Something new is waiting for you.',
  tag: 'our-space-new',
};

const OAUTH_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

let cachedAccess = null;

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
    'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  const list = allowed.split(',').map((s) => s.trim()).filter(Boolean);
  if (origin && list.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
}

function isR2(store) {
  return typeof store.head === 'function';
}

async function readObject(store, key) {
  if (isR2(store)) {
    const object = await store.get(key);
    return object ? object.body : null;
  }
  return await store.get(key, { type: 'arrayBuffer' });
}

async function readText(store, key) {
  if (isR2(store)) {
    const object = await store.get(key);
    return object ? await object.text() : null;
  }
  return await store.get(key, { type: 'text' });
}

async function listKeys(store, prefix) {
  const keys = [];
  let cursor;
  do {
    const page = await store.list({ prefix, cursor });
    if (Array.isArray(page.keys)) keys.push(...page.keys.map((k) => k.name));
    if (Array.isArray(page.objects)) keys.push(...page.objects.map((o) => o.key));
    const more = page.list_complete === false || page.truncated === true;
    cursor = more ? page.cursor : undefined;
  } while (cursor);
  return keys;
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

function base64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem) {
  const body = String(pem)
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function accessToken(account) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccess && cachedAccess.email === account.client_email && cachedAccess.expires - 60 > now) {
    return cachedAccess.token;
  }

  const encoder = new TextEncoder();
  const header = base64Url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64Url(
    encoder.encode(
      JSON.stringify({
        iss: account.client_email,
        scope: FCM_SCOPE,
        aud: OAUTH_URL,
        iat: now,
        exp: now + 3600,
      })
    )
  );
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    signingKey,
    encoder.encode(`${header}.${claims}`)
  );

  const response = await fetch(OAUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${base64Url(new Uint8Array(signature))}`,
    }),
  });
  if (!response.ok) throw new Error(`token exchange failed: ${response.status}`);
  const data = await response.json();
  cachedAccess = {
    token: data.access_token,
    email: account.client_email,
    expires: now + (Number(data.expires_in) || 3600),
  };
  return cachedAccess.token;
}

function pushMessage(token) {
  return {
    message: {
      token,
      notification: { title: PUSH_MESSAGE.title, body: PUSH_MESSAGE.body },
      android: {
        priority: 'HIGH',
        ttl: '86400s',
        collapse_key: PUSH_MESSAGE.tag,
        notification: { tag: PUSH_MESSAGE.tag },
      },
      data: { kind: 'mailbox' },
    },
  };
}

async function ringOthers(env, mailboxId, writer) {
  if (!env.FCM_SERVICE_ACCOUNT) return;
  try {
    const keys = await listKeys(env.MAILBOX, `push/${mailboxId}/`);
    const targets = keys.filter((key) => key.split('/')[2] !== writer);
    if (targets.length === 0) return;

    const account = JSON.parse(env.FCM_SERVICE_ACCOUNT);
    const access = await accessToken(account);
    const endpoint = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

    await Promise.all(
      targets.map(async (key) => {
        let token;
        try {
          token = JSON.parse((await readText(env.MAILBOX, key)) || '{}').token;
        } catch {
          token = undefined;
        }
        if (typeof token !== 'string' || !token) return;
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(pushMessage(token)),
        });
        if (response.status === 404) await env.MAILBOX.delete(key);
      })
    );
  } catch {
  }
}

async function handlePush(request, env, cors, key) {
  if (request.method === 'DELETE') {
    await env.MAILBOX.delete(key);
    return reply(204, null, cors);
  }

  if (request.method !== 'PUT') return reply(405, null, cors);

  let token;
  try {
    token = (await request.json()).token;
  } catch {
    token = undefined;
  }
  if (typeof token !== 'string' || token.length > MAX_PUSH_TOKEN_CHARS || !PUSH_TOKEN.test(token)) {
    return reply(400, null, cors);
  }

  await env.MAILBOX.put(key, JSON.stringify({ token, at: Date.now() }));
  return reply(204, null, cors);
}

export default {
  async fetch(request, env, ctx) {
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

    if (tail.startsWith('push/')) {
      return handlePush(request, env, cors, `push/${mailboxId}/${owner}/${tail.slice(5)}`);
    }

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

      if (tail === 'manifest') {
        const ringing = ringOthers(env, mailboxId, owner);
        if (ctx && typeof ctx.waitUntil === 'function') ctx.waitUntil(ringing);
        else await ringing;
      }

      return reply(204, null, cors);
    }

    return reply(405, null, cors);
  },
};
