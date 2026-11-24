import 'package:latlong2/latlong.dart';

class Profile {
  Profile({required this.name, required this.colorIndex, this.emoji});
  final String name;
  final int colorIndex;
  final String? emoji;
}

class Group {
  Group({required this.code, required this.name});
  final String code;
  final String name;

  Map<String, dynamic> toJson() => {'code': code, 'name': name};
  factory Group.fromJson(Map<String, dynamic> j) =>
      Group(code: j['code'] as String, name: j['name'] as String);
}

class Member {
  Member({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.position,
    required this.updatedAt,
    this.isMe = false,
    this.sos = false,
    this.status,
    this.statusAt,
    this.emoji,
  });

  final String id;
  final String name;
  final int colorIndex;
  final LatLng? position;
  final DateTime updatedAt;
  final bool isMe;
  final bool sos;
  final String? status;
  final String? emoji;
  final DateTime? statusAt;

  /// A quick message ("Running late") stays visible for 30 minutes.
  String? get activeStatus {
    final s = status;
    final at = statusAt;
    if (s == null || s.isEmpty || at == null) return null;
    return DateTime.now().difference(at).inMinutes < 30 ? s : null;
  }

  String get initial =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  bool get isLive => DateTime.now().difference(updatedAt).inMinutes < 3;

  String get lastSeen {
    final d = DateTime.now().difference(updatedAt);
    if (d.inSeconds < 20) return 'Live now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class Meeting {
  Meeting({required this.position, required this.label, required this.by});
  final LatLng position;
  final String label;
  final String by;

  Map<String, dynamic> toMap() => {
    'lat': position.latitude,
    'lng': position.longitude,
    'label': label,
    'by': by,
  };

  static Meeting? fromMap(Object? m) {
    if (m is! Map) return null;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return Meeting(
      position: LatLng(lat, lng),
      label: (m['label'] as String?) ?? 'Meeting point',
      by: (m['by'] as String?) ?? '',
    );
  }
}

/// Live, shared settings of a group.
class GroupInfo {
  const GroupInfo({
    this.ownerId,
    this.locked = false,
    this.meeting,
    this.ended = false,
  });
  final String? ownerId;
  final bool locked;
  final Meeting? meeting;
  final bool ended;
}

class JoinException implements Exception {
  JoinException(this.message);
  final String message;
  @override
  String toString() => message;
}
