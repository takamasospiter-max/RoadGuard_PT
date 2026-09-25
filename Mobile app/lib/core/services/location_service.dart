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
  Stream<GpsFix> watch() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).map(
        (position) => GpsFix(
          latitude: position.latitude,
          longitude: position.longitude,
          // Negative/invalid native speeds remain invalid. Never coerce to stationary.
          speedMps: position.speed,
          accuracyMeters: position.accuracy,
          observedAt: position.timestamp,
          isMocked: position.isMocked,
        ),
      );
  @override
  Future<void> openSettings() async {
    await _permissions.openAppSettings();
  }
}
