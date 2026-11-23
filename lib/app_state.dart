import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    final raw = _prefs.getStringList('groups') ?? [];
    groups = raw
        .map((e) => Group.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfile(Profile p) async {
    profile = p;
    await _prefs.setString('name', p.name);
    await _prefs.setInt('color', p.colorIndex);
    notifyListeners();
  }

  Future<void> _persist() => _prefs.setStringList(
      'groups', groups.map((g) => jsonEncode(g.toJson())).toList());

  Future<Group> create(String name) async {
    final g = await repo.createGroup(name, profile!);
    groups.insert(0, g);
    await _persist();
    notifyListeners();
    return g;
  }

  Future<Group?> join(String code) async {
    final clean = code.trim().toUpperCase();
    final existing = groups.where((g) => g.code == clean);
    if (existing.isNotEmpty) return existing.first;
    final g = await repo.joinGroup(clean, profile!);
    if (g == null) return null;
    groups.insert(0, g);
    await _persist();
    notifyListeners();
    return g;
  }

  Future<void> leave(Group g) async {
    await repo.leave(g.code);
    groups.removeWhere((x) => x.code == g.code);
    await _persist();
    notifyListeners();
  }
}
