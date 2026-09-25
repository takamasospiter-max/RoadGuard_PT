import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/permission_service.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';
import 'package:roadguard_ai/core/services/trip_collection.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

import '../support/auth.dart';

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

class FakeAuth extends AuthService {
  FakeAuth()
    : super(
        baseUrl: 'https://roadguard.example.test',
        storage: MemorySessionStorage(),
      );
  bool fail = false;
  int uploads = 0, grants = 0;
  @override
  Future<Map<String, dynamic>> mobileGraphql(
    String document,
    Map<String, Object?> variables,
  ) async {
    if (document.contains('grantCollection')) {
      // The app must accept the notice version the backend currently requires.
      expect(variables['version'], collectionNoticeVersion);
      grants++;
      return {
        'grantCollectionConsent': {'id': 'consent'},
      };
    }
    if (document.contains('revokeMyCollection')) {
      return {
        'revokeCollectionConsent': {'revoked': true},
      };
    }
    if (fail) throw const AuthFailure('Offline');
    uploads++;
    final input = variables['input'] as Map;
    return {
      'uploadTelemetry': {'id': input['id'], 'accepted': true},
    };
  }
}

class FakeLocation implements LocationService {
  final stream = StreamController<GpsFix>.broadcast(sync: true);
  Completer<void>? permission;
  @override
  Future<void> requestAccess() async {
    await permission?.future;
  }

  @override
  Stream<GpsFix> watch() => stream.stream;
  @override
  Future<void> openSettings() async {}
}

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
    expect([registered, consent, activeTrip, foreground], everyElement(isTrue));
    started = true;
    event = onEvent;
  }

  @override
  Future<void> stop() async {
    started = false;
  }
}

void main() {
  late FakeAuth auth;
  late FakeLocation location;
  late FakeMotion motion;
  late MemoryLocalStore store;
  late TripCollection collection;
  setUp(() {
    auth = FakeAuth();
    location = FakeLocation();
    motion = FakeMotion();
    store = MemoryLocalStore();
    collection = TripCollection(
      auth: auth,
      store: store,
      location: location,
      permissions: FakePermissions(),
      motion: motion,
      ownerId: 'owner',
      tripId: 'trip',
    );
  });
  tearDown(() async {
    collection.dispose();
    auth.dispose();
    await location.stream.close();
  });
  void emit({bool mocked = false, bool stale = false}) {
    final now = DateTime.now();
    location.stream.add(
      GpsFix(
        latitude: -6.8,
        longitude: 39.25,
        speedMps: 4,
        accuracyMeters: 5,
        observedAt: stale ? now.subtract(const Duration(minutes: 1)) : now,
        isMocked: mocked,
      ),
    );
    for (var i = 0; i < 20; i++) {
      motion.event?.call({
        'kind': 'acceleration',
        'at': DateTime.now().toUtc().toIso8601String(),
        'x': .1,
        'y': .2,
        'z': .3,
      });
    }
  }

  test(
    'no implicit collection; stop during permission prevents late activation',
    () async {
      expect(motion.started, isFalse);
      expect(auth.grants, 0);
      location.permission = Completer();
      final starting = collection.start();
      await collection.stop();
      location.permission!.complete();
      await starting;
      expect(motion.started, isFalse);
      expect(auth.grants, 0);
      expect(collection.running, isFalse);
    },
  );
  test('only valid GPS events queue; failed upload preserves and successful ACK removes', () async {
    await collection.start();
    emit(mocked: true);
    emit(stale: true);
    await collection.flush();
    expect(await store.telemetryCount(), 0);
    emit();
    auth.fail = true;
    await collection.stop();
    await collection.flush();
    expect(await store.telemetryCount(), 1);
    final row = (await store.pendingTelemetry()).single;
    final data = jsonDecode(row.payload) as Map;
    expect(data['ownerId'], 'owner');
    expect((data['events'] as List).length, 20);
    auth.fail = false;
    await collection.flush();
    expect(await store.telemetryCount(), 0);
    expect(auth.uploads, 1);
    expect(motion.started, isFalse);
  });
  test('queue never crosses account/server boundaries', () async {
    for (final owner in ['other', 'owner']) {
      await store.enqueueTelemetry(
        OutboxRecord(
          id: owner,
          payload: jsonEncode({
            'ownerId': owner,
            'origin': owner == 'owner' ? 'https://other.test' : auth.baseUrl,
            'events': <Object?>[],
          }),
        ),
      );
    }
    await collection.flush();
    expect(auth.uploads, 0);
    expect(await store.telemetryCount(), 2);
  });
  test(
    'withdrawal stops sensors and removes this account pending data',
    () async {
      await collection.start();
      emit();
      await collection.stop();
      await collection.withdraw();
      expect(motion.started, isFalse);
      expect(collection.consentId, isNull);
      expect(await store.telemetryCount(), 0);
      expect(auth.uploads, 0);
    },
  );
}
