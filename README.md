# Our Space

A private app for two people. I made it for the two of us.

Letters, photos, milestones, a bucket list, date ideas, a question to answer every day, and a way to watch a film together from two phones. Everything is encrypted on the phone with a passphrase only the two of you know. No accounts, no ads, no analytics.

## What's in it

The Android app in `mobile/` has everything:

- Sky: today's star, the daily question and the moon
- Letters: send one now or seal it until a date
- Memories: your photos
- Us: your story, dreams and date night
- Watch Together: paste a stream link and both phones play in sync, with chat and voice

The web version in `src/` is smaller: countdown, photos, letters, bucket list, date roulette, the daily question and love bursts.

## Running it

Web:

```bash
npm install
npm run dev
npm test
```

On a phone it needs HTTPS, so use a tunnel or a dev certificate. `npm run build` gives you static files you can host anywhere, and `vercel.json` has the security headers.

Android: put `VITE_MAILBOX_URL` and `VITE_MAILBOX_TOKEN` in `.env`, add your own `google-services.json` to `mobile/android/app/`, then:

```bash
bash mobile/tool/build_release.sh
```

`bash mobile/tool/build_test.sh` builds a separate test app that installs next to the real one and doesn't need Firebase.

Run the app's tests from `mobile/` with `flutter test`.

## Connecting two phones

Send an invite link or scan the QR code in the app. The phones sync directly when both are online. The rest of the time there's a mailbox, a small Cloudflare Worker, and your letters and photos are encrypted before they get there. Setup is in [worker/README.md](worker/README.md).

## Worth knowing

- Forget the passphrase and everything is gone. Nobody can reset it, so keep a backup.
- A sealed letter can be opened early by moving the phone's clock forward. It's more of a promise than a lock.
