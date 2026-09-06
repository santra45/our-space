# Our Space 💕 (Private Couple's Sanctuary)

A private, zero-knowledge, local-first couple's web application designed from scratch for two partners. Built with modern web standards (React 18, Vite, Tailwind CSS, Framer Motion, Dexie.js, Web Crypto API, and WebRTC PeerJS).

---

## 🛡️ Core Security & Privacy Guarantees

1. **Zero Third-Party Plaintext Storage**:
   - No Firebase, Supabase, AWS S3, or remote database.
   - All memories, letters, photos, and date ideas live inside your browser's local **IndexedDB**.
2. **Zero-Knowledge Web Crypto**:
   - Powered by the native W3C **Web Cryptography API** (`crypto.subtle`).
   - Master key derived via **PBKDF2 (HMAC-SHA-256, 250,000 iterations)** with a cryptographically random salt.
   - All text, notes, and photos are encrypted client-side using **AES-GCM 256-bit** with unique 96-bit random IVs for every record.
   - The master key lives only in active browser memory and is never written to disk or sent across any network.
3. **Direct Peer-to-Peer Synchronization**:
   - Uses **WebRTC DataChannels** (via PeerJS) for direct phone-to-phone data replication.
   - Before syncing, both devices perform an automated zero-knowledge authentication challenge over the data channel to verify they share the exact same passphrase.
   - Once paired, newly added polaroids, letters, and bucket list checks sync directly between your devices.
4. **Failsafe Encrypted Backup (`.vault`)**:
   - 1-tap export/import of all your encrypted memories into a single `.vault` file.
   - You can send this file via WhatsApp or Telegram anytime as an offline backup—even messaging providers cannot read it without your shared passphrase.

---

## 📱 How to Use on Two Android Devices

### 1. Free Zero-Backend Deployment (1-Click)
Because the app has zero server database and compiles to static files (`dist/`), you can host it for free on:
- **Cloudflare Pages**: Connect your Git repository or drag-and-drop the `dist/` folder.
- **Vercel**: Deploy with `npx vercel` or GitHub integration.
- **GitHub Pages**: Free static hosting directly from your repo.

### 2. Install as an App on Android (PWA)
1. Open your deployed URL (e.g. `https://our-space.pages.dev`) in **Chrome** or **Samsung Internet** on your Android phone.
2. Tap the browser menu (three dots) and select **"Add to Home screen"** or **"Install app"**.
3. It will install with a custom app icon, splash screen, and full-screen view (no browser address bar), working fully offline.

### 3. Effortless Pairing
- **Method 1 (Instant WhatsApp Invite)**: Tap the sync status pill in the top header -> tap **"Share Pairing Link (WhatsApp)"**. Send the link to your girlfriend. When she taps it on her Android phone, the app launches and auto-connects via WebRTC!
- **Method 2 (Camera QR Scan)**: When you are together, one phone displays the QR code in the Sync Hub, and the other taps **"Scan Her QR"** to scan it directly using the phone's camera.

---

## 🎨 Features

- **Love Countdown & Milestones**: Live precision counter (days, hours, minutes, seconds), anniversary radar, and custom milestone scrapbook.
- **Polaroid Photo Wall**: Realistic polaroids with washi tape, handwritten fonts, 3D interactive tilt, and client-side canvas photo compression to high-res WebP (~250KB).
- **Date Night Scratch-Off**: Interactive canvas scratch card with touch physics, celebratory confetti, and 4 categories (At-Home, Outdoor, Foodie, Budget).
- **Secret Capsule & Love Letters**: Time-locked notes that remain sealed until future anniversaries or dates, with 3D wax-seal breaking animations.
- **Shared Bucket List**: Couple's checklist with progress bars, completed stamps, and tactile vibrations (`navigator.vibrate`).
