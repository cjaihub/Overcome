# Ovacome

**Ovacome** is a self-discovery and digital-addiction recovery app for **Android and iOS**, built with **Flutter** and **Firebase**. It also includes a protected library of PDF books and read-along audiobooks.

- **Identity-first onboarding.** A 10-step wizard. Every screen has an animated icon or live infographic, then a title, a description and the input. Answers save as the user types, and a final review step lets them correct anything.
- **Live AI plan agent.** After onboarding, an agent first looks for an existing template that fits the user's profile. If none fits, it asks Claude to write a new plan. The plan can only use the brand's colours and icons. The user watches each step happen live.
- **Progress tracking.** Dynamic check-in forms (daily check-in, urge log, and others), streaks, a wellbeing trend, a 12-week heatmap and usage stats.
- **Protected library.** A storefront with a 3D carousel and a 3D book you can rotate with your finger. Encrypted PDFs are decrypted in memory only. Audiobooks highlight the line being read and keep playing in the background. An **AI narrator** can retell a passage as a storyteller, a teacher or a motivational speaker.
- **Anti-capture.** Screenshots and screen recording are blocked. The app has no share, print or download options. Each page carries a per-user watermark. See [Security model](#security-model) for what can and cannot be blocked.
- **Access and payments.** Phone-number sign-in with an SMS one-time code. A 7-day free trial, given once per phone number. Monthly and yearly subscriptions, single-book purchases, and one-time unlock codes. Every purchase is checked on the server.
- **Owner dashboard.** For admin accounts: total users, daily active users, subscribers, trials, engagement mix and capture attempts. You can drill into any single user to see their usage, their recovery trend and a full activity log.
- **Settings.** Theme, daily reminder time, default narrator and speed, background audio, biometric app lock, haptics and account deletion.

- **Live tracker (Android).** Real screen time, pickups, notifications and late-night use, taken from Android's usage log and refreshed every 15 seconds. Includes a live timer for the app you're in right now, a focus score, an hour-by-hour chart, written insights, per-app usage with icons, and weekly trends against your target.
- **Guardian mode.** A background service that checks usage every 30 seconds, even when the app is closed. It nudges you after a long session in a watched app, when you hit your daily limit, during your late-night window, and after a burst of unlocks. Nudges arrive as notifications that open the right screen, and can be spoken aloud using your name.
- **AI coach chat.** Text, voice, camera or gallery photos, links that open in in-app browser tabs, and buttons that jump to app screens. The coach knows your plan, your check-ins and your real usage.
- **Emotion-aware voice.** Voice messages include speech rate, loudness variation and pauses, measured on the phone. The coach estimates your mood (shown as an estimate), adjusts its tone, and speaks its reply at a matching pace and pitch.
- **Wake phrase.** Hands-free mode listens for your first name by default, or for any phrase you choose. The assistant's name is also customizable.

---

## Project layout

```
lib/
  core/
    theme/        brand.dart (colours, fonts, icon and accent tokens) · app_theme.dart
    widgets/      animated_step_icon · live_infographics (ring, bars, trend, bubbles) · aurora_background · common
    security/     screen_security (native bridge) · secure_content_guard (watermark + blur on capture)
    services/     firebase_providers · analytics_service · push_service
    router/       app_router (auth/onboarding/admin guards) · splash
  features/
    auth/         phone OTP sign-in · welcome carousel · redeem code
    onboarding/   profile model · autosaving repository · wizard · live plan-agent screen
    progress/     plan/form models · dynamic form renderer · progress analytics
    home/         shell (bottom nav) · Today dashboard
    library/      store · 3D book · secure PDF reader · audiobook read-along · AI narrator
    subscription/ entitlement · store purchases · paywall
    settings/     settings controller + screen
    admin/        owner dashboard · per-user analytics
android/app/src/main/kotlin/.../MainActivity.kt   FLAG_SECURE, screenshot callback, renderer-cache purge
ios/Runner/ScreenSecurity.swift                    secure capture layer, recording/screenshot events
functions/                                         Cloud Functions (TypeScript)
firestore.rules · storage.rules · firestore.indexes.json · firebase.json
```

## Backend (Cloud Functions)

| Function | Trigger | Purpose |
|---|---|---|
| `bootstrapUser` | callable | Creates the user document and grants the trial (one per phone hash). Phones listed in `ADMIN_PHONES` get admin. |
| `redeemAccessCode` / `createAccessCodes` | callable | One-time unlock codes. Only a hash of each code is stored. A code can be tied to one phone number and can expire. |
| `verifyPurchase` | callable | Checks Google Play (Android Publisher API) or App Store (StoreKit 2 signed transaction) purchases, then updates the user's access. A purchase can only unlock one account. |
| `playBillingNotifications` / `appStoreNotifications` | Pub/Sub / HTTPS | Keep renewals, cancellations and refunds in sync. |
| `getBookAccess` | callable | Checks the user has access, then returns the book's AES key and 10-minute signed URLs. |
| `runPlanAgent` | Firestore create `users/{uid}/agentRuns/{id}` | The plan agent: search templates → reuse, or generate with Claude → validate → assign. |
| `narratePassage` | callable | Claude retells a passage in the chosen persona without adding anything new. |
| `aggregateEvent` | Firestore create `users/{uid}/events/{id}` | Rolls up per-user stats, global totals and daily active users. |
| `recountMetrics` / `dailyNudge` | schedule | Nightly subscriber and trial counts; hourly check-in reminders sent by local time. |
| `setAdmin` / `deleteAccount` | callable | Role management and store-compliant account deletion. |

Every callable requires a signed-in user **and** App Check.

---

## Setup

### 1. Firebase project
1. Create a Firebase project on the **Blaze** plan (needed for Functions and signed URLs).
2. Enable **Authentication → Phone**, **Firestore**, **Storage**, **Cloud Messaging** and **App Check** (Play Integrity on Android, App Attest on iOS).
3. Connect the app (this overwrites `lib/firebase_options.dart` and adds the Google Services files):
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<project-id> --platforms=android,ios
   ```
4. Add your SHA-1 and SHA-256 fingerprints to the Android app (needed for phone auth and Play Integrity). On iOS, enable Push Notifications and upload an APNs key.

### 2. Functions configuration
```bash
cd functions && npm install
firebase functions:secrets:set ANTHROPIC_API_KEY      # Claude, for the plan agent and narrator
```
Then set these parameters in `functions/.env.<project-id>`:
```
ADMIN_PHONES=+15551234567          # owner number(s) that get the admin role
ANDROID_PACKAGE=com.overcome.overcome
IOS_BUNDLE_ID=com.overcome.overcome
IOS_APP_ID=1234567890
APPLE_ENV=Production
```
- **Signed URLs:** give the Functions service account the *Service Account Token Creator* role.
- **Google Play:** invite the Functions service account in Play Console → Users & permissions, with "View financial data" and "Manage orders". Create a Pub/Sub topic `play-billing` and select it under Monetization setup → Real-time developer notifications.
- **App Store:** put Apple's root certificates (`AppleRootCA-G3.cer` and others, from apple.com/certificateauthority) in `functions/certs/`. Point App Store Server Notifications V2 to the `appStoreNotifications` URL.

### 3. Store products
Create subscriptions `overcome_premium_monthly` and `overcome_premium_yearly` in both stores. Single books are non-consumable products whose ID matches the book's `productId`.

### 4. Deploy
```bash
firebase deploy --only firestore,storage,functions
cd functions && npm run seed      # approved starter templates for the plan agent
```

### 5. Publish a book
```bash
cd functions
GOOGLE_APPLICATION_CREDENTIALS=sa.json npm run encrypt-book -- \
  --id quiet-mind --title "The Quiet Mind" --author "Jane Doe" \
  --pdf ./quiet-mind.pdf --transcript ./quiet-mind.transcript.json \
  --audio "Chapter 1=./ch1.m4a" --audio "Chapter 2=./ch2.m4a" \
  --cover ./cover.jpg --accent iris --featured --product quiet_mind_book
```
`transcript.json` is a list of `{ "text", "start", "end", "chapter" }` items, with times in milliseconds within each chapter's audio. It drives both the read-along highlighting and the AI narrator.

### 6. Unlock codes (for books sold elsewhere, counselors, or partners)
As an admin, call `createAccessCodes` with `{ count, premiumDays?, bookIds?, phone?, expiresInDays? }`. The response contains the plaintext codes, and this is the only time they are shown.

### 7. Run
```bash
flutter pub get
flutter run
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

## Building and installing

Releases are built by GitHub Actions (`.github/workflows/android-release.yml`) on every push to the release branch, on `v*` tags, or on demand. Each run produces:

| Artifact | Contents | Use |
|---|---|---|
| `ovacome-apks` | `ovacome-arm64-v8a.apk` (most phones), `ovacome-armeabi-v7a.apk` (older phones), `ovacome-x86_64.apk`, `ovacome-universal.apk` | Install directly on any Android 7.0+ device |
| `ovacome-aab` | `ovacome.aab` | Upload to Google Play |
| `ovacome-debug` | R8 mapping and Dart symbols | Make crash reports readable (upload to Play / Crashlytics) |

Release builds are shrunk and obfuscated with R8, have unused resources removed, use obfuscated Dart, and are split per CPU type. Version **1.1.0 (build 2)**.

**Before the first real release:**
1. Run `flutterfire configure`, then either commit `lib/firebase_options.dart` or save it as the `FIREBASE_OPTIONS_DART_B64` secret. (Builds without it install fine, but only show a "setup needed" screen.)
2. Create an upload key: `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Add these secrets: `ANDROID_KEYSTORE_B64` (`base64 -w0 upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without a key, builds are debug-signed. They still install for testing, but Play rejects them.
3. Optional: add `PLAY_SERVICE_ACCOUNT_JSON` so each signed build uploads to Play's **internal testing** track as a draft.

**Install over Wi-Fi** (on your computer, with `adb` from Android platform-tools):
```bash
# On the phone: Developer options → Wireless debugging → ON
./scripts/install-android.sh pair 192.168.1.20:37099 123456   # from "Pair device with pairing code"
./scripts/install-android.sh connect 192.168.1.20:41231
./scripts/install-android.sh install ~/Downloads/ovacome-apks  # picks the right APK for the phone
```
Or copy the APK to the phone and open it. You'll need to allow "Install unknown apps" for your file manager or browser.

**Google Play checklist:** a privacy policy URL; the Data safety form (phone number, usage summaries, chat messages and photos, analytics); the **special-use foreground service** declaration for Guardian mode (explain "digital wellbeing reminders", with a short video); an explanation of why the app uses Usage access and the notification listener; a content rating; and screenshots made from the brand assets.

## Tests
```bash
flutter analyze && flutter test        # app: progress maths, entitlement, encryption, focus score, wake phrase, voice cues, widgets
cd functions && npm test               # backend: access, codes, plan/coach schemas, action allowlist, encryption format
```
There is a cross-language test: a file encrypted by `encrypt-book.ts` is decrypted by the app's Dart code. Tampered files and wrong keys are rejected.

---

## Security model

| Threat | Protection |
|---|---|
| Screenshots or screen recording (Android) | `FLAG_SECURE` on the whole window: captures, casting and the Recent Apps preview come out black. Android 14+ also reports screenshot attempts. |
| Screenshots or screen recording (iOS) | The app is drawn inside the system's secure text-entry layer, so captures come out blank. Recording and mirroring are detected and protected content is blurred. Screenshot attempts are logged. The App Switcher preview is blurred. |
| Downloading or extracting files | Files in Storage are AES-256-GCM encrypted, and Storage rules block all direct reads. Short-lived signed URLs are only issued to users with access. Decryption happens in memory. On Android, the copy the PDF engine stages is deleted as soon as it is opened. App backups are disabled. |
| Sharing or printing | The reader has no share, print, save, copy or open-in options. |
| Tampered or fake clients | App Check is enforced on every function. Access is written only by the server. Firestore rules block clients from editing access, stats or keys. Release builds are shrunk and obfuscated with R8. |
| Trial abuse | One trial per phone number, enforced on the server (stored as a hash). |
| Shared receipts or codes | A store purchase or a code can only unlock one account. |

**Privacy of the tracker:** usage events are read on the phone. Only daily totals, hourly minutes and the names of the most-used apps are synced to `users/{uid}/usage`. The notification listener records which app posted a notification and when, and never the title, text or sender. Voice is transcribed by the phone's speech engine; only the transcript and four numeric voice cues reach the coach.

**Limits to know about:**
- **A camera pointed at the screen cannot be blocked by any app.** The faint per-user watermark (account ID, masked phone number and time) on every protected page lets you trace leaked photos.
- The iOS secure-layer technique relies on how iOS currently handles secure text fields, not on a documented API for this purpose. Re-test it on each major iOS release.
- Rooted or jailbroken devices with hooking tools can get around any app-level protection. App Check (Play Integrity / App Attest) makes this much harder but not impossible.
- **iOS cannot provide the live tracker or Guardian mode.** Apple only shares app usage with apps approved for its Family Controls entitlement, and it doesn't let apps read other apps' notifications. On iPhone, the tracker shows check-ins and in-app activity instead.
- **The wake phrase only works while Ovacome is open.** Always-on wake words with the app closed need a dedicated on-device engine, such as Picovoice Porcupine with a custom keyword.
- Emotion is an **estimate** based on wording and simple voice measurements. It is not a clinical assessment, and the app labels it that way.
- Audiobooks are streamed from short-lived signed URLs and are not encrypted at rest in Storage. For stronger protection, encrypt the audio too and play it through a decrypting stream source.

## Analytics collected
`app_open`, `session_end` (duration), `onboarding_step`, `onboarding_complete`, `plan_assigned`, `form_submit`, `book_view`, `book_open`, `pdf_page_view`, `audio_play`, `audio_complete`, `read_along_start`, `ai_narration`, `paywall_view`, `purchase`, `code_redeemed`, `capture_attempt`.

Events are stored under `users/{uid}/events` (only admins can read them). They are also sent to Firebase Analytics, and rolled up into `users/{uid}.stats` and `metrics/global[/daily/{yyyymmdd}]`. Mention this in your privacy policy and in the Play and App Store data-safety forms.
