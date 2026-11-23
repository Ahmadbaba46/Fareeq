import 'package:latlong2/latlong.dart';
import '../models.dart';

/// Backend contract. Two implementations: [DemoRepository] (no setup at all)
/// and [FirebaseRepository] (free Spark plan, no billing).
abstract class Repository {
  bool get isDemo;
  String get userId;
  Future<void> init();
  Future<Group> createGroup(String name, Profile me);
  Future<Group?> joinGroup(String code, Profile me);
  Stream<List<Member>> members(String code);
  Future<void> updateLocation(String code, Profile me, LatLng pos);
  Future<void> leave(String code);
}

String generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = DateTime.now().microsecondsSinceEpoch;
  var n = r;
  final b = StringBuffer();
  for (var i = 0; i < 6; i++) {
    n = (n * 1103515245 + 12345) & 0x7fffffff;
    b.write(chars[n % chars.length]);
  }
  return b.toString();
}
