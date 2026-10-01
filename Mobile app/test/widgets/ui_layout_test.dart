import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/permission_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/voice_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

class _SilentVoice implements VoiceService {
  @override
  Future<void> stop() async {}
}

/// Fake device permissions: [answer] is what the next location request returns.
class _FakePermissions implements PermissionService {
  PermissionState location = PermissionState.denied;
  PermissionState answer = PermissionState.granted;
  @override
  Future<PermissionSnapshot> snapshot() async => PermissionSnapshot(
    location: location,
    locationServicesEnabled: true,
    camera: PermissionState.denied,
    motion: PermissionState.granted,
  );
  @override
  Future<PermissionState> requestLocation() async => location = answer;
  @override
  Future<PermissionState> requestCamera() async => PermissionState.denied;
  @override
  Future<PermissionState> requestMotion() async => PermissionState.granted;
  @override
  Future<SensorState> checkMotionSensors() async => SensorState.available;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

/// Destination picked in Explore.
const _posta = PlaceResult(
  label: 'Posta, Dar es Salaam',
  latitude: -6.81,
  longitude: 39.28,
);

/// Fake GPS that always reports a fresh fix (the planner starts from it).
class _HereLocation implements LocationService {
  @override
  Future<void> requestAccess() async {}
  @override
  Stream<GpsFix> watch() => Stream.value(
    GpsFix(
      latitude: -6.77,
      longitude: 39.22,
      speedMps: 0,
      accuracyMeters: 6,
      observedAt: DateTime.now(),
    ),
  );
  @override
  Future<void> openSettings() async {}
}

/// Fake RoadGuard service: one place for any search, one route, no hazards.
RoadApi _searchApi() => RoadApi(
  'https://roadguard.example.test',
  client: MockClient((request) async {
    if (request.body.contains('searchPlaces')) {
      return http.Response(
        jsonEncode({
          'data': {
            'searchPlaces': [
              {
                'label': 'Posta, Dar es Salaam',
                'latitude': -6.81,
                'longitude': 39.28,
              },
            ],
          },
        }),
        200,
      );
    }
    if (request.body.contains('drivingRoutes')) {
      return http.Response(
        jsonEncode({
          'data': {
            'drivingRoutes': [
              {
                'id': 'route-fixture',
                'distanceMeters': 1800,
                'durationSeconds': 300,
                'coordinatesJson': '[[39.22,-6.77],[39.28,-6.81]]',
                'computedAt': '2026-09-21T06:00:00Z',
                'provider': 'OSRM / OpenStreetMap',
              },
            ],
          },
        }),
        200,
      );
    }
    return http.Response('{"data":{"publicHazards":[]}}', 200);
  }),
);

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  bool onboarded = true,
  Size size = const Size(320, 640),
  String appearance = 'light',
  LocationService? location,
  PermissionService? permissions,
  RoadApi? api,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final settings = AppSettings(
    onboardingComplete: onboarded,
    appearance: appearance,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Sign-in is required after onboarding; start as a signed-in traveller.
        authServiceProvider.overrideWithValue(signedInAuthService()),
        mapTileProviderFactoryProvider.overrideWithValue(
          testMapTileProviderFactory,
        ),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore(settings)),
        initialSettingsProvider.overrideWithValue(settings),
        voiceServiceProvider.overrideWithValue(_SilentVoice()),
        if (location != null)
          locationServiceProvider.overrideWithValue(location),
        if (permissions != null)
          permissionServiceProvider.overrideWithValue(permissions),
        if (api != null) roadApiProvider.overrideWithValue(api),
      ],
      child: const RoadGuardApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
}

/// Scroll the page to its end, checking for layout errors on the way.
/// Fixed-layout screens (e.g. the full-screen maps) have nothing to scroll;
/// for those it only checks that nothing overflows.
Future<void> _scrollPage(WidgetTester tester, {String? reason}) async {
  if (find.byType(Scrollable).evaluate().isEmpty) {
    expect(tester.takeException(), isNull, reason: reason);
    return;
  }
  final scrollable = find.byType(Scrollable).first;
  // Up to 200 steps: the privacy page runs to ~15,000 px at 200% text.
  for (var i = 0; i < 200; i++) {
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: reason);
    if (tester.state<ScrollableState>(scrollable).position.extentAfter == 0) {
      return;
    }
  }
  fail('The page could not be scrolled to the end. $reason');
}

const _route = RouteOption(
  id: 'fixture-route',
  origin: 'Mlimani City',
  destination: 'Posta',
  road: 'OSRM / OpenStreetMap',
  kilometers: 12.4,
  minutes: 28,
  hazardIds: [],
  coordinates: [
    [39.22, -6.77],
    [39.25, -6.79],
    [39.28, -6.81],
  ],
);

void main() {
  testWidgets(
    'a refused location request explains itself and keeps Allow location; allowing updates the status',
    (tester) async {
      final permissions = _FakePermissions();
      // The permissions screen is the last onboarding step.
      final container = await _launch(
        tester,
        onboarded: false,
        permissions: permissions,
      );
      container.read(routerProvider).go('/permissions');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Allow location'), 200);
      await tester.pumpAndSettle();

      // The traveller refuses: say so, and keep the button to try again.
      permissions.answer = PermissionState.denied;
      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      expect(find.text('Location access was not allowed.'), findsOneWidget);
      expect(find.text('Not allowed'), findsWidgets);
      expect(find.text('Allow location'), findsOneWidget);

      // The traveller allows: the status updates and the button goes away.
      permissions.answer = PermissionState.granted;
      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      expect(find.text('Allow location'), findsNothing);
      expect(find.text('Allowed'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all onboarding pages remain usable with large text', (
    tester,
  ) async {
    await _launch(tester, onboarded: false);
    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    for (var page = 0; page < 3; page++) {
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Make it yours'), findsOneWidget); // permissions screen
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape onboarding fits large text and system bars', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPadding);
    await _launch(tester, onboarded: false, size: const Size(640, 320));
    await tester.ensureVisible(find.text('Get Started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    for (var page = 0; page < 3; page++) {
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('onboarding-next')),
        150,
        scrollable: find.descendant(
          of: find.byKey(ValueKey('onboarding-page-$page')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Make it yours'), findsOneWidget); // permissions screen
    expect(tester.takeException(), isNull);
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets(
      'main screens scroll at 320px and 200% text in $appearance mode',
      (tester) async {
        final container = await _launch(tester, appearance: appearance);
        for (final path in [
          '/explore',
          '/alerts',
          '/plan',
          '/trips',
          '/you',
          '/permissions',
          '/privacy',
          '/storage',
          '/hazards',
          '/hazard/unknown-hazard',
        ]) {
          container.read(routerProvider).go(path);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: path);
          await _scrollPage(tester, reason: path);
        }
      },
    );
  }

  testWidgets('route planner sheet stays usable in landscape at 200% text', (
    tester,
  ) async {
    final container = await _launch(
      tester,
      size: const Size(640, 320),
      api: _searchApi(),
      location: _HereLocation(),
    );
    unawaited(
      container.read(routerProvider).push(PlannerPaths.plan, extra: _posta),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveRoadMap), findsWidgets);
    final start = find.byKey(const Key('start-trip'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'place search results stay reachable in landscape with large text',
    (tester) async {
      await _launch(
        tester,
        size: const Size(640, 320),
        api: _searchApi(),
        location: _HereLocation(),
      );
      await tester.tap(find.byKey(const Key('live-plan')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('place-query')), 'Posta');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final option = find.text('Posta, Dar es Salaam');
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      // Choosing the place opens the planner for it (pushed over Explore).
      expect(find.byKey(const Key('start-trip')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance choices remain reachable in landscape with large text',
    (tester) async {
      final container = await _launch(tester, size: const Size(640, 320));
      container.read(routerProvider).go('/you');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Appearance'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).appearance, 'dark');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('trip controls and finish dialog work at 200% text', (
    tester,
  ) async {
    final container = await _launch(tester);
    await container.read(tripProvider.notifier).start(_route);
    container.read(routerProvider).go('/trip');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _scrollPage(tester);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(container.read(tripProvider)?.paused, isTrue);
    await tester.tap(find.text('Finish trip'));
    await tester.pumpAndSettle();
    expect(container.read(tripProvider), isNull);
    expect(find.text('Your journeys.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
