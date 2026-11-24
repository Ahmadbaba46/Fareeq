# Releasing Fareeq on Google Play

## 1. Create your upload key (once, keep it safe)
```
keytool -genkey -v -keystore ~/fareeq-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```
Back the `.jks` file and its passwords up somewhere safe. If you lose it you must
ask Google to reset the upload key.

Create `android/key.properties` (this file is git-ignored, never commit it):
```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/absolute/path/to/fareeq-upload.jks
```

## 2. Build
```
flutter build appbundle --release \
  --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_SENDER_ID=...
```
Upload `build/app/outputs/bundle/release/app-release.aab`. Raise `version:` in
`pubspec.yaml` (e.g. `1.0.1+2`) for every upload; the number after `+` must increase.

Note: an APK signed with a different key than the one already installed cannot
update it. Uninstall the old test build first.

## 3. Play Console checklist (one-time $25 developer account)
* **Privacy policy URL** - required because the app collects location. It should say:
  location is shared only with the groups you join, is stored in Firebase while a
  trip is active, and is deleted when the creator ends the trip.
* **Data safety form** - declare *Precise location* (collected, shared with other
  group members, not sold) and *Name* (the display name).
* **Foreground service permission declaration** - Play asks why the app uses
  `FOREGROUND_SERVICE_LOCATION`. Answer: sharing live location with the user's
  travel group while the app is in the background. You must attach a short screen
  recording showing the persistent "Fareeq is sharing your location" notification.
* **Content rating**, **target audience** (18+ is simplest), app icon and screenshots.
* New personal accounts must run a closed test with 12+ testers for 14 days before
  production access.

## 4. Firebase hygiene before real users
* In Firebase console > Authentication > Settings, keep only **Anonymous** enabled.
* Google Cloud console > Credentials > restrict the Android API key to package
  `com.fuyoudhat.fareeq` and your signing certificate's SHA-1.
* Watch Firestore usage (Spark plan: ~20k writes/day). Upgrade only if you outgrow it.
