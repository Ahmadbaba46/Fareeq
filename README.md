# Fareeq

Link up with the people you travel with and see each other on one live map, with no calls or "where are you?" texts.

* Animated onboarding, group creation, join-by-code
* Live map (OpenStreetMap, **no API key, no billing**) with smoothly gliding, pulsing markers
* Distance to each friend, "last seen", tap to fly to them, one-tap directions
* Pause sharing at any time

## Run it (demo mode, zero setup)
```
flutter pub get
flutter run
```
Without Firebase configured the app runs in **demo mode**: friends are simulated around you.

## Go live for free (Firebase Spark plan, no credit card)
1. Create a Firebase project (stay on **Spark**).
2. Enable **Authentication -> Anonymous** and create a **Firestore** database.
3. `dart pub global activate flutterfire_cli && flutterfire configure`
4. Publish `firestore.rules` (Firestore -> Rules).
5. `flutter run` - the banner disappears and everything is live.

Do **not** use Cloud Functions (they require the paid Blaze plan).

## Limits to know
* Spark quota: ~20k writes/day. Location is only written when you move 15 m, which supports a small group on a trip.
* Location sharing works **while the app is open**. Background tracking needs an Android foreground service / iOS "Always" permission - a natural next step.
* Everyone needs internet (roaming/eSIM/Wi-Fi) to share and see locations.
* OSM's public tile server is for light use. For a big public launch, switch to a free-tier tile provider.
* Installing: Android APK sideload is free; Play Store is a one-time $25, App Store $99/yr.
