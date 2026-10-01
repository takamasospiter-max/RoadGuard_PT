import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';
import '../support/sensors.dart';

// Sensor collection starts with the trip (after a one-time choice), and the
// traveller can always see that it is running.

class _Location implements LocationService {
  final fixes = StreamController<GpsFix>.broadcast();
  @override
  Future<void> requestAccess() async {}
  @override
  Stream<GpsFix> watch() => fixes.stream;
  @override
  Future<void> openSettings() async {}
}

const _route = RouteOption(
  id: 'autostart-route',
  origin: 'Mlimani City',
  destination: 'Posta',
  road: 'OSRM',
  kilometers: 12,
  minutes: 25,
  hazardIds: [],
  coordinates: [
    [39.22, -6.77],
    [39.28, -6.81],
  ],
);

// The signed-in test account (test/support/auth.dart).
const _account = 'test-traveler';

Future<(ProviderContainer, FakeMotion)> _openTrip(
  WidgetTester tester,
  AppSettings settings, {
  String path = TripPaths.active,
}) async {
  final location = _Location();
  final motion = FakeMotion();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(412, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await location.fixes.close();
  });
  final trip = TripRecord(id: 'trip', route: _route, startedAt: DateTime.now());
  final store = MemoryLocalStore();
  await store.saveTrip(trip);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(signedInAuthService()),
        localStoreProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore(settings)),
        initialSettingsProvider.overrideWithValue(settings),
        initialTripProvider.overrideWithValue(trip),
        locationServiceProvider.overrideWithValue(location),
        permissionServiceProvider.overrideWithValue(FakePermissions()),
        motionAdapterProvider.overrideWithValue(motion),
        mapTileProviderFactoryProvider.overrideWithValue(
          testMapTileProviderFactory,
        ),
      ],
      child: const RoadGuardApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RoadGuardApp)),
  );
  container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return (container, motion);
}

void main() {
  const onboarded = AppSettings(onboardingComplete: true);

  testWidgets(
    '"every trip" travellers: collection starts by itself and says so',
    (tester) async {
      final (_, motion) = await _openTrip(
        tester,
        onboarded.withSensorSharing(
          _account,
          everyTrip: true,
          noticeVersion: collectionNoticeVersion,
        ),
      );
      expect(motion.started, isTrue);
      expect(find.text('Sensor collection started'), findsOneWidget);
      // No fix yet: the chip says it is waiting for GPS, not that data flows.
      expect(find.text('Waiting for GPS…'), findsOneWidget);
      expect(find.text('Share road sensor data?'), findsNothing); // no dialog
    },
  );

  testWidgets(
    'first trip asks once; "Share on every trip" starts and is saved',
    (tester) async {
      final (container, motion) = await _openTrip(tester, onboarded);
      expect(find.text('Share road sensor data?'), findsOneWidget);
      await tester.tap(find.text('Share on every trip'));
      await tester.pumpAndSettle();
      expect(motion.started, isTrue);
      expect(find.text('Sensor collection started'), findsOneWidget);
      expect(
        container
            .read(settingsProvider)
            .sensorSharingFor(_account, collectionNoticeVersion),
        SensorSharingChoice.everyTrip,
      );
    },
  );

  testWidgets(
    '"Not now": no collection, remembered, and the chip shows it is off',
    (tester) async {
      final (container, motion) = await _openTrip(tester, onboarded);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(motion.started, isFalse);
      expect(find.text('Sensor collection started'), findsNothing);
      expect(find.text('Sensor sharing off'), findsOneWidget);
      expect(
        container
            .read(settingsProvider)
            .sensorSharingFor(_account, collectionNoticeVersion),
        SensorSharingChoice.declined,
      );
    },
  );

  testWidgets('travellers who said "Not now" are not asked again', (
    tester,
  ) async {
    final (_, motion) = await _openTrip(
      tester,
      onboarded.withSensorSharing(
        _account,
        everyTrip: false,
        noticeVersion: collectionNoticeVersion,
      ),
    );
    expect(find.text('Share road sensor data?'), findsNothing);
    expect(motion.started, isFalse);
  });

  // Profile: change the standing answer later.
  SensorSharingChoice choiceIn(ProviderContainer container) => container
      .read(settingsProvider)
      .sensorSharingFor(_account, collectionNoticeVersion);
  final everyTripSwitch = find.byKey(const Key('profile-sensor-every-trip'));
  // Profile builds its list lazily: scroll until the switch exists, then
  // bring it fully into view (not under the bottom navigation bar).
  Future<void> showSwitch(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      everyTripSwitch,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(everyTripSwitch);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Profile: turning on shows the notice first, and only "Agree" saves it',
    (tester) async {
      final (container, _) = await _openTrip(
        tester,
        onboarded,
        path: ProfilePaths.profile,
      );
      await showSwitch(tester);
      await tester.tap(everyTripSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Share road sensor data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(choiceIn(container), SensorSharingChoice.ask); // nothing saved

      await tester.tap(everyTripSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree'));
      await tester.pumpAndSettle();
      expect(choiceIn(container), SensorSharingChoice.everyTrip);
    },
  );

  testWidgets('Profile: turning off takes effect at once', (tester) async {
    final (container, _) = await _openTrip(
      tester,
      onboarded.withSensorSharing(
        _account,
        everyTrip: true,
        noticeVersion: collectionNoticeVersion,
      ),
      path: ProfilePaths.profile,
    );
    await showSwitch(tester);
    await tester.tap(everyTripSwitch);
    await tester.pumpAndSettle();
    expect(find.text('Share road sensor data?'), findsNothing);
    expect(choiceIn(container), SensorSharingChoice.declined);
  });
}
