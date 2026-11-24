'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const lib = require('../lib');

test('sos message names the sender and uses the alert channel', () => {
  const m = lib.buildMessage('sos', { name: 'Amina' });
  assert.equal(m.title, 'SOS from Amina');
  assert.equal(m.channelId, 'sos_alerts');
});

test('meeting message includes who and where, truncated', () => {
  const m = lib.buildMessage('meeting', { name: 'Yusuf', label: 'Hotel lobby, 6pm' });
  assert.equal(m.body, 'Yusuf set: Hotel lobby, 6pm');
  const long = lib.buildMessage('meeting', { name: 'Y', label: 'x'.repeat(200) });
  assert.ok(long.body.length < 90);
});

test('unknown kind yields no message', () => {
  assert.equal(lib.buildMessage('nope', {}), null);
});

test('sosTurnedOn only on false -> true', () => {
  assert.equal(lib.sosTurnedOn({ sos: false }, { sos: true }), true);
  assert.equal(lib.sosTurnedOn(undefined, { sos: true }), true);
  assert.equal(lib.sosTurnedOn({ sos: true }, { sos: true }), false);
  assert.equal(lib.sosTurnedOn({ sos: true }, { sos: false }), false);
  assert.equal(lib.sosTurnedOn({ sos: false }, undefined), false);
});

test('meetingChanged ignores clears and unchanged points', () => {
  const m = { lat: 1, lng: 2, label: 'A' };
  assert.equal(lib.meetingChanged({}, { meeting: m }), true);
  assert.equal(lib.meetingChanged({ meeting: m }, { meeting: { ...m, label: 'B' } }), true);
  assert.equal(lib.meetingChanged({ meeting: m }, { meeting: m }), false);
  assert.equal(lib.meetingChanged({ meeting: m }, { meeting: null }), false);
  assert.equal(lib.meetingChanged({}, {}), false);
});

test('recipientTokens skips the sender, blanks and duplicates', () => {
  const docs = [
    { uid: 'a', token: 't1' },
    { uid: 'b', token: 't2' },
    { uid: 'c', token: 't2' },
    { uid: 'd', token: '' },
    { uid: 'me', token: 't3' },
  ];
  assert.deepEqual(lib.recipientTokens(docs, 'me'), [
    { uid: 'a', token: 't1' },
    { uid: 'b', token: 't2' },
  ]);
});

test('stale trips are detected after 7 days', () => {
  const day = 24 * 60 * 60 * 1000;
  const now = 100 * day;
  assert.equal(lib.isStale(now - 6 * day, now), false);
  assert.equal(lib.isStale(now - 8 * day, now), true);
  assert.equal(lib.lastActivityMs([1, 50, 20], 10), 50);
  assert.equal(lib.lastActivityMs([], 10), 10);
});

test('dead token errors recognised', () => {
  assert.equal(lib.isDeadTokenError('messaging/registration-token-not-registered'), true);
  assert.equal(lib.isDeadTokenError('messaging/internal-error'), false);
});
