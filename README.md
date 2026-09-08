# Our Space 💕

A private, offline-first web app for two people. Photos, letters, milestones, a shared
bucket list and a date-night scratch card — all encrypted on the phone with a passphrase
only the two of you know, and synced directly between your devices.

There is no server, no account, no database and no analytics. Nothing you write is ever
uploaded anywhere.

---

## What's inside

| Screen | What it does |
| --- | --- |
| **Countdown** | Live counter since the day you started, plus milestones you add yourself |
| **Scrapbook** | Polaroid-style photo wall with captions, compressed and encrypted on device |
| **Date Roulette** | Scratch-off card that picks a date idea, with confetti |
| **Capsule** | Love letters, optionally sealed until a future date |
| **Bucket List** | Shared checklist with progress, ticked from either phone |

Plus a **Sync Hub** for pairing the two phones, and an encrypted `.vault` backup you can
save anywhere.

---

## Quick start

```bash
npm install
npm run dev
```

Then open the printed URL. `npm run dev` binds to your network so you can also load it on
a phone on the same Wi-Fi — but see [Testing on a phone](#testing-on-a-phone), because
plain HTTP will not work.

```bash
npm run build     # production build into dist/
npm run preview   # serve the built output
npm test          # crypto + sync test suite (329 assertions, plain node, no browser)
```

---

## How it works

Everything lives in the browser. Records are encrypted with **AES-GCM-256** and stored in
IndexedDB via Dexie; the key is derived from your passphrase with **PBKDF2-HMAC-SHA-256**.
React renders it, Framer Motion animates it, and that is the whole stack.

The two phones talk to each other over **WebRTC**, peer to peer. A public PeerJS broker
introduces them — it sees IP addresses and random peer IDs while connecting, and nothing
else. Once the data channel opens, everything flows directly between the devices, already
encrypted before it leaves.

Sync is last-write-wins on a per-record timestamp, and it converges from both directions:
each phone sends the other a manifest of what it has, and asks only for what it is missing
or has an older copy of. Deletions travel as tombstones, so removing a photo on one phone
removes it on the other.

---

## Security model

**What's encrypted.** The contents of every record — captions, letter bodies, milestone
titles, bucket-list text, photo bytes — plus the metadata that used to sit in the clear:
dates, categories, completion flags, unlock dates.

**What isn't.** Three fields stay readable so that two phones can compare notes without
unlocking anything: the record's random `id`, its `updatedAt` timestamp, and whether it is
deleted. Someone with access to the raw database learns how many records exist and roughly
when they changed — not what any of them say.

**The passphrase.** Minimum 16 characters, and it never leaves memory. It is not written
to `localStorage`, `sessionStorage`, a cookie or a log, and it is never sent over the
network. Both phones must type the *same* passphrase — that is what makes them able to
read each other's records.

The derived key is a non-extractable `CryptoKey` held only in memory. The practical
consequence: **reloading the page asks for the passphrase again.** That is the cost of not
storing it anywhere, and it is deliberate.

Keys derive at 600,000 PBKDF2 iterations. The count is recorded on the vault itself rather
than assumed, so it can be raised later without locking an existing vault out.

**Time-locked letters.** A sealed letter's body is wrapped under a key derived from its
unlock date, so the app genuinely cannot open it early and editing the stored date breaks
the letter rather than unlocking it.

It is still a guardrail, not a vault. Anyone who knows the passphrase can move their
phone's clock forward, or call the unseal function from the browser console. A real
non-interactive time lock needs an external beacon, which a zero-server app does not have.
Treat it as a promise you're both keeping, not a lock you couldn't pick.

**What this does not protect against.** A compromised phone — if someone has your unlocked
device, they have your memories. A weak passphrase, since it is the only secret. And each
other: this is an app for two people who trust one another, not a system with two mutually
suspicious parties.

**No recovery.** Lose the passphrase and the data is gone. Not "email support" gone —
mathematically gone. Nobody can reset it, including you. Keep a `.vault` backup somewhere
safe, and remember it needs *two* passphrases to restore: the one you set on the file, and
the vault passphrase the records inside were written with.

---

## Pairing the two phones

Both phones need the same passphrase, then one of:

- **Share a link.** Sync Hub → *Share Pairing Link*. Send it over WhatsApp or anything
  else; opening it on the other phone offers to connect.
- **Scan a QR code.** One phone shows its code in the Sync Hub, the other taps *Scan* and
  points the camera at it. Best when you're together.
- **Type the code.** Every phone has a short pairing code you can read out loud.

The app asks before connecting to a link someone sent you, because connecting reveals your
IP address to whoever is on the other end. Only accept links from your partner.

Both phones have to be open at the same time to sync — there is no server holding messages
for later. The app reconnects on its own when you unlock your phone or come back onto Wi-Fi.

---

## Deploying

The build is static files, so anything that serves a folder works — Vercel, Cloudflare
Pages, GitHub Pages, Netlify:

```bash
npm run build   # → dist/
```

`vercel.json` ships the security headers (CSP, `frame-ancestors`, HSTS, referrer policy).
**If you deploy somewhere else, port those headers across** — `index.html` carries a
fallback CSP meta tag, but `frame-ancestors` cannot be expressed in a meta tag and only
works as a real header.

**HTTPS is required**, not optional. The Web Crypto API and the camera are both
unavailable on plain HTTP, so the app cannot unlock or scan a QR code without it.

### Install as an app

Open the deployed URL on Android, then browser menu → *Add to Home screen*. You get a
standalone window with no address bar, and a service worker caches the app shell so it
starts offline. Your records were always local; the worker just means the app itself loads
without a connection.

### Testing on a phone

`npm run dev` serves over `http://<your-ip>:5173`, and that is **not** a secure context, so
crypto and the camera will both fail. Either use a tunnel that terminates TLS (`ngrok`,
`cloudflared`), or add a dev certificate via `@vitejs/plugin-basic-ssl`.

---

## Known limits

- **Carrier NAT can block a direct connection.** There is no TURN relay configured, only
  STUN. Two phones on mobile data behind carrier-grade NAT may fail to connect; the app
  says so rather than spinning. On the same Wi-Fi it is reliable.
- **A reload asks for the passphrase again** — see above; the key is memory-only by design.
- **Both phones must be online together** to sync. Nothing queues server-side.
- **App icons are SVG only.** iOS ignores SVG icons, so a home-screen install there falls
  back to a screenshot. Generating a PNG set (192/512, plus a maskable variant with ~20%
  padding) would fix it.
- **Photos are capped** at 9 MB after compression, derived from the sync frame size so
  that anything the app accepts is guaranteed to reach the other phone.

---

## Project layout

```
src/
  services/
    crypto.js      Encryption, key derivation, record envelopes, time-lock sealing
    peerSync.js    WebRTC transport, pairing handshake, replication protocol
    vaultKey.js    In-memory key holder
    limits.js      Size ceilings shared by storage and the wire
  db/index.js      Dexie schema, backup import/export, record integrity gates
  context/         VaultContext (lock/unlock), SyncContext (pairing lifecycle)
  components/      One folder per screen, plus layout/ common/ sync/
  utils/           Dates, image compression, invite links
test-crypto.mjs    Test suite — runs in plain node, no browser needed
```

---

## Notes for contributors

`npm test` runs the whole suite in node with no browser. It exercises the real shipped
functions rather than reimplementations — the database methods are bound to an in-memory
store so the actual merge and integrity code runs.

A few invariants the tests hold in place, worth knowing before changing anything in
`services/` or `db/`:

- **Reads name their table.** `decryptRecord()` takes the table it is reading so a record
  sealed for one list cannot be presented as another. The suite scans the source and fails
  if any caller omits it, because the parameter is legitimately optional for older records
  and nothing else can tell "forgot" from "hasn't got one".
- **A record may be created freely, but may only overwrite or delete an existing one if it
  is fully sealed** — header, table and photo bytes all bound to the ciphertext. This is
  what lets an old backup restore while stopping a hand-built file from erasing anything.
- **Timestamps only move forward.** Records are stamped from a monotonic clock rather than
  raw `Date.now()`, so a phone with a slow clock can still win a merge and a phone whose
  clock jumped into the future recovers instead of poisoning every write.

Stack: React 18, Vite, Tailwind, Dexie, PeerJS, Framer Motion. No backend to run.
