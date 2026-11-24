'use strict';

/** Notification text for each kind of group event. Pure, so it is unit-tested. */
function buildMessage(kind, { name, label } = {}) {
  const who = (name || 'Someone').toString().slice(0, 40);
  switch (kind) {
    case 'sos':
      return {
        title: `SOS from ${who}`,
        body: 'Needs help. Open Fareeq to see exactly where they are.',
        channelId: 'sos_alerts',
      };
    case 'meeting': {
      const where = (label || 'a meeting point').toString().slice(0, 60);
      return {
        title: 'New meeting point',
        body: `${who} set: ${where}`,
        channelId: 'sos_alerts',
      };
    }
    default:
      return null;
  }
}

/** Did this member just turn SOS on? */
function sosTurnedOn(before, after) {
  return Boolean(after && after.sos === true && !(before && before.sos === true));
}

/** Did the meeting point just change to something new (not cleared)? */
function meetingChanged(before, after) {
  const a = after && after.meeting;
  if (!a) return false;
  const b = before && before.meeting;
  return !b || b.lat !== a.lat || b.lng !== a.lng || b.label !== a.label;
}

/** Tokens to notify: everyone except the sender, de-duplicated. */
function recipientTokens(tokenDocs, senderUid) {
  const seen = new Set();
  const out = [];
  for (const d of tokenDocs) {
    if (!d || d.uid === senderUid || !d.token || seen.has(d.token)) continue;
    seen.add(d.token);
    out.push({ uid: d.uid, token: d.token });
  }
  return out;
}

/** Latest activity time (ms) of a group, from its members; falls back to creation. */
function lastActivityMs(memberUpdatedAts, createdAtMs) {
  let latest = createdAtMs || 0;
  for (const t of memberUpdatedAts) {
    if (typeof t === 'number' && t > latest) latest = t;
  }
  return latest;
}

const STALE_DAYS = 7;
function isStale(latestMs, nowMs, days = STALE_DAYS) {
  return nowMs - latestMs > days * 24 * 60 * 60 * 1000;
}

/** FCM error codes meaning the token is dead and should be deleted. */
function isDeadTokenError(code) {
  return (
    code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-registration-token'
  );
}

module.exports = {
  buildMessage,
  sosTurnedOn,
  meetingChanged,
  recipientTokens,
  lastActivityMs,
  isStale,
  isDeadTokenError,
  STALE_DAYS,
};
