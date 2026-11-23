import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationStatus { ok, denied, deniedForever, serviceOff }

class LocationService {
  static Future<LocationStatus> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationStatus.serviceOff;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      return LocationStatus.deniedForever;
    }
    if (p == LocationPermission.denied) return LocationStatus.denied;
    return LocationStatus.ok;
  }

  /// Moves of 15 m or more are emitted - keeps Firestore writes (and battery)
  /// low enough for the free tier.
  static Stream<LatLng> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).map((p) => LatLng(p.latitude, p.longitude));

  static Future<LatLng?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition();
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}
