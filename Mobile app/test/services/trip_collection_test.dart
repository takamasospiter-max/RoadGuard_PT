import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';
import 'package:roadguard_ai/core/services/trip_collection.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

import '../support/auth.dart';
import '../support/sensors.dart';

class FakeAuth extends AuthService {
  FakeAuth()
    : super(
        baseUrl: 'https://roadguard.example.test',
        storage: MemorySessionStorage(),
      );
  bool fail = false;
  int uploads = 0, grants = 0;
  // Batch ids the server refuses for good (e.g. their consent has ended).
  final refused = <String>{};
  // Simulates a server-side fault (not the batch's fault).
  bool internalError = false;
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
    final input = variables['input'] as Map;
    if (refused.contains(input['id'])) {
      throw const ServerRejection(
        'Collection consent is missing, expired or withdrawn.',
        code: 'BAD_USER_INPUT',
      );
    }
    if (internalError) {
      throw const ServerRejection(
        'The request could not be completed.',
        code: 'INTERNAL_ERROR',
      );
    }
    uploads++;
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
  // A batch the server can never accept (its consent ended, e.g. recorded
  // before switching servers) used to stay first in the queue and pause
  // every later upload for good.
  Future<void> queueBatch(String id) => store.enqueueTelemetry(
    OutboxRecord(
      id: id,
      payload: jsonEncode({
        'ownerId': 'owner',
        'origin': auth.baseUrl,
        'consentId': 'old-consent',
        'tripId': 'trip',
        'events': <Object?>[],
      }),
    ),
  );

  test('a batch the server refuses for good is removed and does not block the rest', () async {
    await queueBatch('old');
    await queueBatch('new');
    auth.refused.add('old');
    await collection.flush();
    expect(await store.telemetryCount(), 0); // old dropped, new delivered
    expect(auth.uploads, 1);
    expect(collection.message, contains('1 batch'));
  });

  test('when the current consent is refused, recording stops', () async {
    await collection.start(); // grants the consent "consent"
    emit();
    await collection.stop();
    await collection.start();
    final batch = (await store.pendingTelemetry()).single;
    auth.refused.add(batch.id);
    await collection.flush();
    expect(collection.running, isFalse);
    expect(collection.message, startsWith('Sharing stopped'));
    expect(await store.telemetryCount(), 0);
  });

  test('a server fault keeps every batch for a later attempt', () async {
    await queueBatch('a');
    await queueBatch('b');
    auth.internalError = true;
    await collection.flush();
    expect(await store.telemetryCount(), 2);
    expect(collection.message, startsWith('Upload paused'));
  });

  // What the trip screen's status chip shows, without parsing messages.
  test(
    'status follows the collection: off, waiting for GPS, collecting, paused',
    () async {
      expect(collection.status, SensorStatus.off);
      await collection.start();
      expect(collection.status, SensorStatus.waitingForGps);
      emit();
      expect(collection.status, SensorStatus.collecting);
      auth.fail = true;
      await collection.flush();
      expect(collection.status, SensorStatus.uploadPaused);
      auth.fail = false;
      await collection.flush();
      expect(collection.status, SensorStatus.collecting);
      await collection.stop();
      expect(collection.status, SensorStatus.off);
    },
  );

  // The phone keeps at most 500 unsent batches. When full, collection must
  // pause (not stop): stopping also ended uploading, so a full store never
  // drained and every new trip stopped two seconds after starting.
  test('a full local store keeps uploading, then resumes recording', () async {
    for (var i = 0; i < 500; i++) {
      await store.enqueueTelemetry(
        OutboxRecord(
          id: 'backlog-$i',
          payload: jsonEncode({
            'ownerId': 'owner',
            'origin': auth.baseUrl,
            'consentId': 'consent',
            'tripId': 'trip',
            'events': <Object?>[],
          }),
        ),
      );
    }
    await collection.start();
    emit(); // 20 readings: no room for them yet
    await collection.flush();
    expect(collection.running, isTrue); // paused, not stopped
    expect(await store.telemetryCount(), 0); // the backlog was sent
    expect(auth.uploads, 500);
    emit(); // room again: recording resumes
    await collection.flush();
    expect(auth.uploads, 501);
    expect(collection.status, SensorStatus.collecting);
  });

  test(
    'while the store is full, the status says saved data is being sent',
    () async {
      for (var i = 0; i < 500; i++) {
        await store.enqueueTelemetry(
          OutboxRecord(
            id: 'other-$i',
            payload: jsonEncode({'ownerId': 'someone-else'}),
          ),
        );
      }
      await collection.start();
      emit();
      await collection.flush(); // nothing of ours to send: still full
      expect(collection.running, isTrue);
      expect(collection.status, SensorStatus.storeFull);
    },
  );

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
