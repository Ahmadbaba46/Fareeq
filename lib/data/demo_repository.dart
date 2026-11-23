import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models.dart';
import 'repository.dart';

/// Works offline with zero configuration: simulated friends wander around
/// the user so the whole UI can be tried without any backend.
class DemoRepository implements Repository {
  final _rand = Random();
  final Map<String, LatLng> _myPos = {};
  final Map<String, List<_Bot>> _bots = {};

  static const _fallback = LatLng(41.0082, 28.9784); // Istanbul

  @override
  bool get isDemo => true;
  @override
  String get userId => 'me';
  @override
  Future<void> init() async {}

  @override
  Future<Group> createGroup(String name, Profile me) async =>
      Group(code: generateCode(), name: name);

  @override
  Future<Group?> joinGroup(String code, Profile me) async =>
      Group(code: code.toUpperCase(), name: 'Trip $code');

  @override
  Future<void> leave(String code) async {
    _myPos.remove(code);
    _bots.remove(code);
  }

  @override
  Future<void> updateLocation(String code, Profile me, LatLng pos) async {
    _myPos[code] = pos;
  }

  List<_Bot> _botsFor(String code) => _bots.putIfAbsent(
      code,
      () => [
            _Bot('Amina', 3, _rand),
            _Bot('Yusuf', 1, _rand),
            _Bot('Khadija', 4, _rand),
            _Bot('Ibrahim', 5, _rand),
          ]);

  @override
  Stream<List<Member>> members(String code) async* {
    final bots = _botsFor(code);
    while (true) {
      final origin = _myPos[code] ?? _fallback;
      final now = DateTime.now();
      for (final b in bots) {
        b.step(origin, _rand);
      }
      yield [
        Member(
          id: 'me',
          name: 'You',
          colorIndex: 0,
          position: origin,
          updatedAt: now,
          isMe: true,
        ),
        for (final b in bots)
          Member(
            id: b.name,
            name: b.name,
            colorIndex: b.color,
            position: b.pos,
            updatedAt: b.stale ? now.subtract(const Duration(minutes: 7)) : now,
          ),
      ];
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}

class _Bot {
  _Bot(this.name, this.color, Random r)
      : _dx = (r.nextDouble() - .5) * .012,
        _dy = (r.nextDouble() - .5) * .012;
  final String name;
  final int color;
  final double _dx, _dy;
  LatLng? pos;

  bool get stale => name == 'Ibrahim'; // stays put, shows "last seen"

  void step(LatLng origin, Random r) {
    final p = pos;
    if (p == null) {
      pos = LatLng(origin.latitude + _dy, origin.longitude + _dx);
    } else if (!stale) {
      pos = LatLng(p.latitude + (r.nextDouble() - .45) * .0006,
          p.longitude + (r.nextDouble() - .45) * .0006);
    }
  }
}
