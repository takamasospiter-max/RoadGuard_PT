import 'dart:async';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

import '../support/photos.dart';

class _Location implements LocationService {
  int watches = 0;
  @override
  Future<void> requestAccess() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Stream<GpsFix> watch() {
    watches++;
    return const Stream.empty();
  }
}

class _Photo implements PhotoService {
  @override
  Future<Uint8List?> capture() async => null;
  @override
  Future<Uint8List?> recover() async => null;
}

class _Voice implements VoiceService {
  @override
  Future<void> stop() async {}
}

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  bool onboarded = true,
  MemoryLocalStore? store,
  _Location? location,
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = AppSettings(onboardingComplete: onboarded);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Sign-in is required after onboarding; start as a signed-in traveller.
        authServiceProvider.overrideWithValue(signedInAuthService()),
        mapTileProviderFactoryProvider.overrideWithValue(
          testMapTileProviderFactory,
        ),
        localStoreProvider.overrideWithValue(store ?? MemoryLocalStore()),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore(settings)),
        initialSettingsProvider.overrideWithValue(settings),
        locationServiceProvider.overrideWithValue(location ?? _Location()),
        photoServiceProvider.overrideWithValue(_Photo()),
        voiceServiceProvider.overrideWithValue(_Voice()),
      ],
      child: const RoadGuardApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
}

void main() {
  testWidgets('module deep links cannot bypass unfinished onboarding', (
    tester,
  ) async {
    final location = _Location();
    final container = await _launch(
      tester,
      onboarded: false,
      location: location,
    );
    final router = container.read(routerProvider);
    for (final path in [
      '/plan',
      '/trip',
      '/report',
      '/reports',
      '/you',
      '/hazards',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/welcome');
    }
    expect(location.watches, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'module shell selection follows deep links and detail back navigation',
    (tester) async {
      final store = MemoryLocalStore();
      const route = RouteOption(id: 'history-route', origin: 'A', destination: 'B',
          road: 'OSRM', kilometers: 1, minutes: 3, hazardIds: []);
      await store.saveTrip(TripRecord(id: 'trip-1', route: route, startedAt: DateTime.now()));
      await store.saveRouteAlert(RouteAlertRecord(
        id: 'trip-1/hazard-1', tripId: 'trip-1', ownerKey: 'test-traveler', hazardId: 'hazard-1', // the signed-in test user
        kind: HazardKind.pothole, distanceMeters: 120, receivedAt: DateTime.now(),
      ));
      final container = await _launch(tester, store: store);
      final router = container.read(routerProvider);
      // Each bottom tab reports "selected" to screen readers; read it from there.
      final semantics = tester.ensureSemantics();
      String? selectedTab() {
        for (final tab in ['explore', 'alerts', 'profile']) {
          final finder = find.byKey(Key('nav-$tab'));
          if (finder.evaluate().isNotEmpty &&
              tester.getSemantics(finder).flagsCollection.isSelected == ui.Tristate.isTrue) {
            return tab;
          }
        }
        return null;
      }

      router.go('/you');
      await tester.pumpAndSettle();
      expect(find.text('Route alert history'), findsOneWidget);
      expect(selectedTab(), 'profile');
      unawaited(router.push<void>(ProfilePaths.privacy));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-profile')), findsNothing); // detail page: no tab bar
      router.pop();
      await tester.pumpAndSettle();
      expect(selectedTab(), 'profile');
      await tester.tap(find.text('My Routes'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/trips');
      expect(selectedTab(), 'profile');
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, HomePaths.alerts);
      expect(selectedTab(), 'alerts');
      expect(find.text('Road alerts'), findsOneWidget);
      expect(find.byKey(const ValueKey('received-alert-trip-1/hazard-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('received-alert-trip-1/hazard-1')));
      await tester.pumpAndSettle();
      expect(find.text('Pothole warning'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'report module resolves encoded local identifiers without losing local-only status',
    (tester) async {
      final store = MemoryLocalStore();
      final now = DateTime.now();
      final report = LocalReport(
        id: 'local report/one?#',
        kind: HazardKind.pothole,
        notes: 'Saved in the original local store.',
        fix: GpsFix(
          latitude: -6.8,
          longitude: 39.2,
          speedMps: 0,
          accuracyMeters: 5,
          observedAt: now,
        ),
        photo: testPhoto(),
        createdAt: now,
      );
      await store.saveReport(report);
      final container = await _launch(tester, store: store);
      container.read(routerProvider).go(ReportPaths.reportDetail(report.id));
      await tester.pumpAndSettle();
      expect(find.text('LOCAL ONLY'), findsOneWidget);
      expect(find.text(report.notes), findsOneWidget);
      expect(find.text('Report not found'), findsNothing);
      expect((await store.reports()).single.id, report.id);
      expect(tester.takeException(), isNull);
    },
  );
}
