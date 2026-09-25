import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

/// Fake GPS that always reports a fresh fix at Mlimani City (the planner's
/// starting point is the driver's current location).
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

/// The destination the driver picked in Explore.
const _posta = PlaceResult(
  label: 'Posta, Dar es Salaam',
  latitude: -6.81,
  longitude: 39.28,
);

void main() {
  late bool fail, emptyRoutes;
  late List<Map<String, Object?>> hazards;
  late RoadApi api;
  late int searches;
  setUp(() {
    fail = false;
    searches = 0;
    emptyRoutes = false;
    hazards = [];
    api = RoadApi(
      'https://roadguard.example.test',
      client: MockClient((request) async {
        if (fail) return http.Response('{}', 503);
        if (request.body.contains('searchPlaces')) {
          searches++;
          final start =
              jsonDecode(request.body)['variables']['query'] == 'Mlimani City';
          return http.Response(
            jsonEncode({
              'data': {
                'searchPlaces': [
                  {
                    'label': start
                        ? 'Mlimani City, Dar es Salaam'
                        : 'Posta, Dar es Salaam',
                    'latitude': start ? -6.77 : -6.81,
                    'longitude': start ? 39.22 : 39.28,
                  },
                ],
              },
            }),
            200,
          );
        }
        final route = request.body.contains('drivingRoutes');
        return http.Response(
          jsonEncode({
            'data': route
                ? {
                    'drivingRoutes': emptyRoutes
                        ? <Object?>[]
                        : [
                            {
                              'id': 'route-fixture',
                              'distanceMeters': 1800,
                              'durationSeconds': 300,
                              'coordinatesJson': '[[39.2,-6.8],[39.21,-6.81]]',
                              'computedAt': '2026-09-21T06:00:00Z',
                              'provider': 'OSRM / OpenStreetMap',
                            },
                          ],
                  }
                : {'publicHazards': hazards},
          }),
          200,
        );
      }),
    );
  });
  tearDown(() => api.dispose());
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    bool large = false,
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    if (large) tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const settings = AppSettings(onboardingComplete: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Sign-in is required after onboarding; start as a signed-in traveller.
          authServiceProvider.overrideWithValue(signedInAuthService()),
          roadApiProvider.overrideWithValue(api),
          mapTileProviderFactoryProvider.overrideWithValue(
            testMapTileProviderFactory,
          ),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
          settingsStoreProvider.overrideWithValue(
            MemorySettingsStore(settings),
          ),
          initialSettingsProvider.overrideWithValue(settings),
          locationServiceProvider.overrideWithValue(_HereLocation()),
        ],
        child: const RoadGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
  }

  testWidgets(
    'live hazards have explicit empty, failure and loaded states',
    (tester) async {
      await launch(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('No confirmed hazards in this view'), findsOneWidget);
      fail = true;
      await tester.tap(find.byTooltip('Refresh hazards'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hazards unavailable · tap refresh to retry'),
        findsOneWidget,
      );
      fail = false;
      hazards = [
        {
          'id': 'fixture',
          'category': 'POTHOLE',
          'severity': 'HIGH',
          // At the map's starting centre, so the pin is inside the small test view.
          'latitude': -6.7924,
          'longitude': 39.2083,
          'updatedAt': '2026-09-21T06:00:00Z',
        },
      ];
      await tester.tap(find.byTooltip('Refresh hazards'));
      await tester.pumpAndSettle();
      // The redesigned Explore shows hazards as map pins with a status line
      // (it no longer pops up a timed alert sheet).
      expect(find.text('1 hazard · refreshed now'), findsOneWidget);
      expect(find.byTooltip('Confirmed Pothole'), findsOneWidget);
      // A crowd-reported hazard is never labelled "confirmed".
      hazards = [
        {...hazards.single, 'id': 'crowd', 'verification': 'CROWD_REPORTED'},
      ];
      await tester.tap(find.byTooltip('Refresh hazards'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pothole reported by drivers'), findsOneWidget);
      expect(find.byTooltip('Confirmed Pothole'), findsNothing);
      // Tapping a hazard zooms to about ±30 m around it and opens its details,
      // worded "reported by drivers" (not "confirmed").
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap).first);
      final zoomBefore = map.mapController!.camera.zoom;
      await tester.tap(find.byTooltip('Pothole reported by drivers'));
      await tester.pumpAndSettle();
      final camera = map.mapController!.camera;
      expect(camera.zoom, greaterThan(zoomBefore));
      expect(camera.zoom, greaterThanOrEqualTo(19));
      expect(camera.center.latitude, closeTo(-6.7924, 0.0002));
      expect(camera.center.longitude, closeTo(39.2083, 0.0002));
      expect(find.text('Pothole reported by drivers'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Report hazard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'live planner preserves server geometry through start pause finish and history',
    (tester) async {
      final container = await launch(tester);
      // Explore → destination → Directions opens the planner, which finds a
      // live route from the current location.
      unawaited(container.read(routerProvider).push(PlannerPaths.plan, extra: _posta));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-trip')));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider)!.route.hasGeometry, isTrue);
      expect(container.read(tripProvider)!.route.coordinates, [
        [39.2, -6.8],
        [39.21, -6.81],
      ]);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider)!.paused, isTrue);
      await tester.tap(find.text('Finish trip'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider), isNull);
      expect(find.textContaining('KM OSRM ROUTE'), findsOneWidget);
      expect(
        (await container.read(localStoreProvider).trips()).single.route.hasGeometry,
        isTrue,
      );
      expect(await container.read(localStoreProvider).telemetryCount(), 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('live Explore and planner fit 320px with 200 percent text', (
    tester,
  ) async {
    final container = await launch(tester, large: true);
    expect(tester.takeException(), isNull);
    unawaited(container.read(routerProvider).push(PlannerPaths.plan, extra: _posta));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The route summary and the Start button stay on screen and usable.
    expect(find.byKey(const Key('start-trip')).hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'search picks a destination, the planner routes to it, and icon controls stay aligned',
    (tester) async {
      final container = await launch(tester);
      await container
          .read(tripProvider.notifier)
          .start(
            RouteOption(
              id: 'existing',
              origin: 'A',
              destination: 'B',
              road: 'OSRM',
              kilometers: 2,
              minutes: 5,
              hazardIds: [],
              coordinates: [
                [39.2, -6.8],
                [39.21, -6.81],
              ],
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Choose a driving route'), findsNothing);
      expect(find.text('My location'), findsNothing);
      expect(find.text('Resume trip'), findsNothing);
      final locate = tester.getRect(find.byKey(const Key('map-my-location')));
      final report = tester.getRect(find.byKey(const Key('map-report-hazard')));
      final resume = tester.getRect(find.byKey(const Key('map-resume-trip')));
      expect(locate.width, greaterThanOrEqualTo(48));
      expect(locate.right, report.right);
      expect(report.right, resume.right);
      expect(locate.bottom, lessThan(report.top));
      expect(report.bottom, lessThan(resume.top));
      expect(resume.right, greaterThan(280));
      await tester.tap(find.byKey(const Key('live-plan')));
      await tester.pumpAndSettle();
      // Fewer than 3 characters never reach the server.
      await tester.enterText(find.byKey(const Key('place-query')), 'Po');
      await tester.pump(const Duration(seconds: 1));
      expect(searches, 0);
      await tester.enterText(find.byKey(const Key('place-query')), 'Posta');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Posta, Dar es Salaam'));
      await tester.pumpAndSettle();
      // Picking a result opens the route planner directly, which routes
      // from the current location to the chosen place.
      expect(find.text('To Posta, Dar es Salaam'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('start-trip'))).onPressed,
        isNotNull,
      );
      expect(searches, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
