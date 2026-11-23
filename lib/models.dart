import 'package:latlong2/latlong.dart';

class Profile {
  Profile({required this.name, required this.colorIndex});
  final String name;
  final int colorIndex;
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
  });

  final String id;
  final String name;
  final int colorIndex;
  final LatLng? position;
  final DateTime updatedAt;
  final bool isMe;

  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  bool get isLive => DateTime.now().difference(updatedAt).inMinutes < 2;

  String get lastSeen {
    final d = DateTime.now().difference(updatedAt);
    if (d.inSeconds < 20) return 'Live now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
