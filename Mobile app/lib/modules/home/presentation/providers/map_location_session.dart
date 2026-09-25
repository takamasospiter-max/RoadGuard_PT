import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/location_service.dart';

/// An explicit, visible-screen location session. Never feeds reporting eligibility
/// or telemetry. Moving positions are valid on a map, unlike manual reporting.
class MapLocationSession extends ChangeNotifier {
  MapLocationSession(this._service, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LocationService _service;
  final DateTime Function() _now;
  StreamSubscription<GpsFix>? _subscription;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  bool active = false;
  bool requesting = false;
  GpsFix? fix;
  String? error;
  String message = 'Tap My location to use GPS while viewing this map.';

  Future<void> start() async {
    if (_disposed || active) return;
    final generation = ++_generation;
    active = requesting = true;
    error = null;
    fix = null;
    message = 'Requesting location access…';
    notifyListeners();
    try {
      await _service.requestAccess();
      if (_disposed || generation != _generation) return;
      requesting = false;
      final startedAt = _now();
      message = 'Waiting for a fresh GPS location…';
      _subscription = _service.watch().listen(
        (position) {
          if (_disposed || generation != _generation) return;
          if (!_usable(position, startedAt)) {
            fix = null;
            message = 'Waiting for a fresh, valid device location…';
          } else {
            fix = position;
            message =
                'Location accuracy: ±${position.accuracyMeters.ceil()} m. '
                'GPS is on while this map is visible.';
          }
          notifyListeners();
        },
        onError: (Object failure) {
          if (_disposed || generation != _generation) return;
          _fail(failure);
        },
        onDone: () {
          if (_disposed || generation != _generation) return;
          stop(message: 'Location updates ended. Tap My location to retry.');
        },
      );
      _expiry = Timer.periodic(const Duration(seconds: 1), (_) {
        if (fix != null && !_usable(fix!, startedAt)) {
          fix = null;
          message = 'Location is out of date. Waiting for a new GPS fix…';
          notifyListeners();
        }
      });
      notifyListeners();
    } catch (failure) {
      if (!_disposed && generation == _generation) _fail(failure);
    }
  }

  bool _usable(GpsFix position, DateTime startedAt) {
    final age = _now().difference(position.observedAt);
    return !position.isMocked &&
        position.latitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.isFinite &&
        position.longitude.abs() <= 180 &&
        position.accuracyMeters.isFinite &&
        position.accuracyMeters > 0 &&
        position.accuracyMeters <= 5000 &&
        !position.observedAt.isBefore(startedAt) &&
        !age.isNegative &&
        age <= const Duration(seconds: 10);
  }

  void _fail(Object failure) {
    stop(
      message: 'Your location is unavailable. You can still browse the map.',
    );
    error = failure is StateError
        ? failure.message.toString()
        : 'Could not read location. Check device location and app permissions.';
    notifyListeners();
  }

  void stop({
    String message = 'Location paused. Tap My location to reconnect.',
  }) {
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _expiry?.cancel();
    _expiry = null;
    active = requesting = false;
    fix = null;
    this.message = message;
    if (!_disposed) notifyListeners();
  }

  Future<void> openSettings() async {
    stop();
    try {
      await _service.openSettings();
    } catch (failure) {
      if (!_disposed) _fail(failure);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
