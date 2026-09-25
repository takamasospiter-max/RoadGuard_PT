import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

enum PermissionState {
  unknown,
  requesting,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unavailable,
}

enum SensorState { initializing, available, active, unavailable, error }

class PermissionSnapshot {
  const PermissionSnapshot({
    required this.location,
    required this.locationServicesEnabled,
    required this.camera,
    required this.motion,
  });

  final PermissionState location;
  final bool locationServicesEnabled;
  final PermissionState camera;
  final PermissionState motion;
}

/// Owns platform permission checks and requests so screens consume real state.
abstract interface class PermissionService {
  Future<PermissionSnapshot> snapshot();
  Future<PermissionState> requestLocation();
  Future<PermissionState> requestCamera();
  Future<PermissionState> requestMotion();
  Future<SensorState> checkMotionSensors();
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

class DevicePermissionService implements PermissionService {
  const DevicePermissionService();
  static const MethodChannel _capabilityChannel = MethodChannel(
    'roadguard/device_sensors',
  );

  @override
  Future<PermissionSnapshot> snapshot() async {
    final locationEnabled =
        !kIsWeb && await Geolocator.isLocationServiceEnabled();
    final location = await _locationStatus();
    final camera = kIsWeb || !(Platform.isAndroid || Platform.isIOS)
        ? PermissionState.unavailable
        : await _cameraStatus();
    final motion = await _motionStatus();
    return PermissionSnapshot(
      location: location,
      locationServicesEnabled: locationEnabled,
      camera: camera,
      motion: motion,
    );
  }

  Future<PermissionState> _locationStatus() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return PermissionState.unavailable;
    }
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always ||
      LocationPermission.whileInUse => PermissionState.granted,
      LocationPermission.deniedForever => PermissionState.permanentlyDenied,
      LocationPermission.denied => _map(
        await ph.Permission.locationWhenInUse.status,
      ),
      LocationPermission.unableToDetermine => PermissionState.unknown,
    };
  }

  @override
  Future<PermissionState> requestLocation() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return PermissionState.unavailable;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Location services are off. Enable GPS in device settings.',
      );
    }
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    return switch (status) {
      LocationPermission.always ||
      LocationPermission.whileInUse => PermissionState.granted,
      LocationPermission.deniedForever => PermissionState.permanentlyDenied,
      LocationPermission.denied => PermissionState.denied,
      LocationPermission.unableToDetermine => PermissionState.unknown,
    };
  }

  @override
  Future<PermissionState> requestCamera() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return PermissionState.unavailable;
    }
    if (await _cameraAvailable() != true) return PermissionState.unavailable;
    return _map(await ph.Permission.camera.request());
  }

  @override
  Future<PermissionState> requestMotion() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return PermissionState.unavailable;
    }
    // Accelerometer and gyroscope do not require a runtime Android permission.
    // iOS requires the Motion & Fitness permission exposed by sensors_plus.
    if (Platform.isIOS) return _map(await ph.Permission.sensors.request());
    return (await checkMotionSensors()) == SensorState.available
        ? PermissionState.granted
        : PermissionState.unavailable;
  }

  Future<PermissionState> _motionStatus() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return PermissionState.unavailable;
    }
    if (Platform.isIOS) return _map(await ph.Permission.sensors.status);
    return switch (await checkMotionSensors()) {
      SensorState.available || SensorState.active => PermissionState.granted,
      SensorState.unavailable => PermissionState.unavailable,
      SensorState.initializing || SensorState.error => PermissionState.unknown,
    };
  }

  Future<PermissionState> _cameraStatus() async {
    final available = await _cameraAvailable();
    if (available == null) return PermissionState.unknown;
    if (!available) return PermissionState.unavailable;
    return _map(await ph.Permission.camera.status);
  }

  Future<bool?> _cameraAvailable() async {
    try {
      final capabilities = await _capabilityChannel
          .invokeMapMethod<String, bool>('deviceCapabilities');
      return capabilities?['camera'];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SensorState> checkMotionSensors() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return SensorState.unavailable;
    }
    try {
      final capabilities = await _capabilityChannel
          .invokeMapMethod<String, bool>('deviceCapabilities');
      if (capabilities == null) return SensorState.error;
      return capabilities['accelerometer'] == true &&
              capabilities['gyroscope'] == true
          ? SensorState.available
          : SensorState.unavailable;
    } catch (_) {
      return SensorState.error;
    }
  }

  @override
  Future<void> openAppSettings() async {
    if (!await ph.openAppSettings()) {
      throw StateError(
        'Open RoadGuard AI in your device settings to change access.',
      );
    }
  }

  @override
  Future<void> openLocationSettings() async {
    if (!await Geolocator.openLocationSettings()) {
      await openAppSettings();
    }
  }

  PermissionState _map(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return PermissionState.granted;
    }
    if (status.isPermanentlyDenied) return PermissionState.permanentlyDenied;
    if (status.isRestricted) return PermissionState.restricted;
    if (status.isDenied) return PermissionState.denied;
    return PermissionState.unknown;
  }
}
