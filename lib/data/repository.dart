import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';

/// Backend contract. Two implementations: [DemoRepository] (no setup at all)
/// and [FirebaseRepository] (free Spark plan, no billing).
abstract class Repository {
  bool get isDemo;
  String get userId;

  /// True while the backend cannot be reached (data is from local cache).
  ValueNotifier<bool> get offline;
  Future<void> init();
  Future<Group> createGroup(String name, Profile me);

  /// Throws [JoinException] if the group does not exist or is locked.
  Future<Group> joinGroup(String code, Profile me);
  Stream<List<Member>> members(String code);
  Stream<GroupInfo> groupInfo(String code);
  Future<void> updateLocation(String code, Profile me, LatLng pos);
  Future<void> setSos(String code, Profile me, bool on);
  Future<void> setStatus(String code, Profile me, String? status);
  Future<void> setMeeting(String code, Meeting? meeting);
  Future<void> setLocked(String code, bool locked);

  /// Owner only: removes every member and the group itself.
  Future<void> endTrip(String code);
  Future<void> leave(String code);
}

String generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Accepts a raw code or a scanned QR payload (`fareeq://join/CODE`).
String parseCode(String input) {
  final t = input.trim();
  final i = t.lastIndexOf('/');
  return (i >= 0 ? t.substring(i + 1) : t).toUpperCase();
}
