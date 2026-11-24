import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
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
  bool straggler = true; // alert when someone is far from the group
  ThemeMode themeMode = ThemeMode.system;
  LocationStatus? locationStatus;
  StreamSubscription<LatLng>? _locSub;
  Timer? _heartbeat;
  Timer? _idleCheck;
  bool _active = true; // moving -> GPS; standing still -> low-power
  LatLng? _lastFix;
  DateTime _lastMove = DateTime.now();

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
      profile = Profile(
        name: name,
        colorIndex: _prefs.getInt('color') ?? 0,
        emoji: _prefs.getString('emoji'),
      );
    }
    sharing = _prefs.getBool('sharing') ?? true;
    straggler = _prefs.getBool('straggler') ?? true;
    themeMode = switch (_prefs.getString('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
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
    if (p.emoji == null) {
      await _prefs.remove('emoji');
    } else {
      await _prefs.setString('emoji', p.emoji!);
    }
    notifyListeners();
    for (final g in groups) {
      repo.updateIdentity(g.code, p).catchError((_) {});
    }
    unawaited(startTracking());
  }

  Future<void> _persist() => _prefs.setStringList(
    'groups',
    groups.map((g) => jsonEncode(g.toJson())).toList(),
  );

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
    try {
      locationStatus = await LocationService.ensurePermission();
    } catch (_) {
      locationStatus = LocationStatus.serviceOff;
    }
    notifyListeners();
    if (locationStatus != LocationStatus.ok) return;
    LocationService.askNotifications();
    final first = await LocationService.current();
    if (first != null) _onPosition(first);
    if (!sharing) return; // paused: no foreground service, no notification
    _active = true;
    _lastMove = DateTime.now();
    _listen();
    _idleCheck = Timer.periodic(const Duration(seconds: 60), (_) {
      // Standing still for 4+ minutes -> switch to low-power location.
      if (_active && DateTime.now().difference(_lastMove).inMinutes >= 4) {
        _active = false;
        _listen();
      }
    });
  }

  void _listen() {
    _locSub?.cancel();
    _locSub = LocationService.stream(active: _active)
        .listen(_onPosition, onError: (_) {});
    // Re-send while stationary so friends still see you as "live"
    // (they count anyone updated in the last 3 minutes as live).
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(Duration(seconds: _active ? 90 : 150), (_) {
      final p = myPosition.value;
      if (p != null) _push(p);
    });
  }

  Future<void> stopTracking() async {
    await _locSub?.cancel();
    _locSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _idleCheck?.cancel();
    _idleCheck = null;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setString('theme', m.name);
    notifyListeners();
  }

  Future<void> setStraggler(bool v) async {
    straggler = v;
    await _prefs.setBool('straggler', v);
    notifyListeners();
  }

  Future<void> setSharing(bool v) async {
    sharing = v;
    await _prefs.setBool('sharing', v);
    notifyListeners();
    await stopTracking();
    await startTracking();
  }

  void _onPosition(LatLng p) {
    final last = _lastFix;
    if (last == null || const Distance().as(LengthUnit.Meter, last, p) > 25) {
      _lastFix = p;
      _lastMove = DateTime.now();
      if (!_active) {
        _active = true; // started moving again -> back to GPS
        _listen();
      }
    }
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
