# Fareeq

Link up with the people you travel with and see each other on one live map, with no calls or "where are you?" texts.

* Home: live trip card with a mini-map, quick actions (New group / Join with code / Scan QR) and a trips list with live counts
* Animated onboarding, group creation, join-by-code
* Live map (OpenStreetMap, **no API key, no billing**) with smoothly gliding, pulsing markers
* Distance to each friend, "last seen", tap to fly to them, one-tap directions
* Pause sharing at any time
* **QR invite**: anyone in the group can show a QR; friends scan it from "Join with code"
* **Guide line**: tap a person (or the meeting point) to draw a free straight line with distance and walking time; one tap opens walking directions in your maps app
* **SOS**: red alert with exact location to the whole group, with a "Go" button that draws the line to them
* **Meeting point**: long-press the map
* **Quick messages** ("Running late", "I am lost"...) shown above your marker for 30 minutes
* **Far-away alert** when someone is >1.5 km from everyone else (can be turned off), **trails** toggle, and a **no-connection banner**
* Share the invite on WhatsApp
* **Push alerts** (SOS, meeting point) and **profile photos** via Cloud Functions + Storage: see `FUNCTIONS.md`
* **Dark mode** (Auto/Light/Dark, dark map tiles), **emoji avatars** and an editable profile (tap your avatar on the home screen)
* **Offline maps**: every tile you view is cached for 30 days, and menu > *Save this area offline* pre-loads the visible area (small on purpose, to respect OpenStreetMap's usage policy)
* **Battery saver**: after 4 minutes standing still, location switches from GPS to low-power mode and returns to GPS as soon as you move
* **Lock group** (no new joins) and **End trip** (deletes all locations) for the group creator

## Run it (demo mode, zero setup)
```
flutter pub get
flutter run
```
Without Firebase configured the app runs in **demo mode**: friends are simulated around you.

## Build the APK (GitHub Actions, free)
Every push builds `fareeq.apk`: download it from the repo's **Releases -> Fareeq APK (latest)**
or from the workflow run's **Artifacts**. Enable Actions in the repo if asked.

## Go live for free (Firebase Spark plan, no credit card)
1. console.firebase.google.com -> create project (stay on **Spark**).
2. **Build -> Authentication -> Sign-in method -> Anonymous -> Enable.**
3. **Build -> Firestore Database -> Create** (production mode), then paste `firestore.rules` into the Rules tab and publish. (Re-publish them after updating the app: the rules changed to support locking and ending trips.)
4. **Project settings -> Add app -> Android**, package name `com.fuyoudhat.fareeq`. Skip the download step.
   From Project settings -> General -> your Android app, copy: API key, App ID, Project ID, Project number.
5. In GitHub: repo -> Settings -> Secrets and variables -> Actions -> add:
   `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID` (= project number).
6. Re-run the workflow; the new APK is live (no demo banner).

Local build: `flutter build apk --release --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_SENDER_ID=...`

Do **not** use Cloud Functions (they require the paid Blaze plan).

See `RELEASE.md` for signing and publishing on Google Play.

## Limits to know
* Spark quota: ~20k writes/day. Location is only written when you move 15 m, which supports a small group on a trip.
* Sharing continues in the background through an Android foreground service (a persistent "Fareeq is sharing your location" notification). Some phones (Xiaomi, Huawei, Samsung) kill background apps: set battery to "Unrestricted" for Fareeq.
* Everyone needs internet (roaming/eSIM/Wi-Fi) to share and see locations.
* OSM's public tile server is for light use. For a big public launch, switch to a free-tier tile provider.
* Installing: Android APK sideload is free; Play Store is a one-time $25, App Store $99/yr.
