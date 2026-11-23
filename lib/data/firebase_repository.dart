import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:latlong2/latlong.dart';
import '../models.dart';
import 'repository.dart';

/// Values come from `--dart-define` at build time (see README / CI workflow).
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

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
  Future<void> init() async {
    if (!FirebaseConfig.isConfigured) throw StateError('Firebase not configured');
    await Firebase.initializeApp(options: FirebaseConfig.options);
    final cred = FirebaseAuth.instance.currentUser != null
        ? FirebaseAuth.instance.currentUser!
        : (await FirebaseAuth.instance.signInAnonymously()).user!;
    _uid = cred.uid;
    _db = FirebaseFirestore.instance;
  }

  @override
  Future<Group> createGroup(String name, Profile me) async {
    for (var i = 0; i < 5; i++) {
      final code = generateCode();
      final ref = _db.collection('groups').doc(code);
      if ((await ref.get()).exists) continue;
      await ref.set({'name': name, 'createdAt': FieldValue.serverTimestamp()});
      return Group(code: code, name: name);
    }
    throw Exception('Could not allocate a group code, try again');
  }

  @override
  Future<Group?> joinGroup(String code, Profile me) async {
    final snap = await _db.collection('groups').doc(code.toUpperCase()).get();
    if (!snap.exists) return null;
    return Group(code: snap.id, name: (snap.data()?['name'] as String?) ?? code);
  }

  @override
  Future<void> leave(String code) =>
      _db.collection('groups').doc(code).collection('members').doc(_uid).delete();

  @override
  Future<void> updateLocation(String code, Profile me, LatLng pos) =>
      _db.collection('groups').doc(code).collection('members').doc(_uid).set({
        'name': me.name,
        'color': me.colorIndex,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<List<Member>> members(String code) => _db
      .collection('groups')
      .doc(code)
      .collection('members')
      .snapshots()
      .map((s) => s.docs.map((d) {
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
            );
          }).toList());
}
