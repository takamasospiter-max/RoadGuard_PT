import 'dart:async';
import 'dart:convert';

import 'package:sensors_plus/sensors_plus.dart';

import '../models/models.dart';
import '../models/safety_policy.dart';
import '../storage/local_store.dart';

/// Version of the sensor-sharing notice the driver agrees to (shown in the
/// trip screen's consent dialog and sent with the consent). Must match
/// NOTICE_VERSION in the backend (new-backend/telemetry/services.py).
/// Version 2 (2026-09-25): the raw accelerometer, gravity included, replaced
/// the gravity-removed one, so drivers accept the new wording once.
const collectionNoticeVersion = 2;

/// The sensor-sharing notice the traveller agrees to (version
/// collectionNoticeVersion, which the backend checks).
const collectionNoticeText =
    "While a trip screen is open, share GPS coordinates, speed, accuracy, timestamps, acceleration including gravity (m/s²) and angular velocity (rad/s) with RoadGuard, linked to your account. Raw observations help develop road analysis; they are not verified hazards. Up to 500 batches of 20 observations may be buffered on this device. Collection stops when you leave the trip screen, pause, sign out or background the app, and starts again when you return. With \"Share on every trip\", it starts automatically with each trip; you can stop it on any trip, and turn it off in Profile. Each trip's consent lasts at most 24 hours. Use Withdraw all sensor consent to revoke this account’s sessions on every device and remove its pending batches on this device; already received data is not erased. Notice version $collectionNoticeVersion.";

/// Native foreground raw-stream adapter, not DSP or hazard detection.
/// Activated only by TripCollection after authenticated, explicit consent.
/// Background services, placement calibration and measured device rates remain open.
class ForegroundMotionAdapter {
  StreamSubscription<AccelerometerEvent>? _acceleration;
  StreamSubscription<GyroscopeEvent>? _rotation;
  bool get running => _acceleration != null || _rotation != null;
  Future<void> start({
    required bool registered,
    required bool consent,
    required bool activeTrip,
    required bool foreground,
    required void Function(Map<String, Object?>) onEvent,
    required void Function(Object) onError,
  }) async {
    if (!telemetryEligible(
      registered: registered,
      consent: consent,
      activeTrip: activeTrip,
      foreground: foreground,
    )) {
      throw StateError(
        'Telemetry requires an authenticated traveler, explicit consent and an active foreground trip.',
      );
    }
    await stop();
    const interval = Duration(
      milliseconds: 100,
    ); // Request 10 Hz, not a measured guarantee.
    // Raw accelerometer (m/s², gravity included), not the gravity-removed
    // "user" accelerometer: the AI model was trained on raw readings, and
    // gravity also tells the backend how the phone is held (it turns each
    // window to the training orientation). Kind "acceleration" = notice v2.
    _acceleration = accelerometerEventStream(samplingPeriod: interval).listen(
      (event) {
        onEvent({
          'kind': 'acceleration',
          'at': event.timestamp.toUtc().toIso8601String(),
          'x': event.x,
          'y': event.y,
          'z': event.z,
        });
      },
      onError: (Object error) {
        unawaited(stop());
        onError(error);
      },
    );
    _rotation = gyroscopeEventStream(samplingPeriod: interval).listen(
      (event) {
        onEvent({
          'kind': 'angular_velocity',
          'at': event.timestamp.toUtc().toIso8601String(),
          'x': event.x,
          'y': event.y,
          'z': event.z,
        });
      },
      onError: (Object error) {
        unawaited(stop());
        onError(error);
      },
    );
  }

  Future<void> stop() async {
    final acceleration = _acceleration;
    final rotation = _rotation;
    _acceleration = null;
    _rotation = null;
    await acceleration?.cancel();
    await rotation?.cancel();
  }
}

/// Provisional record definition: a bounded batch, not an unbounded JSON payload.
/// NOT asserted to be the SRS's final definition of a "telemetry record".
OutboxRecord makeTelemetryChunk(
  String tripId,
  List<Map<String, Object?>> events,
) {
  if (events.isEmpty || events.length > 20) {
    throw ArgumentError('A chunk must contain 1–20 raw sensor events.');
  }
  final payload = jsonEncode({
    'tripId': tripId,
    'events': events,
    'schemaVersion': 1,
  });
  if (utf8.encode(payload).length > 32768) {
    throw ArgumentError('Telemetry chunk exceeds 32 KiB.');
  }
  return OutboxRecord(id: newLocalId(), payload: payload);
}

typedef OutboxSender = Future<bool> Function(OutboxRecord record);

/// Single-flight ordered flush. The server must honor record IDs idempotently.
/// No deletion until an explicit ACK. A thrown failure preserves the remaining queue.
class OutboxSync {
  OutboxSync(this.store);
  final LocalStore store;
  bool _running = false;
  Future<int> flush(OutboxSender send) async {
    if (_running) return 0;
    _running = true;
    var sent = 0;
    try {
      for (final record in await store.pendingTelemetry()) {
        if (!await send(record)) break;
        await store.acknowledgeTelemetry(record.id);
        sent++;
      }
      return sent;
    } finally {
      _running = false;
    }
  }
}
