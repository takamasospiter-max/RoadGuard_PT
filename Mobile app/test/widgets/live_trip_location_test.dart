import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

class _Location implements LocationService {
  final fixes = StreamController<GpsFix>.broadcast();
  Completer<void>? permission;
  bool denied = false;
  int watches = 0;
  @override
  Future<void> requestAccess() async {
    if (permission != null) await permission!.future;
    if (denied) throw StateError('Location permission denied.');
  }

  @override
  Stream<GpsFix> watch() {
    watches++;
    return fixes.stream;
  }

  @override
  Future<void> openSettings() async {}
}

const _route = RouteOption(
  id: 'live-location-test',
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
GpsFix _fix(double latitude, {bool stale = false, bool mocked = false}) =>
    GpsFix(
      latitude: latitude,
      longitude: 39.23,
      speedMps: 5,
      accuracyMeters: 8,
      observedAt: DateTime.now().subtract(Duration(seconds: stale ? 20 : 0)),
      isMocked: mocked,
    );

Future<ProviderContainer> _launch(
  WidgetTester tester,
  _Location location,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(412, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await location.fixes.close();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  // Already answered "Not now" to sensor sharing, so the one-time question
  // (test/widgets/sensor_autostart_test.dart) doesn't cover the trip screen.
  final settings = const AppSettings(onboardingComplete: true)
      .withSensorSharing(
        'test-traveler',
        everyTrip: false,
        noticeVersion: collectionNoticeVersion,
      );
  final trip = TripRecord(id: 'trip', route: _route, startedAt: DateTime.now());
  final store = MemoryLocalStore();
  await store.saveTrip(trip);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Sign-in is required after onboarding; start as a signed-in traveller.
        authServiceProvider.overrideWithValue(signedInAuthService()),
        localStoreProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore(settings)),
        initialSettingsProvider.overrideWithValue(settings),
        initialTripProvider.overrideWithValue(trip),
        locationServiceProvider.overrideWithValue(location),
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
  container.read(routerProvider).go(TripPaths.active);
  await tester.pumpAndSettle();
  return container;
}

MapCamera _camera(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  test('legacy coordinate labels stay stored but are readable in history', () {
    final legacy = RouteOption.fromJson({
      ..._route.toJson(),
      'origin': '-6.77000, 39.22000',
      'destination': '-6.81000, 39.28000',
    });
    expect(legacy.originLabel, 'Selected starting point');
    expect(legacy.destinationLabel, 'Selected destination');
    expect(legacy.toJson()['origin'], '-6.77000, 39.22000');
    expect(_route.originLabel, 'Mlimani City');
  });
  testWidgets(
    'moving fixes update marker and camera; dragging allows browsing and recenter follows again',
    (tester) async {
      final location = _Location();
      final container = await _launch(tester, location);
      expect(location.watches, 1);
      location.fixes.add(_fix(-6.78));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-location-marker')), findsOneWidget);
      expect(_camera(tester).center.latitude, closeTo(-6.78, .00001));
      expect(find.text('18 km/h'), findsOneWidget);
      location.fixes.add(_fix(-6.781));
      await tester.pumpAndSettle();
      expect(_camera(tester).center.latitude, closeTo(-6.781, .00001));
      // Drag from the middle of the map: the top corner of the full-screen
      // map is under the direction banner.
      await tester.dragFrom(
        tester.getCenter(find.byType(FlutterMap)),
        const Offset(70, 45),
      );
      await tester.pumpAndSettle();
      final browsed = _camera(tester).center;
      expect(browsed.latitude, isNot(closeTo(-6.781, .00001)));
      location.fixes.add(_fix(-6.782));
      await tester.pumpAndSettle();
      expect(_camera(tester).center, browsed);
      expect(
        tester.widget<LiveRoadMap>(find.byType(LiveRoadMap)).location!.latitude,
        -6.782,
      );
      await tester.tap(find.byKey(const Key('trip-recenter')));
      await tester.pumpAndSettle();
      expect(_camera(tester).center.latitude, closeTo(-6.782, .00001));
      expect(await container.read(localStoreProvider).telemetryCount(), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale and mocked fixes disappear; pause and leaving cancel location',
    (tester) async {
      final location = _Location();
      final container = await _launch(tester, location);
      location.fixes.add(_fix(-6.78));
      await tester.pumpAndSettle();
      location.fixes.add(_fix(-6.79, stale: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-location-marker')), findsNothing);
      location.fixes.add(_fix(-6.79, mocked: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-location-marker')), findsNothing);
      await container.read(tripProvider.notifier).togglePause();
      await tester.pumpAndSettle();
      expect(location.fixes.hasListener, isFalse);
      await container.read(tripProvider.notifier).togglePause();
      await tester.pumpAndSettle();
      expect(location.watches, 2);
      container.read(routerProvider).go(ProfilePaths.profile);
      await tester.pumpAndSettle();
      expect(location.fixes.hasListener, isFalse);
      expect(await container.read(localStoreProvider).telemetryCount(), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('background clears GPS and returning needs explicit reconnect', (
    tester,
  ) async {
    final location = _Location();
    await _launch(tester, location);
    location.fixes.add(_fix(-6.78));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(location.fixes.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(location.watches, 1);
    expect(find.byKey(const Key('live-location-marker')), findsNothing);
    await tester.tap(find.byKey(const Key('trip-recenter')));
    await tester.pumpAndSettle();
    expect(location.watches, 2);
  });

  testWidgets(
    'permission denial shows recovery without preventing trip controls',
    (tester) async {
      final location = _Location()..denied = true;
      await _launch(tester, location);
      expect(location.watches, 0);
      expect(find.text('Location permission denied.'), findsOneWidget);
      expect(find.text('Retry location'), findsOneWidget);
      await tester.ensureVisible(find.text('Finish trip'));
      await tester.tap(find.text('Finish trip'));
      await tester.pumpAndSettle();
      expect(find.textContaining('KM OSRM ROUTE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed permission cannot start a watch after leaving the trip',
    (tester) async {
      final location = _Location()..permission = Completer<void>();
      final container = await _launch(tester, location);
      container.read(routerProvider).go(ProfilePaths.profile);
      await tester.pumpAndSettle();
      location.permission!.complete();
      await tester.pumpAndSettle();
      expect(location.watches, 0);
      expect(location.fixes.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'permission dialog return starts GPS but background during permission cancels it',
    (tester) async {
      final location = _Location()..permission = Completer<void>();
      await _launch(tester, location);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      location.permission!.complete();
      await tester.pumpAndSettle();
      expect(location.watches, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      location.permission = Completer<void>();
      await tester.tap(find.byKey(const Key('trip-recenter')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      location.permission!.complete();
      await tester.pumpAndSettle();
      expect(location.watches, 1);
      expect(location.fixes.hasListener, isFalse);
    },
  );

  testWidgets(
    'Profile omits replay controls without changing the active trip',
    (tester) async {
      final location = _Location();
      final container = await _launch(tester, location);
      container.read(routerProvider).go(ProfilePaths.profile);
      await tester.pumpAndSettle();
      expect(find.text('View introduction'), findsNothing);
      expect(find.text('Restart presentation'), findsNothing);
      expect(container.read(tripProvider)?.id, 'trip');
      expect(
        (await container.read(localStoreProvider).trips()).single.id,
        'trip',
      );
      expect(location.fixes.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
