import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/photo_service.dart';
import 'package:roadguard_ai/core/services/voice_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/explore_screen.dart';
import 'package:roadguard_ai/modules/planner/presentation/pages/planner_screen.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

class _Location implements LocationService {
  _Location() {
    fixes = StreamController<GpsFix>.broadcast(onCancel: () => cancellations++);
  }

  late final StreamController<GpsFix> fixes;
  int accessRequests = 0;
  int watches = 0;
  int cancellations = 0;
  bool denyAccess = false;

  @override
  Future<void> requestAccess() async {
    accessRequests++;
    if (denyAccess) {
      throw StateError(
        'Location was not allowed. You can still browse the map.',
      );
    }
  }

  @override
  Stream<GpsFix> watch() {
    watches++;
    return fixes.stream;
  }

  @override
  Future<void> openSettings() async {}
}

class _Photos implements PhotoService {
  @override
  Future<Uint8List?> capture() async => null;
  @override
  Future<Uint8List?> recover() async => null;
}

class _Voice implements VoiceService {
  @override
  Future<void> stop() async {}
}

GpsFix _freshFix() => GpsFix(
  latitude: -6.7924,
  longitude: 39.2083,
  speedMps: 4,
  accuracyMeters: 8,
  observedAt: DateTime.now(),
);

Future<void> _settleMap(WidgetTester tester) async {
  // Memory tiles still decode through Flutter's real image pipeline.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _launch(
  WidgetTester tester,
  _Location location,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await location.fixes.close();
  });
  const settings = AppSettings(onboardingComplete: true);
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
        locationServiceProvider.overrideWithValue(location),
        photoServiceProvider.overrideWithValue(_Photos()),
        voiceServiceProvider.overrideWithValue(_Voice()),
      ],
      child: const RoadGuardApp(),
    ),
  );
  // (Explore used to open with a sample alert to dismiss first; it no longer does.)
  await _settleMap(tester);
  return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
}

Future<void> _startLocation(WidgetTester tester, _Location location) async {
  await tester.ensureVisible(find.byKey(const Key('map-my-location')));
  await tester.tap(find.byKey(const Key('map-my-location')));
  await tester.pump();
  expect(location.accessRequests, 1);
  expect(location.watches, 1);
  expect(location.fixes.hasListener, isTrue);
  location.fixes.add(_freshFix());
  await _settleMap(tester);
  expect(find.byKey(const Key('live-location-marker')), findsOneWidget);
}

void main() {
  testWidgets('Explore browses tiles without GPS until My location is tapped', (
    tester,
  ) async {
    final location = _Location();
    await _launch(tester, location);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('map-attribution')) /* OpenStreetMap credit */, findsOneWidget);
    expect(location.accessRequests, 0);
    expect(location.watches, 0);
    expect(location.fixes.hasListener, isFalse);
    expect(find.byKey(const Key('live-location-marker')), findsNothing);

    await _startLocation(tester, location);
    expect(find.byTooltip('Stop location'), findsOneWidget);
    expect(location.cancellations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushing a route cancels GPS before the transition completes', (
    tester,
  ) async {
    final location = _Location();
    final container = await _launch(tester, location);
    final router = container.read(routerProvider);
    await _startLocation(tester, location);

    unawaited(router.push<void>(PlannerPaths.plan));
    await tester.pump();
    expect(location.fixes.hasListener, isFalse);
    expect(location.cancellations, 1);
    await _settleMap(tester);
    expect(find.byType(PlannerScreen), findsOneWidget);
    expect(find.byType(ExploreScreen), findsNothing);

    router.pop();
    await _settleMap(tester);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.byType(PlannerScreen), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(location.accessRequests, 1);
    expect(location.watches, 1);
    expect(location.fixes.hasListener, isFalse);
    expect(find.byKey(const Key('live-location-marker')), findsNothing);
    expect(find.byTooltip('My location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive clears the marker and resume does not restart GPS', (
    tester,
  ) async {
    final location = _Location();
    await _launch(tester, location);
    await _startLocation(tester, location);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(location.fixes.hasListener, isFalse);
    expect(location.cancellations, 1);
    await tester.pump();
    expect(find.byKey(const Key('live-location-marker')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    location.fixes.add(_freshFix());
    await tester.idle();
    expect(location.watches, 1);
    expect(location.fixes.hasListener, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settleMap(tester);
    expect(location.accessRequests, 1);
    expect(location.watches, 1);
    expect(find.byKey(const Key('live-location-marker')), findsNothing);
    expect(find.byTooltip('My location'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied location keeps the live map available without a marker', (
    tester,
  ) async {
    final location = _Location()..denyAccess = true;
    await _launch(tester, location);
    await tester.ensureVisible(find.byKey(const Key('map-my-location')));
    await tester.tap(find.byKey(const Key('map-my-location')));
    await tester.pumpAndSettle();

    expect(location.accessRequests, 1);
    expect(location.watches, 0);
    expect(location.fixes.hasListener, isFalse);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('map-attribution')) /* OpenStreetMap credit */, findsOneWidget);
    expect(find.byKey(const Key('live-location-marker')), findsNothing);
    expect(
      find.text('Location was not allowed. You can still browse the map.'),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
