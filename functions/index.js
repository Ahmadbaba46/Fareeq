'use strict';

const { setGlobalOptions } = require('firebase-functions/v2');
const {
  onDocumentUpdated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const lib = require('./lib');

admin.initializeApp();
const db = admin.firestore();

// Trigger region must match your Firestore location (Firebase console >
// Firestore > Settings). Set REGION in functions/.env (see RELEASE/FUNCTIONS docs).
setGlobalOptions({
  region: process.env.REGION || 'us-central1',
  maxInstances: 5, // hard cap, keeps costs bounded
});

async function notifyGroup(code, senderUid, kind, details) {
  const msg = lib.buildMessage(kind, details);
  if (!msg) return;
  const snap = await db.collection('groups').doc(code).collection('tokens').get();
  const docs = snap.docs.map((d) => ({ uid: d.id, token: d.get('token') }));
  const targets = lib.recipientTokens(docs, senderUid);
  if (targets.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens: targets.map((t) => t.token),
    notification: { title: msg.title, body: msg.body },
    data: { type: kind, code },
    android: {
      priority: 'high',
      notification: { channelId: msg.channelId },
    },
  });

  // remove tokens that no longer exist
  const dead = [];
  res.responses.forEach((r, i) => {
    if (!r.success && lib.isDeadTokenError(r.error && r.error.code)) {
      dead.push(targets[i].uid);
    }
  });
  await Promise.all(
    dead.map((uid) =>
      db.collection('groups').doc(code).collection('tokens').doc(uid).delete(),
    ),
  );
}

// 1. Someone presses SOS -> push to everyone else in the group.
exports.onSos = onDocumentUpdated('groups/{code}/members/{uid}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!lib.sosTurnedOn(before, after)) return;
  await notifyGroup(event.params.code, event.params.uid, 'sos', {
    name: after.name,
  });
});

// 2. A meeting point is set or changed -> push to everyone else.
exports.onMeeting = onDocumentUpdated('groups/{code}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!lib.meetingChanged(before, after)) return;
  await notifyGroup(event.params.code, after.meeting.byId, 'meeting', {
    name: after.meeting.by,
    label: after.meeting.label,
  });
});

// 3. Privacy: delete trips nobody has used for 7 days (locations included).
exports.cleanupOldTrips = onSchedule('every 24 hours', async () => {
  const now = Date.now();
  const groups = await db.collection('groups').get();
  for (const g of groups.docs) {
    const members = await g.ref.collection('members').get();
    const times = members.docs.map((m) => {
      const t = m.get('updatedAt');
      return t && t.toMillis ? t.toMillis() : null;
    });
    const created = g.get('createdAt');
    const latest = lib.lastActivityMs(
      times.filter((t) => t !== null),
      created && created.toMillis ? created.toMillis() : 0,
    );
    if (!lib.isStale(latest, now)) continue;
    const tokens = await g.ref.collection('tokens').get();
    const batch = db.batch();
    members.docs.forEach((m) => batch.delete(m.ref));
    tokens.docs.forEach((t) => batch.delete(t.ref));
    batch.delete(g.ref);
    await batch.commit();
    console.log(`Deleted inactive trip ${g.id}`);
  }
});
