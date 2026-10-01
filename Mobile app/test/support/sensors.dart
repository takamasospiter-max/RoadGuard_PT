import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/services/permission_service.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';

/// Device permissions as on a phone where the driver allowed motion sensors.
class FakePermissions implements PermissionService {
  @override
  Future<PermissionState> requestMotion() async => PermissionState.granted;
  @override
  Future<SensorState> checkMotionSensors() async => SensorState.available;
  @override
  Future<PermissionSnapshot> snapshot() async => const PermissionSnapshot(
    location: PermissionState.granted,
    locationServicesEnabled: true,
    camera: PermissionState.granted,
    motion: PermissionState.granted,
  );
  @override
  Future<PermissionState> requestLocation() async => PermissionState.granted;
  @override
  Future<PermissionState> requestCamera() async => PermissionState.granted;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

/// Motion sensors that report nothing until a test calls [event].
class FakeMotion extends ForegroundMotionAdapter {
  void Function(Map<String, Object?>)? event;
  bool started = false;
  @override
  Future<void> start({
    required bool registered,
    required bool consent,
    required bool activeTrip,
    required bool foreground,
    required void Function(Map<String, Object?>) onEvent,
    required void Function(Object) onError,
  }) async {
    // Sensors may only start for a signed-in, consenting traveller on an
    // active trip with the app in front.
    expect([registered, consent, activeTrip, foreground], everyElement(isTrue));
    started = true;
    event = onEvent;
  }

  @override
  Future<void> stop() async {
    started = false;
  }
}
