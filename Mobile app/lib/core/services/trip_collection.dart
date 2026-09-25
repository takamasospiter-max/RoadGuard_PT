import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../storage/local_store.dart';
import 'auth_service.dart';
import 'location_service.dart';
import 'permission_service.dart';
import 'telemetry_service.dart';

/// One explicit foreground collection session. A new start always needs consent.
class TripCollection extends ChangeNotifier {
  TripCollection({
    required this.auth,
    required this.store,
    required this.location,
    required this.permissions,
    required this.motion,
    required this.ownerId,
    required this.tripId,
  });
  final AuthService auth;
  final LocalStore store;
  final LocationService location;
  final PermissionService permissions;
  final ForegroundMotionAdapter motion;
  final String ownerId, tripId;
  StreamSubscription<GpsFix>? _gps;
  Timer? _timer;
  GpsFix? _fix;
  String? consentId;
  bool running = false, busy = false, _closed = false, _flushing = false;
  int _epoch = 0, accepted = 0;
  String message = 'Sensor collection is off.';
  Future<void> _writes = Future.value();
  final List<Map<String, Object?>> _events = [];
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() async {
    if (busy || running) return;
    final epoch = ++_epoch;
    busy = true;
    _notify();
    try {
      await location.requestAccess();
      if (epoch != _epoch || _closed) return;
      final motionAccess = await permissions.requestMotion();
      if (motionAccess != PermissionState.granted) {
        throw StateError(
          'Motion sensor access was not granted or sensors are unavailable.',
        );
      }
      final sensors = await permissions.checkMotionSensors();
      if (sensors != SensorState.available) {
        throw StateError(
          'Accelerometer or gyroscope is unavailable on this device.',
        );
      }
      if (epoch != _epoch || _closed) return;
      final result = await auth.mobileGraphql(
        r'''mutation Consent($trip:ID!,$version:Int!) {
        grantCollectionConsent(tripId:$trip,version:$version,accepted:true) { id }
      }''',
        {'trip': tripId, 'version': collectionNoticeVersion},
      );
      if (epoch != _epoch || _closed) return;
      consentId = (result['grantCollectionConsent'] as Map)['id'] as String;
      running = true;
      message = 'Waiting for a fresh, accurate GPS fix. No sensor data is queued yet.';
      _gps = location.watch().listen(
        (fix) {
          _fix = fix;
        },
        onError: (Object error) {
          unawaited(stop());
          message = 'Location unavailable. Collection stopped.';
          _notify();
        },
      );
      await motion.start(
        registered: true,
        consent: true,
        activeTrip: true,
        foreground: true,
        onEvent: (event) {
          if (!running ||
              epoch != _epoch ||
              !_validFix(
                _fix,
                DateTime.tryParse(event['at'] as String? ?? '') ??
                    DateTime.now(),
              )) {
            return;
          }
          _events.add({...event, 'gps': _fix!.toJson()});
          if (_events.length >= 20) _queue();
        },
        onError: (error) {
          unawaited(stop());
          message = 'Motion sensor unavailable. Collection stopped.';
          _notify();
        },
      );
      if (epoch != _epoch || _closed) {
        await motion.stop();
        return;
      }
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!running) return;
        _queue();
        unawaited(flush());
      });
    } catch (_) {
      await stop();
      message = 'Could not start collection. Check sign-in, consent, location and motion access.';
    } finally {
      busy = false;
      _notify();
    }
  }

  bool _validFix(GpsFix? fix, DateTime at) =>
      fix != null &&
      !fix.isMocked &&
      fix.latitude.isFinite &&
      fix.longitude.isFinite &&
      fix.latitude.abs() <= 90 &&
      fix.longitude.abs() <= 180 &&
      fix.speedMps.isFinite &&
      fix.speedMps >= 0 &&
      fix.speedMps <= 100 &&
      fix.accuracyMeters.isFinite &&
      fix.accuracyMeters > 0 &&
      fix.accuracyMeters <= 25 &&
      !at.isBefore(fix.observedAt) &&
      at.difference(fix.observedAt) <= const Duration(seconds: 10) &&
      DateTime.now().difference(at) <= const Duration(seconds: 10) &&
      !at.isAfter(DateTime.now());

  void _queue() {
    if (_events.isEmpty || consentId == null) return;
    final events = List<Map<String, Object?>>.from(_events);
    _events.clear();
    final record = OutboxRecord(
      id: newLocalId(),
      payload: jsonEncode({
        'ownerId': ownerId,
        'origin': auth.baseUrl,
        'consentId': consentId,
        'tripId': tripId,
        'events': events,
        'schemaVersion': 1,
      }),
    );
    _writes = _writes.then((_) => store.enqueueTelemetry(record)).catchError((
      Object error,
    ) {
      // The existing queue is preserved. Stop instead of overwriting old evidence.
      unawaited(stop());
      message = 'Local buffer could not accept data. Collection stopped; existing records are preserved.';
      _notify();
    });
  }

  Future<void> flush() async {
    if (_flushing || _closed) return;
    _flushing = true;
    final epoch = _epoch;
    try {
      await _writes;
      for (final row in await store.pendingTelemetry(limit: 500)) {
        if (_closed || epoch != _epoch) break;
        final value = jsonDecode(row.payload) as Map<String, dynamic>;
        // Never upload another account/server's queue using the current token.
        if (value['ownerId'] != ownerId || value['origin'] != auth.baseUrl) {
          continue;
        }
        final result = await auth.mobileGraphql(
          r'''mutation Upload($input:TelemetryInput!) {
          uploadTelemetry(input:$input) { id accepted receivedAt }
        }''',
          {
            'input': {
              'id': row.id,
              'consentId': value['consentId'],
              'tripId': value['tripId'],
              'eventsJson': jsonEncode(value['events']),
            },
          },
        );
        final ack = result['uploadTelemetry'] as Map;
        if (ack['accepted'] != true ||
            (ack['id'] as String).replaceAll('-', '') !=
                row.id.replaceAll('-', '')) {
          throw const AuthFailure('Telemetry acknowledgement mismatch.');
        }
        await store.acknowledgeTelemetry(row.id);
        accepted++;
      }
      message = running
          ? (_validFix(_fix, DateTime.now())
                ? 'Sharing foreground sensor data · $accepted batches received'
                : 'Waiting for accurate GPS; no new data queued.')
          : 'Collection stopped · $accepted batches received';
    } on AuthFailure catch (error) {
      if (error.status == 401 ||
          error.status == 403 ||
          error.message.contains('rejected')) {
        await stop();
      }
      message = 'Upload paused. Check your connection/session. Unacknowledged batches remain on this device.';
    } catch (_) {
      message =
          'Upload unavailable. Unacknowledged batches remain on this device.';
    } finally {
      _flushing = false;
      _notify();
    }
  }

  Future<void> stop() async {
    ++_epoch;
    running = false;
    _timer?.cancel();
    _timer = null;
    final gps = _gps;
    _gps = null;
    _fix = null;
    _queue();
    await gps?.cancel();
    await motion.stop();
    message = 'Collection stopped. Start again explicitly to record more.';
    _notify();
  }

  Future<void> withdraw() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      await stop();
      await _writes;
      // Revoke before removing local data. A failed request never claims success.
      await auth.mobileGraphql(
        'mutation Withdraw { revokeMyCollectionConsents }',
        {},
      );
      for (final row in await store.pendingTelemetry(limit: 500)) {
        final value = jsonDecode(row.payload) as Map;
        if (value['ownerId'] == ownerId && value['origin'] == auth.baseUrl) {
          await store.acknowledgeTelemetry(row.id);
        }
      }
      consentId = null;
      message = 'All sensor consent withdrawn for this account. Its pending local batches were removed; received data is not erased.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(stop());
    super.dispose();
  }
}
