import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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

  /// Android 13+ needs this for the "sharing" notification to be visible.
  static Future<void> askNotifications() async {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  /// Runs as an Android foreground service (persistent notification) so
  /// updates continue when the app is in the background or screen is off.
  /// Only moves of 15 m or more are emitted - keeps Firestore writes and
  /// battery low enough for the free tier.
  static Stream<LatLng> stream() => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Fareeq is sharing your location',
        notificationText: 'Your travel group can see where you are.',
        notificationChannelName: 'Location sharing',
        enableWakeLock: true,
        setOngoing: true,
      ),
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
