import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import 'repository.dart';

/// Values come from `--dart-define` at build time (see README / CI workflow).
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: senderId,
  );
}

/// Firestore + anonymous auth. Both are available on Firebase's free Spark
/// plan (no credit card). Do NOT add Cloud Functions - they need Blaze.
///
/// Data model:
///   groups/{code}               { name, createdAt }
///   groups/{code}/members/{uid} { name, color, lat, lng, updatedAt }
class FirebaseRepository implements Repository {
  late final FirebaseFirestore _db;
  late final String _uid;

  @override
  bool get isDemo => false;
  @override
  String get userId => _uid;
  @override
  final offline = ValueNotifier<bool>(false);

  @override
  Future<void> init() async {
    if (!FirebaseConfig.isConfigured)
      throw StateError('Firebase not configured');
    await Firebase.initializeApp(options: FirebaseConfig.options);
    final cred = FirebaseAuth.instance.currentUser != null
        ? FirebaseAuth.instance.currentUser!
        : (await FirebaseAuth.instance.signInAnonymously()).user!;
    _uid = cred.uid;
    _db = FirebaseFirestore.instance;
  }

  DocumentReference<Map<String, dynamic>> _group(String code) =>
      _db.collection('groups').doc(code);
  CollectionReference<Map<String, dynamic>> _members(String code) =>
      _group(code).collection('members');

  Map<String, dynamic> _identity(Profile me) => {
    'name': me.name,
    'color': me.colorIndex,
    'emoji': me.emoji,
    'photoUrl': me.photoUrl,
  };

  @override
  Future<Group> createGroup(String name, Profile me) async {
    for (var i = 0; i < 5; i++) {
      final code = generateCode();
      final ref = _group(code);
      if ((await ref.get()).exists) continue;
      await ref.set({
        'name': name,
        'ownerId': _uid,
        'locked': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _members(code)
          .doc(_uid)
          .set({..._identity(me), 'updatedAt': FieldValue.serverTimestamp()});
      return Group(code: code, name: name);
    }
    throw Exception('Could not allocate a group code, try again');
  }

  @override
  Future<Group> joinGroup(String code, Profile me) async {
    final id = code.toUpperCase();
    final snap = await _group(id).get();
    if (!snap.exists) throw JoinException('No group found with that code.');
    final data = snap.data()!;
    final already = (await _members(id).doc(_uid).get()).exists;
    if (data['locked'] == true && !already) {
      throw JoinException('This group is locked by its creator.');
    }
    await _members(id).doc(_uid).set({
      ..._identity(me),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return Group(code: snap.id, name: (data['name'] as String?) ?? id);
  }

  @override
  Future<GroupSummary?> summary(String code) async {
    final g = await _group(code).get();
    if (!g.exists) return null;
    final ms = await _members(code).get();
    final now = DateTime.now();
    final live = ms.docs.where((d) {
      final t = (d.data()['updatedAt'] as Timestamp?)?.toDate();
      return t != null && now.difference(t).inMinutes < 3;
    }).length;
    return GroupSummary(
      people: ms.size,
      live: live,
      locked: g.data()?['locked'] == true,
    );
  }

  @override
  Future<void> leave(String code) async {
    await _group(code)
        .collection('tokens')
        .doc(_uid)
        .delete()
        .catchError((_) {});
    await _members(code).doc(_uid).delete();
  }

  @override
  Future<void> saveToken(String code, String token) =>
      _group(code)
          .collection('tokens')
          .doc(_uid)
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});

  Reference get _avatarRef => FirebaseStorage.instance.ref('avatars/$_uid.jpg');

  @override
  Future<String?> uploadAvatar(Uint8List jpeg) async {
    await _avatarRef.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
    final url = await _avatarRef.getDownloadURL();
    // changes on every upload so cached copies are refreshed
    return '$url&t=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> deleteAvatar() async {
    try {
      await _avatarRef.delete();
    } catch (_) {}
  }

  @override
  Future<void> updateLocation(String code, Profile me, LatLng pos) =>
      _members(code).doc(_uid).set({
        ..._identity(me),
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> updateIdentity(String code, Profile me) =>
      _members(code).doc(_uid).set(_identity(me), SetOptions(merge: true));

  @override
  Future<void> setSos(String code, Profile me, bool on) => _members(code)
      .doc(_uid)
      .set({
        ..._identity(me),
        'sos': on,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> setStatus(String code, Profile me, String? status) =>
      _members(code).doc(_uid).set({
        ..._identity(me),
        'status': status,
        'statusAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> setMeeting(String code, Meeting? meeting) =>
      _group(code).update({'meeting': meeting?.toMap()});

  @override
  Future<void> setLocked(String code, bool locked) =>
      _group(code).update({'locked': locked});

  @override
  Future<void> endTrip(String code) async {
    final batch = _db.batch();
    for (final d in (await _members(code).get()).docs) {
      batch.delete(d.reference);
    }
    batch.delete(_group(code));
    await batch.commit();
  }

  @override
  Stream<GroupInfo> groupInfo(String code) => _group(code).snapshots().map((s) {
    if (!s.exists) return const GroupInfo(ended: true);
    final d = s.data()!;
    return GroupInfo(
      ownerId: d['ownerId'] as String?,
      locked: d['locked'] == true,
      meeting: Meeting.fromMap(d['meeting']),
    );
  });

  @override
  Stream<List<Member>> members(String code) => _members(code)
      .snapshots(includeMetadataChanges: true)
      .map((s) {
        offline.value = s.metadata.isFromCache && s.docs.isNotEmpty;
        return s.docs.map((d) {
          final m = d.data();
          final lat = (m['lat'] as num?)?.toDouble();
          final lng = (m['lng'] as num?)?.toDouble();
          return Member(
            id: d.id,
            name: (m['name'] as String?) ?? '?',
            colorIndex: (m['color'] as int?) ?? 0,
            position: lat == null || lng == null ? null : LatLng(lat, lng),
            updatedAt:
                (m['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            isMe: d.id == _uid,
            sos: m['sos'] == true,
            emoji: m['emoji'] as String?,
            photoUrl: m['photoUrl'] as String?,
            status: m['status'] as String?,
            statusAt: (m['statusAt'] as Timestamp?)?.toDate(),
          );
        }).toList();
      });
}
