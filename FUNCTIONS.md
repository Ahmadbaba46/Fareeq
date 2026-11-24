# Cloud Functions, push alerts and photos

## What they do
| Function | Trigger | What it does |
|---|---|---|
| `onSos` | someone's SOS turns on | push to everyone else in the group |
| `onMeeting` | a meeting point is set/changed | push to everyone except who set it |
| `cleanupOldTrips` | every 24 h | deletes trips inactive for 7 days (locations, tokens) |

Plus **profile photos** in Cloud Storage (`avatars/<uid>.jpg`, JPEG under 200 KB).
Cost: tiny, well inside the free quotas of the Blaze plan. `maxInstances` is capped at 5.
**Still set a budget alert** (Google Cloud console > Billing > Budgets, e.g. $1).

## Deploy from a phone (Google Cloud Shell, no PC needed)
1. Open https://shell.cloud.google.com in your phone browser (desktop-site mode), sign in with the
   Google account that owns the Firebase project.
2. Get the code. If the GitHub repo is private, create a read-only fine-grained token
   (GitHub > Settings > Developer settings) and use it in the URL:
   ```
   git clone -b ccr-2e54d9e2-c9f9v3 https://YOUR_TOKEN@github.com/ahmadbaba46/fareeq.git
   cd fareeq
   ```
3. Set the region to your Firestore location (table in `functions/.env.example`):
   ```
   echo "REGION=us-central1" > functions/.env
   (cd functions && npm install)
   ```
4. Log in and deploy (the login prints a link; open it, copy the code back):
   ```
   npx firebase-tools login --no-localhost
   npx firebase-tools deploy --only functions,firestore:rules,storage --project fess-f2027
   ```
   If it says an API must be enabled (Cloud Build, Artifact Registry, Eventarc...), accept, or enable them in
   the Cloud console and run the deploy again. The first deploy can take 5 to 10 minutes.
5. Check: Firebase console > Functions shows `onSos`, `onMeeting`, `cleanupOldTrips`.

### Alternative: GitHub Action
`.github/workflows/deploy-firebase.yml` deploys the same way. It needs a repository secret
`FIREBASE_SERVICE_ACCOUNT` (the JSON of a service account you create yourself; never share it with anyone),
and the workflow file must be on the default branch before GitHub lets you run it.

## App side
The APK registers each phone's push token in `groups/<code>/tokens/<uid>` (readable only by that user) and
creates the high-priority `sos_alerts` channel. Notifications need the Android notification permission.

## Troubleshooting
* No push arrives: check Functions logs (Firebase console > Functions > Logs). Make sure both phones
  allowed notifications and have the new APK, and the region matches Firestore.
* `Storage: object-not-found` or permission errors: publish `storage.rules` (done by the deploy command above).
