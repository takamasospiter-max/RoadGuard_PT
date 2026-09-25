import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/models/safety_policy.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/modules/home/presentation/providers/map_location_session.dart';

class _Location implements LocationService {
  _Location() {
    positions = StreamController<GpsFix>.broadcast(
      sync: true,
      onListen: () => listeners++,
      onCancel: () => cancellations++,
    );
  }

  late final StreamController<GpsFix> positions;
  Future<void>? permissionResult;
  Object? permissionError;
  Object? watchError;
  int requests = 0;
  int watches = 0;
  int listeners = 0;
  int cancellations = 0;
  int settingsOpened = 0;

  @override
  Future<void> requestAccess() async {
    requests++;
    if (permissionResult case final Future<void> result) await result;
    if (permissionError case final Object error) throw error;
  }

  @override
  Stream<GpsFix> watch() {
    watches++;
    if (watchError case final Object error) throw error;
    return positions.stream;
  }

  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }
}

class _SessionFixture {
  _SessionFixture() {
    session = MapLocationSession(service, now: () => now);
  }

  final service = _Location();
  DateTime now = DateTime.utc(2026, 9, 21, 10);
  late final MapLocationSession session;
  bool _disposed = false;

  GpsFix position({
    double latitude = -6.7924,
    double longitude = 39.2083,
    double accuracy = 8,
    double speed = 0,
    DateTime? observedAt,
    bool mocked = false,
  }) => GpsFix(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracy,
    speedMps: speed,
    observedAt: observedAt ?? now,
    isMocked: mocked,
  );

  void disposeSession() {
    if (_disposed) return;
    _disposed = true;
    session.dispose();
  }

  Future<void> close() async {
    disposeSession();
    await service.positions.close();
  }
}

Future<void> _withSession(
  WidgetTester tester,
  Future<void> Function(_SessionFixture fixture) body,
) async {
  final fixture = _SessionFixture();
  try {
    await body(fixture);
  } finally {
    await fixture.close();
    await tester.pump();
  }
}

void main() {
  testWidgets('map location stays idle until explicitly requested', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      await tester.pump(const Duration(seconds: 30));
      expect(fixture.service.requests, 0);
      expect(fixture.service.watches, 0);
      expect(fixture.session.active, isFalse);
      expect(fixture.session.requesting, isFalse);
      expect(fixture.session.fix, isNull);

      final permission = Completer<void>();
      fixture.service.permissionResult = permission.future;
      final pending = fixture.session.start();
      expect(fixture.session.active, isTrue);
      expect(fixture.session.requesting, isTrue);
      expect(fixture.service.requests, 1);
      expect(fixture.service.watches, 0);
      await fixture.session.start();
      expect(fixture.service.requests, 1);

      permission.complete();
      await pending;
      expect(fixture.session.requesting, isFalse);
      expect(fixture.service.watches, 1);
      expect(fixture.service.listeners, 1);
      expect(fixture.session.fix, isNull);
    });
  });

  testWidgets('denied permission never opens a GPS stream and can be retried', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      fixture.service.permissionError = StateError('Location was not allowed.');
      await fixture.session.start();
      expect(fixture.service.watches, 0);
      expect(fixture.session.active, isFalse);
      expect(fixture.session.requesting, isFalse);
      expect(fixture.session.fix, isNull);
      expect(fixture.session.error, 'Location was not allowed.');

      fixture.service.permissionError = null;
      await fixture.session.start();
      fixture.service.positions.add(fixture.position());
      expect(fixture.service.requests, 2);
      expect(fixture.service.watches, 1);
      expect(fixture.session.active, isTrue);
      expect(fixture.session.fix, isNotNull);
      expect(fixture.session.error, isNull);
    });
  });

  testWidgets(
    'moving GPS positions display on the map but cannot allow reports',
    (tester) async {
      await _withSession(tester, (fixture) async {
        await fixture.session.start();
        final moving = fixture.position(speed: 12);
        fixture.service.positions.add(moving);
        expect(fixture.session.fix, same(moving));
        expect(fixture.session.active, isTrue);
        expect(
          const SafetyPolicy().evaluate(moving, fixture.now),
          ReportingGate.moving,
        );

        final approximate = fixture.position(accuracy: 1000);
        fixture.service.positions.add(approximate);
        expect(fixture.session.fix, same(approximate));
        expect(
          const SafetyPolicy().evaluate(approximate, fixture.now),
          ReportingGate.inaccurate,
        );
      });
    },
  );

  final invalidPositions = <String, GpsFix Function(_SessionFixture)>{
    'a cached fix from before this session': (fixture) => fixture.position(
      observedAt: fixture.now.subtract(const Duration(milliseconds: 1)),
    ),
    'a future timestamp': (fixture) => fixture.position(
      observedAt: fixture.now.add(const Duration(milliseconds: 1)),
    ),
    'a mocked position': (fixture) => fixture.position(mocked: true),
    'a NaN latitude': (fixture) => fixture.position(latitude: double.nan),
    'an out-of-range latitude': (fixture) => fixture.position(latitude: 91),
    'an infinite longitude': (fixture) =>
        fixture.position(longitude: double.infinity),
    'an out-of-range longitude': (fixture) => fixture.position(longitude: -181),
    'an unknown accuracy': (fixture) => fixture.position(accuracy: double.nan),
    'zero accuracy': (fixture) => fixture.position(accuracy: 0),
    'negative accuracy': (fixture) => fixture.position(accuracy: -1),
    'an excessively inaccurate position': (fixture) =>
        fixture.position(accuracy: 5001),
  };
  for (final entry in invalidPositions.entries) {
    testWidgets('${entry.key} removes an existing location marker', (
      tester,
    ) async {
      await _withSession(tester, (fixture) async {
        await fixture.session.start();
        fixture.service.positions.add(fixture.position());
        expect(fixture.session.fix, isNotNull);
        fixture.service.positions.add(entry.value(fixture));
        expect(fixture.session.fix, isNull);
        expect(fixture.session.active, isTrue);
        expect(fixture.session.error, isNull);
      });
    });
  }

  testWidgets('old GPS events stay hidden and a newer valid event recovers', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      await fixture.session.start();
      final old = fixture.position();
      fixture.now = fixture.now.add(const Duration(seconds: 11));
      fixture.service.positions.add(old);
      expect(fixture.session.fix, isNull);

      final fresh = fixture.position();
      fixture.service.positions.add(fresh);
      expect(fixture.session.fix, same(fresh));
      expect(fixture.session.active, isTrue);
    });
  });

  testWidgets('a marker expires even when no newer GPS events arrive', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      await fixture.session.start();
      final fix = fixture.position();
      fixture.service.positions.add(fix);
      fixture.now = fixture.now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(fixture.session.fix, same(fix));

      fixture.now = fixture.now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.session.fix, isNull);
      expect(fixture.session.active, isTrue);
      expect(fixture.session.message, contains('out of date'));

      fixture.service.positions.add(fixture.position());
      expect(fixture.session.fix, isNotNull);
    });
  });

  testWidgets(
    'stop cancels location and expiry without accepting more events',
    (tester) async {
      await _withSession(tester, (fixture) async {
        var notifications = 0;
        fixture.session.addListener(() => notifications++);
        await fixture.session.start();
        fixture.service.positions.add(fixture.position());
        fixture.session.stop();
        expect(fixture.service.cancellations, 1);
        expect(fixture.service.positions.hasListener, isFalse);
        expect(fixture.session.active, isFalse);
        expect(fixture.session.requesting, isFalse);
        expect(fixture.session.fix, isNull);
        final stoppedNotifications = notifications;

        fixture.now = fixture.now.add(const Duration(minutes: 1));
        fixture.service.positions.add(fixture.position());
        await tester.pump(const Duration(minutes: 1));
        expect(fixture.session.fix, isNull);
        expect(notifications, stoppedNotifications);
      });
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'permission completing after ${dispose ? 'dispose' : 'stop'} cannot restart GPS',
      (tester) async {
        await _withSession(tester, (fixture) async {
          final permission = Completer<void>();
          fixture.service.permissionResult = permission.future;
          final pending = fixture.session.start();
          expect(fixture.session.requesting, isTrue);
          if (dispose) {
            fixture.disposeSession();
          } else {
            fixture.session.stop();
          }
          permission.complete();
          await pending;
          await tester.pump();
          expect(fixture.service.watches, 0);
          expect(fixture.session.active, isFalse);
          expect(fixture.session.requesting, isFalse);
          expect(fixture.session.fix, isNull);
        });
      },
    );
  }

  testWidgets('an earlier permission response cannot replace a newer session', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      final permission = Completer<void>();
      fixture.service.permissionResult = permission.future;
      final earlier = fixture.session.start();
      fixture.session.stop();
      fixture.service.permissionResult = null;
      await fixture.session.start();
      final currentFix = fixture.position();
      fixture.service.positions.add(currentFix);
      permission.complete();
      await earlier;

      expect(fixture.service.requests, 2);
      expect(fixture.service.watches, 1);
      expect(fixture.service.listeners, 1);
      expect(fixture.session.active, isTrue);
      expect(fixture.session.fix, same(currentFix));
    });
  });

  testWidgets('stream errors clear the marker and cancel GPS', (tester) async {
    await _withSession(tester, (fixture) async {
      await fixture.session.start();
      fixture.service.positions.add(fixture.position());
      fixture.service.positions.addError(
        StateError('Location services are off.'),
      );
      expect(fixture.session.fix, isNull);
      expect(fixture.session.active, isFalse);
      expect(fixture.session.requesting, isFalse);
      expect(fixture.session.error, 'Location services are off.');
      expect(fixture.service.cancellations, 1);
      expect(fixture.service.positions.hasListener, isFalse);
      await tester.pump(const Duration(seconds: 20));
      expect(fixture.session.fix, isNull);
    });
  });

  testWidgets('stream setup errors produce a recoverable unavailable state', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      fixture.service.watchError = Exception('Native stream failed.');
      await fixture.session.start();
      expect(fixture.service.watches, 1);
      expect(fixture.service.listeners, 0);
      expect(fixture.session.active, isFalse);
      expect(fixture.session.requesting, isFalse);
      expect(fixture.session.fix, isNull);
      expect(fixture.session.error, contains('Check device location'));
    });
  });

  testWidgets('a completed stream removes the marker and offers retry', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      await fixture.session.start();
      fixture.service.positions.add(fixture.position());
      await fixture.service.positions.close();
      expect(fixture.session.active, isFalse);
      expect(fixture.session.fix, isNull);
      expect(fixture.session.error, isNull);
      expect(fixture.session.message, contains('Tap My location to retry'));
      await tester.pump(const Duration(seconds: 20));
      expect(fixture.session.fix, isNull);
    });
  });

  testWidgets('opening device settings first cancels the visible-map session', (
    tester,
  ) async {
    await _withSession(tester, (fixture) async {
      await fixture.session.start();
      fixture.service.positions.add(fixture.position());
      await fixture.session.openSettings();
      expect(fixture.service.settingsOpened, 1);
      expect(fixture.service.cancellations, 1);
      expect(fixture.session.active, isFalse);
      expect(fixture.session.fix, isNull);
    });
  });
}
