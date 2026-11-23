# Fareeq

Link up with the people you travel with and see each other on one live map, with no calls or "where are you?" texts.

* Animated onboarding, group creation, join-by-code
* Live map (OpenStreetMap, **no API key, no billing**) with smoothly gliding, pulsing markers
* Distance to each friend, "last seen", tap to fly to them, one-tap directions
* Pause sharing at any time
* **QR invite**: anyone in the group can show a QR; friends scan it from "Join with code"
* **Guide line**: tap a person (or the meeting point) to draw a free straight line with distance and walking time; one tap opens walking directions in your maps app
* **SOS**: red alert with exact location to the whole group, with a "Go" button that draws the line to them
* **Meeting point**: long-press the map
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

## Limits to know
* Spark quota: ~20k writes/day. Location is only written when you move 15 m, which supports a small group on a trip.
* Sharing continues in the background through an Android foreground service (a persistent "Fareeq is sharing your location" notification). Some phones (Xiaomi, Huawei, Samsung) kill background apps: set battery to "Unrestricted" for Fareeq.
* Everyone needs internet (roaming/eSIM/Wi-Fi) to share and see locations.
* OSM's public tile server is for light use. For a big public launch, switch to a free-tier tile provider.
* Installing: Android APK sideload is free; Play Store is a one-time $25, App Store $99/yr.
