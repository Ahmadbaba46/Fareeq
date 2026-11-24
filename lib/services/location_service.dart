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
  ///
  /// [active] = moving: GPS accuracy, 15 m filter. Idle (standing still for a
  /// while): balanced accuracy (Wi-Fi/cell), 40 m filter - much less battery.
  static Stream<LatLng> stream({bool active = true}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: active ? LocationAccuracy.high : LocationAccuracy.medium,
          distanceFilter: active ? 15 : 40,
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
