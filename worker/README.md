# The mailbox

A shelf that holds sealed envelopes and cannot read one.

Our Space syncs phone-to-phone over WebRTC, which needs both phones awake and
both apps open at the same moment. This removes that requirement and nothing
else. One of you publishes whenever you use the app; the other collects whenever
they use theirs. Neither of you has to be anywhere.

It is optional. With no mailbox configured the app works exactly as it did
before — phone-to-phone, when you happen to overlap.

## What it can see

Nothing. Every object stored here is an AES-GCM envelope that was sealed on a
phone with a key derived from your passphrase. Cloudflare holds bytes.

The mailbox path is a 256-bit id derived from the same vault key, so finding
your mailbox means guessing it, and the Worker has no route that lists
anything — an unknown key is a flat 404.

`MAILBOX_TOKEN` gets compiled into the browser bundle, so treat it as public.
It stops a passer-by burning your request quota; it is not a password, and it
should not be one you use anywhere else.

## Deploy

```bash
cd worker
npx wrangler r2 bucket create our-space-mailbox
npx wrangler secret put MAILBOX_TOKEN   # any long random string
npx wrangler deploy
```

Then edit `ALLOWED_ORIGIN` in `wrangler.toml` to your own domain and deploy
again. The Worker refuses browser origins that are not on that list rather than
reflecting whatever asked, so this step is not optional.

Finally, set these on the app (Vercel → Project Settings → Environment
Variables) and redeploy:

```
VITE_MAILBOX_URL=https://our-space-mailbox.<your-subdomain>.workers.dev
VITE_MAILBOX_TOKEN=<the same token>
```

## What it costs

Nothing, at two people's scale. Cloudflare's free tier is 10GB of R2 storage,
1M writes and 10M reads a month, no egress charge, and 100,000 Worker requests
a day. A mailbox holds one copy of each phone's vault — records are overwritten
in place rather than accumulating — so it stays the size of your app, not the
size of its history.

## Why nothing is ever deleted

The obvious design is a queue: push a change, the other phone collects it, erase
it. That needs an acknowledgement, and an acknowledgement that goes missing
either erases something that was never applied or delivers it twice. It also
breaks the moment one of you has a laptop as well as a phone, because whichever
device collects first destroys the copy the other one needed.

So this is a mirror instead. Each device publishes its current state and
overwrites in place. Reading twice is a no-op, delivery needs no bookkeeping,
and an interrupted sync resumes by starting again.

Deleting something in the app travels as a **tombstone** — a record with its
contents removed — which is written like anything else. That is why this Worker
implements no `DELETE`. Removing an object would mean the other phone never
learns the record died, and a deleted letter would climb back out of the grave
on the next sync.

## What it does not do

It does not make a phone buzz. The other person still finds out when they open
the app. What it kills is the need for both of you to be there at once, which is
the part that actually wears two people down. Real push notifications need a
subscription and a signing key, and they leak to a push service the timing of
every message you send — a different feature with a different trade-off.
