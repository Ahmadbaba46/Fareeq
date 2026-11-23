import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/demo_repository.dart';
import 'data/firebase_repository.dart';
import 'data/repository.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  late Repository repo;
  late SharedPreferences _prefs;
  Profile? profile;
  List<Group> groups = [];

  /// My latest position, shared with every joined group while [sharing].
  final myPosition = ValueNotifier<LatLng?>(null);
  bool sharing = true;
  LocationStatus? locationStatus;
  StreamSubscription<LatLng>? _locSub;
  Timer? _heartbeat;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final fb = FirebaseRepository();
      await fb.init();
      repo = fb;
    } catch (_) {
      repo = DemoRepository(); // Firebase not configured yet -> demo mode
      await repo.init();
    }
    final name = _prefs.getString('name');
    if (name != null) {
      profile = Profile(name: name, colorIndex: _prefs.getInt('color') ?? 0);
    }
    sharing = _prefs.getBool('sharing') ?? true;
    final raw = _prefs.getStringList('groups') ?? [];
    groups = raw
        .map((e) => Group.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    if (profile != null) unawaited(startTracking());
  }

  Future<void> saveProfile(Profile p) async {
    profile = p;
    await _prefs.setString('name', p.name);
    await _prefs.setInt('color', p.colorIndex);
    notifyListeners();
    unawaited(startTracking());
  }

  Future<void> _persist() => _prefs.setStringList(
      'groups', groups.map((g) => jsonEncode(g.toJson())).toList());

  Future<Group> create(String name) async {
    final g = await repo.createGroup(name, profile!);
    groups.insert(0, g);
    await _persist();
    notifyListeners();
    final pos = myPosition.value;
    if (pos != null) _push(pos);
    return g;
  }

  Future<Group> join(String code) async {
    final clean = parseCode(code);
    final existing = groups.where((g) => g.code == clean);
    if (existing.isNotEmpty) return existing.first;
    final g = await repo.joinGroup(clean, profile!);
    groups.insert(0, g);
    await _persist();
    notifyListeners();
    final pos = myPosition.value;
    if (pos != null) _push(pos);
    return g;
  }

  /// Drop a group locally (e.g. the owner ended the trip).
  Future<void> forget(Group g) async {
    groups.removeWhere((x) => x.code == g.code);
    await _persist();
    notifyListeners();
  }

  Future<void> leave(Group g) async {
    try {
      await repo.leave(g.code);
    } catch (_) {}
    groups.removeWhere((x) => x.code == g.code);
    await _persist();
    notifyListeners();
  }

  // ---- background-capable location tracking ----

  Future<void> startTracking() async {
    if (_locSub != null || profile == null) return;
    locationStatus = await LocationService.ensurePermission();
    notifyListeners();
    if (locationStatus != LocationStatus.ok) return;
    LocationService.askNotifications();
    final first = await LocationService.current();
    if (first != null) _onPosition(first);
    if (!sharing) return; // paused: no foreground service, no notification
    _locSub = LocationService.stream().listen(_onPosition, onError: (_) {});
    // Re-send while stationary so friends still see you as "live".
    _heartbeat = Timer.periodic(const Duration(seconds: 90), (_) {
      final p = myPosition.value;
      if (p != null) _push(p);
    });
  }

  Future<void> stopTracking() async {
    await _locSub?.cancel();
    _locSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> setSharing(bool v) async {
    sharing = v;
    await _prefs.setBool('sharing', v);
    notifyListeners();
    await stopTracking();
    await startTracking();
  }

  void _onPosition(LatLng p) {
    myPosition.value = p;
    _push(p);
  }

  void _push(LatLng p) {
    if (!sharing || profile == null) return;
    for (final g in groups) {
      repo.updateLocation(g.code, profile!, p).catchError((_) {});
    }
  }
}
