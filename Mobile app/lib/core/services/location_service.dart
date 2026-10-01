import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'permission_service.dart';

abstract interface class LocationService {
  Future<void> requestAccess();
  Stream<GpsFix> watch();
  Future<void> openSettings();
}

class DeviceLocationService implements LocationService {
  DeviceLocationService({PermissionService? permissions})
    : _permissions = permissions ?? const DevicePermissionService();

  final PermissionService _permissions;

  @override
  Future<void> requestAccess() async {
    switch (await _permissions.requestLocation()) {
      case PermissionState.granted:
        return;
      case PermissionState.permanentlyDenied:
        throw StateError(
          'Location is blocked. Open app settings to grant access.',
        );
      case PermissionState.restricted:
        throw StateError('Location access is restricted on this device.');
      case PermissionState.unavailable:
        throw StateError('Location is unavailable on this device.');
      case PermissionState.denied:
        throw StateError(
          'Location was not allowed. You can still browse the map.',
        );
      case PermissionState.unknown || PermissionState.requesting:
        throw StateError('Location permission could not be confirmed.');
    }
  }

  @override
  Stream<GpsFix> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    ),
  ).map((position) => fixFromPosition(position, receivedAt: DateTime.now()));
  @override
  Future<void> openSettings() async {
    await _permissions.openAppSettings();
  }
}

/// A GPS fix from a native position, timed on the phone's own clock.
///
/// [Position.timestamp] is satellite time, but everything the fix is compared
/// with is on the phone's clock: sensor readings (sensors_plus), "fresh within
/// 10 s" checks and the server's "GPS ≤ 10 s before the reading" rule. Phone
/// clocks commonly run a second or more off; mixing the two made every sensor
/// reading look older than the latest fix, so sensor sharing dropped them all.
/// Positions are delivered as soon as they are computed, so the moment one
/// arrives ([receivedAt]) is when it was observed, on the right clock.
GpsFix fixFromPosition(
  Position position, {
  required DateTime receivedAt,
}) => GpsFix(
  latitude: position.latitude,
  longitude: position.longitude,
  // Negative/invalid native speeds remain invalid. Never coerce to stationary.
  speedMps: position.speed,
  accuracyMeters: position.accuracy,
  observedAt: receivedAt,
  isMocked: position.isMocked,
);
