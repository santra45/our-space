# Our Space 💕 (Private Couple's Sanctuary)

A private, end-to-end encrypted, local-first web app for two people. There is no
backend and no account: every record lives in the browser's IndexedDB on each
device, encrypted with a key derived from a passphrase only the two of you know,
and the devices replicate directly to each other over WebRTC.

Built with React 18, Vite, Tailwind CSS, Framer Motion, Dexie.js, the Web Crypto
API and PeerJS.

> **On the phrase "zero-knowledge."** There is no server that could learn
> anything, because there is no server. That is a property of the architecture,
> not a proof of any particular cryptographic claim. The honest limits are spelled
> out in [What this does *not* protect you from](#5-what-this-does-not-protect-you-from),
> and that section is the one worth reading.

---

## 🛡️ Security Architecture

### 1. The vault key

- **Derivation**: PBKDF2-HMAC-SHA-256 over a 16-byte cryptographically random
  salt, producing a 256-bit AES-GCM key.
- **Iterations**: **600,000** for vaults created by current builds. Vaults
  created before that change keep deriving at their original **250,000** — the
  count is recorded as `kdfIterations` on the vault metadata row and read back at
  unlock. An existing vault *cannot* be silently upgraded, because changing the
  iteration count changes the key and would require re-encrypting every record.
  Unlock tries the recorded count first and falls back, so nobody is locked out
  and nothing is destroyed. If you want 600,000 on an old vault, the only route
  is exporting a backup, creating a fresh vault, and importing.
- **Passphrase policy**: minimum 16 characters. The passphrase is NFKC-normalised
  and trimmed before derivation, so two devices that compose an accented
  character differently — or a phone that appends a trailing space on paste —
  still derive the same key.
- **Encryption**: AES-GCM-256 with a fresh 96-bit IV per item and a 128-bit
  authentication tag. Any bit-level modification, or the wrong key, causes
  decryption to fail rather than return garbage.

### 2. Where the key lives, and what a reload costs you

The derived `CryptoKey` is created **non-extractable**. It is held in exactly two
places, both of which are JavaScript heap: React state, and a module-scoped
singleton (`src/services/vaultKey.js`) so it survives client-side navigation
inside the app.

**Nothing derived from your passphrase is written to `sessionStorage`,
`localStorage`, IndexedDB, cookies, or the URL — and neither is the passphrase
itself.** An earlier build did stash the plaintext passphrase in `sessionStorage`
to make refreshes seamless. That was a real hole — any XSS on the origin could
read it — and it has been removed.

The direct consequence, stated plainly because it is a usability cost you will
notice: **a full page reload wipes the key, and you have to type the passphrase
again.** Moving between screens inside the app does not. Locking the vault clears
the key immediately.

### 3. What is encrypted at rest, and what is not

Records are stored in schema **v2**. Every field of every record sits inside a
single AES-GCM envelope. Photo blobs are encrypted separately as binary and are
never base64-inflated on disk.

Exactly three fields are stored in the clear, because the sync protocol has to
compare records without decrypting them:

| Plaintext on disk | Why it has to be |
| --- | --- |
| `id` | Primary key. Random, carries no meaning. |
| `updatedAt` | Millisecond timestamp. Needed for last-write-wins merges. |
| `_del` | A `0`/`1` tombstone flag. Needed so deletions replicate. |

Everything else — captions, letter bodies, milestone titles, bucket-list text,
dates, categories, completion state, unlock dates, whether a letter has been
opened — is inside the envelope. Earlier builds indexed `date`, `category`,
`unlockDate`, `completed` and `isOpened` as plaintext IndexedDB indexes; those
indexes are gone, and filtering and sorting now happen in memory after
decryption.

**What that still leaks to someone holding your disk but not your passphrase:**
how many records exist, of which kind, when each was last touched, which are
deleted, and roughly how large each photo is. Not their contents.

Vaults written by older builds are migrated to v2 automatically on the first
successful unlock. The migration preserves `id` and `updatedAt` so it does not
churn the sync manifest, and it is idempotent.

### 4. Time-locked letters — the real construction

The lock is not a UI clock check. Sealing a letter derives a wrapping key that
depends on the unlock date:

```
contentKey  = random AES-GCM-256
ciphertext  = AES-GCM(contentKey, iv, plaintext, AAD = binding)
binding     = "our-space/time-lock/v1|<unlockDate>|<record id>"
material    = AES-GCM(vaultKey, lockIv, binding)
lockKey     = HKDF-SHA256(material, salt = lockSalt, info = binding)
wrappedKey  = AES-GCM(lockKey, wrapIv, rawContentKey, AAD = binding)
```

Only `wrappedKey`, `ciphertext` and the public parameters are stored. The content
key itself is never persisted, and the letter body is not present in the record
envelope at all.

**What that genuinely buys you:**

- Editing the stored unlock date to open a letter early makes decryption **fail**.
  The date feeds both the key derivation and the AEAD associated data, so a
  changed date yields a different wrapping key. This is not a check that can be
  patched out of the UI or bypassed by a bug in a date comparison.
- Moving a sealed payload onto a different record fails the same way, because the
  record id is bound in too.
- Against anyone without the vault passphrase, a sealed letter is exactly as
  strong as every other record: AES-GCM-256.

**What it does not buy you:**

- **You can open your own letters early.** Every input needed to re-derive the
  wrapping key is on the device from the moment the letter is written. Moving the
  system clock forward, or calling the crypto module from a browser console,
  opens it immediately. **No purely client-side construction can prevent this.**
- Your partner's device can do the same, because you share one vault key.
- Malware, a hostile browser extension, or XSS while the vault is unlocked can do
  the same.

A time lock that holds against the vault owner needs something this app
deliberately does not have: a trusted third party that withholds the key until
the date, or a verifiable delay function. Sequential-work schemes were considered
and rejected — they punish the honest reader exactly as much as the impatient one
and buy nothing against faster hardware.

So: the lock is real against tampering with the *data*, and honest about being
unenforceable against the person who owns the vault. Treat it as a promise you
make to each other, backed by cryptography that stops the data being quietly
rewritten — not as a safe you cannot open.

### 5. What this does *not* protect you from

- **A weak passphrase.** Everything rests on it. There is no server-side rate
  limit, because there is no server; an attacker with a copy of your IndexedDB
  can grind offline at whatever rate their hardware allows.
- **A lost passphrase.** There is no recovery, no reset, no backdoor. If you both
  forget it, the data is gone permanently. Keep an encrypted backup *and*
  remember the passphrase.
- **A compromised device.** While the vault is unlocked, decrypted photos and
  letters are in RAM and on screen. Root-level malware, a hostile browser
  extension, or an XSS on the origin can read them. Lock the vault when you put
  the phone down.
- **Metadata at rest.** See the table in §3.
- **Signalling metadata and persistent peer ids.** See §7.
- **Your invite links.** See §7.
- **Traffic analysis by whoever runs your network.** They see two devices holding
  an encrypted WebRTC data channel, and roughly how much data moves. Not what.
- **Anything at all if you paste the passphrase into a chat app.** Say it out
  loud, in person.

### 6. Peer-to-peer replication

- **Protocol `SWEETHEART_V2`.** Every frame on the wire is AES-GCM encrypted
  under the vault key. A build running the older `SWEETHEART_V1` protocol is
  **not** interoperable; it is rejected with an explicit version-mismatch error
  rather than failing mysteriously. Update both devices together.
- **Mutual challenge-response.** Both devices exchange encrypted random nonces
  and verify the echo, then invalidate the nonce so it cannot be replayed. A
  30-second timeout drops peers that never authenticate.
- **Nothing moves before authorisation.** Manifest exchange, record transfer and
  live broadcasts are all gated on mutual authorisation. The UI's connection
  indicator is driven by the *authorised* state and never by the raw socket, so
  an unauthenticated stranger who knows your peer id cannot make the app display
  a green "connected" badge.
- **`vaultMeta` never crosses the wire.** The salt and canary are excluded from
  the sync table allowlist entirely.
- **Merge rule.** Newer `updatedAt` wins; on an exact tie a deletion wins; on a
  further tie a deterministic fingerprint decides, so both devices converge on
  the same answer. Timestamps that are not finite, are negative, or are more than
  24 hours in the future are rejected outright, so a badly skewed clock cannot
  install a record that wins forever.
- **Transfers are chunked** with a per-frame byte budget, and every drop path
  (record too large, oversized frame, corrupt frame, storage full) surfaces a
  visible error instead of failing silently.

### 7. Read this before pairing

- **There is no TURN server, and one is not going to be added.** Connections rely
  on STUN for NAT traversal. **If both phones are behind carrier-grade NAT — a
  common configuration on mobile data with some ISPs — the direct connection will
  not establish at all.** When that happens the app reports an explicit
  `ice_failed` state and tells you to retry on the same Wi-Fi or a different
  network, rather than spinning forever. Both devices on one Wi-Fi network is the
  reliable case. A TURN server would fix it, but it would mean paying for and
  trusting a relay that sees both IPs and all the (encrypted) traffic, which is
  exactly what this design is trying to avoid.
- **The connection-route indicator is honest.** It reports `direct`, `relayed` or
  **`unknown`**, and it says `unknown` when it genuinely cannot tell. It does not
  claim "Direct P2P" on a guess. The route is re-polled after ICE settles instead
  of being sampled once at authentication time.
- **The public PeerJS broker sees connection metadata.** WebRTC needs a signalling
  rendezvous. `0.peerjs.com` sees your IP address, user agent and peer id while a
  connection is being set up. It never sees content, photos, or your passphrase.
  Once the data channel is open, traffic is direct.
- **Your device's peer id is persistent.** It is generated once (80 bits of
  entropy, Crockford base32) and stored in `localStorage` so reconnecting after a
  reload works. That makes it a stable identifier this device presents to the
  public broker on every launch — enough for that third party to correlate your
  sessions over time and to link the two paired devices as a pair. It is a real
  privacy trade-off, made in exchange for reconnection working. Clearing site data
  rotates it.
- **Invite links carry more than a peer id.** The `#connect=` fragment contains
  the vault **salt** (not secret, but it identifies your vault), plus your couple
  name and anniversary date. URL fragments are not sent to web servers, but the
  link itself lands in whatever messenger you paste it into. Prefer the in-person
  QR method when you can.
- **Incoming invite links are not auto-dialled.** A link from an unrecognised peer
  waits behind an explicit confirmation, so a crafted link cannot silently make
  your browser start an ICE exchange and reveal your local IP to the sender.

### 8. Encrypted backups (`.vault`)

- Export encrypts the whole archive into a single AES-GCM container with a fresh
  salt and IV. The container records its own `kdfIterations`, so containers
  written by older builds still open.
- **The backup passphrase is verified against the live vault before the file is
  written**, so a typo cannot produce a `.vault` file nobody can ever decrypt.
- Import rejects a tampered container at the authentication tag, before a single
  byte reaches the database, and refuses files above 150 MB.
- **Import never restores `vaultMeta`.** Writing an old backup's salt and canary
  over a live vault would orphan every record created since that backup, so the
  table is excluded from the importable set entirely.
- Re-initialising a vault destroys access to everything already in it, so both the
  "create new" and "join partner" paths refuse to overwrite an existing vault
  unless you type an explicit confirmation phrase.

### 9. Transport hardening

The authoritative Content-Security-Policy ships as an **HTTP response header**
(see `vercel.json`), because `frame-ancestors` is ignored in a `<meta>` tag. The
meta tag in `index.html` is kept as defence in depth for static hosting that
sends no headers at all. If you change one, change both.

Headers set on every response: `Content-Security-Policy` (including
`frame-ancestors 'none'`), `X-Frame-Options: DENY`,
`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
`Strict-Transport-Security` (2 years, `includeSubDomains`, not preloaded),
`Permissions-Policy` (camera allowed for QR scanning, everything else denied) and
`Cross-Origin-Opener-Policy: same-origin`.

**If you deploy anywhere other than Vercel you have to port those headers
yourself.** `vercel.json` is Vercel-specific; Cloudflare Pages uses a `_headers`
file; GitHub Pages cannot set response headers at all, so there you get only the
weaker meta-tag policy and no clickjacking protection.

---

## 📴 Offline support

A hand-written service worker (`public/sw.js` — no dependency, no build step)
ships with the app and is registered from `src/main.jsx` **in production builds
only**; during `vite dev` it would fight HMR.

- **Navigations** are network-first, falling back to the cached shell. A new
  deployment is picked up as soon as the network allows.
- **`/assets/*`** (Vite's content-hashed bundles) are cache-first, which is always
  correct because the hash changes whenever the content does.
- **Other same-origin GETs** are stale-while-revalidate.

What it deliberately does not do:

- It only ever intercepts **same-origin GET** requests. Cross-origin traffic is
  passed through untouched, so PeerJS signalling is unaffected — and the broker
  WebSocket is not a `fetch` event in the first place.
- It never touches IndexedDB. A service worker cannot intercept IndexedDB at all,
  so every encrypted record and photo blob is outside its reach. Nothing decrypted
  is ever written to the Cache Storage API; the only thing cached is the public
  app shell that anyone can download from the deployed URL anyway.
- Non-GET and range requests are passed through, so nothing mutating is replayed
  and no partial response is stored as if it were a whole one.

**Honest scope:** this makes the *app* work with no network — open it, unlock,
read and write your own records. It does not make *syncing* work offline;
replication needs both devices reachable. The very first visit needs a network,
and a browser that has never run the service worker just loads online as normal.

---

## 📱 Deploying and pairing

### Deployment

The app compiles to static files in `dist/`, so any static host works:

- **Vercel** — `npx vercel`, or the GitHub integration. The only host where
  `vercel.json` applies the security headers automatically.
- **Cloudflare Pages** — drag and drop `dist/`, then port `vercel.json`'s headers
  into a `_headers` file.
- **GitHub Pages** — works, but cannot set response headers. See §9.

### Install as an app (PWA)

1. Open your deployed URL in Chrome or Samsung Internet on Android.
2. Menu → **"Add to Home screen"** / **"Install app"**.
3. It installs with an icon and a full-screen view, and works offline as described
   above.

### Pairing

- **Invite link** — tap the sync pill in the header → **"Share Pairing Link"** and
  send it. Read §7 first; the link contains your vault salt and couple details.
- **QR code (preferred)** — when you are physically together, one phone shows the
  QR code in the Sync Hub and the other scans it. Nothing leaves the room.

Both of you must type the **same passphrase**. It is never transmitted, so pairing
verifies the typed passphrase against the inviter's canary before it writes
anything — a mismatch is caught at pairing time instead of silently creating two
divergent vaults.

---

## 🎨 Features

- **Love Countdown & Milestones** — live counter (days, hours, minutes, seconds),
  anniversary radar, and a custom milestone scrapbook.
- **Polaroid Photo Wall** — polaroids with washi tape, handwritten fonts, 3D tilt,
  and client-side canvas compression to WebP before encryption.
- **Date Night Scratch-Off** — canvas scratch card with touch physics, confetti,
  and four categories (At-Home, Outdoor, Foodie, Budget).
- **Secret Capsule & Love Letters** — time-locked notes with wax-seal animations.
  See §4 for what the lock actually guarantees.
- **Shared Bucket List** — checklist with progress bars, completed stamps and
  haptics.

---

## 🧑‍💻 Development

```bash
npm install
npm run dev          # Vite dev server, bound to the LAN for phone testing
npm run build        # production build into dist/
npm run preview      # serve the production build locally
npm run test:crypto  # Web Crypto / PBKDF2 / AES-GCM verification suite
```

`npm run test:crypto` (aliased as `npm test`) runs `test-crypto.mjs` against
`src/services/crypto.js` in Node. There is no component or integration test
framework in this project — that is a gap, not a claim of coverage.

### Known TODO: PNG app icons

`public/manifest.json` and `index.html` reference `/icons/icon-192.png`,
`/icons/icon-512.png` and `/icons/icon-maskable-512.png`. **Those files do not
exist yet and need to be generated from `public/favicon.svg`.** Until they are,
Android falls back to the SVG icon (still installable) and iOS falls back to a
screenshot. Generate them with any SVG-to-PNG tool, for example:

```bash
npx sharp-cli -i public/favicon.svg -o public/icons/icon-192.png resize 192 192
npx sharp-cli -i public/favicon.svg -o public/icons/icon-512.png resize 512 512
# the maskable variant needs roughly 20% padding so the safe zone is respected
```
