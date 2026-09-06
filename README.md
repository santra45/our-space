# Our Space 💕 (Private Couple's Sanctuary)

A private, local-first couple's web application designed from scratch for two partners. Built with modern web standards (React 18, Vite, Tailwind CSS, Framer Motion, Dexie.js, Web Crypto API, and WebRTC PeerJS).

---

## 🛡️ Security Architecture & Threat Model

### 1. Client-Side Cryptography (Zero-Knowledge Storage)
- **Engine**: W3C standard Web Cryptography API (`crypto.subtle`).
- **Key Derivation**: PBKDF2 with **HMAC-SHA-256 (250,000 iterations)** and a cryptographically secure 16-byte random salt.
- **Passphrase Policy**: Enforced **minimum 16 characters**. The plaintext passphrase is never logged, stored in cookies/localStorage, or transmitted over any network.
- **Encryption**: **AES-GCM 256-bit** with a unique 96-bit (12-byte) random IV per item. AES-GCM guarantees both confidentiality and integrity (128-bit authentication tag). Any bit-level modification or incorrect key causes immediate decryption rejection.
- **In-Memory Lifecycle**: The derived `CryptoKey` is held only in active React memory. Locking the vault or closing the browser window wipes the key from memory.

### 2. Direct Peer-to-Peer Synchronization (WebRTC)
- **Mutual Challenge-Response Authentication**:
  - When connection initiates, both devices exchange cryptographically random 128-bit nonces encrypted with the shared key.
  - Both devices verify the returned echo against their pending nonce and invalidate it immediately after use to prevent replay attacks.
  - A strict **30-second authentication timeout** disconnects unverified peers.
- **Channel Access Gate**:
  - Unauthenticated peers cannot request or receive records.
  - Manifest exchange, record transfer, and live broadcasts are strictly blocked until mutual authorization completes.
- **Payload & Schema Hardening**:
  - Strict allowlist of message types and database tables (`vaultMeta` is strictly forbidden from network transmission).
  - Maximum payload size limits and record schema validation before any IndexedDB write.

### 3. Single-Container Encrypted Backups (`.vault`)
- Exporting a backup compiles the records and encrypts the entire archive as a single **AES-GCM 256-bit container** with a fresh salt and IV derived from the user's passphrase.
- Tampered or corrupted backup files fail authentication tag verification and are completely rejected before any data is written to the database.

### 4. Realistic Boundaries & Threat Model Scope
- **Passphrase Strength**: Security depends entirely on choosing a strong, unguessable passphrase of at least 16 characters known only to the couple.
- **Signaling Server Metadata**: WebRTC requires an initial signaling handshake to discover IP addresses and coordinate NAT traversal. The public PeerJS signaling broker (`0.peerjs.com`) coordinates connection setup and sees transient connection metadata (IP addresses, user agents, and random Peer IDs). No plaintext content, photos, or passphrases ever touch the broker. Once the direct WebRTC data channel opens, communication is 100% peer-to-peer.
- **Local Endpoint Security**: Decrypted memories and photos reside in active browser memory (RAM) while the vault is unlocked. If a physical device or browser is compromised with root-level malware, in-memory data could be inspected while unlocked. Always lock the vault when leaving devices unattended.

---

## 📱 How to Use on Two Android Devices

### 1. Free Zero-Backend Deployment
Because the app has zero server database and compiles to static files (`dist/`), you can host it for free on:
- **Cloudflare Pages**: Connect your Git repository or drag-and-drop the `dist/` folder.
- **Vercel**: Deploy with `npx vercel` or GitHub integration.
- **GitHub Pages**: Free static hosting directly from your repo.

### 2. Install as an App on Android (PWA)
1. Open your deployed URL in **Chrome** or **Samsung Internet** on your Android phone.
2. Tap the browser menu (three dots) and select **"Add to Home screen"** or **"Install app"**.
3. It will install with a custom app icon, splash screen, and full-screen view (no browser address bar), working fully offline.

### 3. Effortless Pairing
- **Method 1 (Instant WhatsApp Invite)**: Tap the sync status pill in the top header -> tap **"Share Pairing Link (WhatsApp)"**. Send the link to your girlfriend. When she taps it on her Android phone, the app launches and auto-connects via WebRTC!
- **Method 2 (Camera QR Scan)**: When you are together, one phone displays the QR code in the Sync Hub, and the other taps **"Scan Her QR"** to scan it directly using the phone's camera.

---

## 🎨 Core Features

- **Love Countdown & Milestones**: Live precision counter (days, hours, minutes, seconds), anniversary radar, and custom milestone scrapbook.
- **Polaroid Photo Wall**: Realistic polaroids with washi tape, handwritten fonts, 3D interactive tilt, and client-side canvas photo compression to high-res WebP (~250KB).
- **Date Night Scratch-Off**: Interactive canvas scratch card with touch physics, celebratory confetti, and 4 categories (At-Home, Outdoor, Foodie, Budget).
- **Secret Capsule & Love Letters**: Time-locked notes that remain sealed until future anniversaries or dates, with 3D wax-seal breaking animations.
- **Shared Bucket List**: Couple's checklist with progress bars, completed stamps, and tactile vibrations (`navigator.vibrate`).
