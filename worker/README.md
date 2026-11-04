# The mailbox

A small Cloudflare Worker that holds encrypted copies of your data, so the two phones don't have to be online at the same time. It also rings the other phone when something new is waiting.

It can't read what you write, because everything is encrypted on the phone first. The only thing it keeps unencrypted is the token Google gives a phone that turned notifications on. Notifications use fixed wording, so they never carry names, films or links.

## Deploy

```bash
cd worker
npx wrangler login
npx wrangler kv namespace create MAILBOX
```

Put the id it prints into `wrangler.toml`, then:

```bash
npx wrangler secret put MAILBOX_TOKEN
npx wrangler deploy
```

`MAILBOX_TOKEN` can be any long random string. It gets compiled into the app, so treat it as public and don't reuse a real password.

For notifications, add a Firebase service account key (Firebase console, Project settings, Service accounts, Generate new private key) and deploy again:

```bash
npx wrangler secret put FCM_SERVICE_ACCOUNT < path/to/service-account.json
npx wrangler deploy
```

If the app lives anywhere other than `sameskytonight.vercel.app`, add its address to `ALLOWED_ORIGIN` in `wrangler.toml` and deploy again. The Worker refuses browsers from anywhere else.

Then set these on the app and redeploy it:

```
VITE_MAILBOX_URL=https://our-space-mailbox.<your-subdomain>.workers.dev
VITE_MAILBOX_TOKEN=<the same token>
```

## Cost

Free, and no card needed. You get 100,000 requests and 1,000 writes a day, and 1GB of storage. A photo can take up to 12MB, so about a hundred photos fills it. After that photos only sync directly between phones, and everything else keeps working.

## Worth knowing

- A write can take up to a minute to show up, so give it a minute before deciding sync is broken.
- Objects are never deleted. A deleted letter gets written as an empty record instead, otherwise it would come back on the next sync.
