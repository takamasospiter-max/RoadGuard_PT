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
/// What sensor collection is doing right now, for the trip screen's status
/// chip (so the UI doesn't have to interpret [TripCollection.message]).
enum SensorStatus {
  off,
  starting,

  /// Running, but no fresh accurate GPS fix: nothing is being queued.
  waitingForGps,

  /// Running and queuing readings.
  collecting,

  /// Running, but the last upload failed; batches wait on the phone.
  uploadPaused,

  /// Running, but the phone already holds the maximum of unsent batches:
  /// new readings are skipped while saved ones are sent, then recording
  /// resumes by itself.
  storeFull,
}

/// Most unsent batches the phone keeps (SRS: 500-record buffer; also
/// enforced by LocalStore.enqueueTelemetry).
const maxPendingBatches = 500;

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
  bool _uploadPaused = false;
  bool _storeFull = false;

  SensorStatus get status {
    if (busy) return SensorStatus.starting;
    if (!running) return SensorStatus.off;
    if (_uploadPaused) return SensorStatus.uploadPaused;
    if (_storeFull) return SensorStatus.storeFull;
    return _validFix(_fix, DateTime.now())
        ? SensorStatus.collecting
        : SensorStatus.waitingForGps;
  }

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
      debugPrint('RoadGuard sensors: started (consent $consentId)');
      message = 'Waiting for a fresh, accurate GPS fix. No sensor data is queued yet.';
      _gps = location.watch().listen(
        (fix) {
          final before = status;
          _fix = fix;
          if (status != before) _notify(); // e.g. GPS became accurate
        },
        onError: (Object error) {
          unawaited(stop(reason: 'location stream error'));
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
          // A full store pauses recording (saved batches are sent first).
          if (_storeFull) return;
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
          unawaited(stop(reason: 'motion sensor error'));
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
    } catch (error) {
      debugPrint('RoadGuard sensors: start failed: $error');
      await stop(reason: 'start failed');
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
      // The phone holds the maximum of unsent batches. Existing records are
      // never overwritten; recording pauses while flush() keeps sending them
      // and resumes when there is room. (Stopping here also ended uploading,
      // so a full store could never drain.)
      if (!_storeFull) {
        debugPrint('RoadGuard sensors: local store full, recording paused');
      }
      _storeFull = true;
      message = 'Phone storage for sensor data is full. Sending saved data first; recording resumes when there is room.';
      _notify();
    });
  }

  Future<void> flush() async {
    if (_flushing || _closed) return;
    _flushing = true;
    final epoch = _epoch;
    var dropped = 0; // batches the server refused for good (see below)
    var consentEnded = false;
    try {
      await _writes;
      for (final row in await store.pendingTelemetry(limit: 500)) {
        if (_closed || epoch != _epoch) break;
        final value = jsonDecode(row.payload) as Map<String, dynamic>;
        // Never upload another account/server's queue using the current token.
        if (value['ownerId'] != ownerId || value['origin'] != auth.baseUrl) {
          continue;
        }
        final Map<String, dynamic> result;
        try {
          result = await auth.mobileGraphql(
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
        } on ServerRejection catch (error) {
          // A server problem: keep the batch and retry later.
          if (!error.permanent) rethrow;
          // The server will never accept this batch (e.g. its consent ended,
          // or it was recorded for another server). Keeping it would block
          // every later batch behind it, and without valid consent the data
          // must not be kept: remove it and carry on with the rest.
          await store.acknowledgeTelemetry(row.id);
          dropped++;
          if (value['consentId'] == consentId) {
            // The current consent itself is no longer valid: stop recording
            // rather than keep collecting batches that would be refused too.
            consentEnded = true;
            await stop(reason: 'server refused current consent');
            break;
          }
          continue;
        }
        final ack = result['uploadTelemetry'] as Map;
        if (ack['accepted'] != true ||
            (ack['id'] as String).replaceAll('-', '') !=
                row.id.replaceAll('-', '')) {
          throw const AuthFailure('Telemetry acknowledgement mismatch.');
        }
        await store.acknowledgeTelemetry(row.id);
        accepted++;
      }
      _uploadPaused = false; // every pending batch was handled
      if (_storeFull && await store.telemetryCount() < maxPendingBatches) {
        _storeFull = false; // room again: recording resumes
        debugPrint('RoadGuard sensors: room in local store, recording resumed');
      }
      final removed = dropped == 0
          ? ''
          : ' · $dropped batch${dropped == 1 ? '' : 'es'} the server could not accept removed';
      message = consentEnded
          ? 'Sharing stopped: the server no longer accepts this consent. Start sharing again.'
          : running
          ? (_validFix(_fix, DateTime.now())
                ? 'Sharing foreground sensor data · $accepted batches received$removed'
                : 'Waiting for accurate GPS; no new data queued.$removed')
          : 'Collection stopped · $accepted batches received$removed';
    } on AuthFailure catch (error) {
      if (error.status == 401 ||
          error.status == 403 ||
          error.message.contains('rejected')) {
        await stop(reason: 'signed out or session rejected');
      }
      _uploadPaused = true;
      message = 'Upload paused. Check your connection/session. Unacknowledged batches remain on this device.';
    } catch (_) {
      _uploadPaused = true;
      message =
          'Upload unavailable. Unacknowledged batches remain on this device.';
    } finally {
      _flushing = false;
      _notify();
    }
  }

  /// Stops collection. [reason] goes to the device log (logcat, tag
  /// "flutter", text "RoadGuard sensors"), to see why collection stopped.
  Future<void> stop({String reason = 'requested'}) async {
    if (running || busy) debugPrint('RoadGuard sensors: stopped ($reason)');
    ++_epoch;
    running = false;
    _uploadPaused = false;
    _storeFull = false;
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
      await stop(reason: 'consent withdrawn');
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
    unawaited(stop(reason: 'disposed'));
    super.dispose();
  }
}
