import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';

import '../test/support/auth.dart';

class _NoDeviceLocation implements LocationService {
  @override
  Future<void> requestAccess() async =>
      throw StateError('Location not enabled in this service test.');
  @override
  Stream<GpsFix> watch() =>
      throw StateError('The service test must not start GPS.');
  @override
  Future<void> openSettings() async {}
}

// Real HTTP to local Django/PostGIS and the approved public OSRM service.
// Guest navigation only: no GPS, sensor collection, credentials or report writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('Android live hazards and OSRM route start pause finish', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    const base = String.fromEnvironment('ROADGUARD_API_URL');
    expect(base, isNotEmpty);
    final api = RoadApi(base);
    final guestAuth = AuthService(baseUrl: '', storage: MemorySessionStorage());
    final store = await openLocalStore(
      databasePath:
          '${await getDatabasesPath()}/roadguard-live-service-test.db',
    );
    await store.clearUserData();
    const settings = AppSettings(onboardingComplete: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roadApiProvider.overrideWithValue(api),
          authServiceProvider.overrideWithValue(guestAuth),
          localStoreProvider.overrideWithValue(store),
          settingsStoreProvider.overrideWithValue(
            MemorySettingsStore(settings),
          ),
          initialSettingsProvider.overrideWithValue(settings),
          locationServiceProvider.overrideWithValue(_NoDeviceLocation()),
        ],
        child: const RoadGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RoadGuardApp)),
    );
    // A successful query may legitimately be empty: no invented presentation hazards.
    final hazards = await api.hazards({
      'west': 39.1,
      'south': -6.95,
      'east': 39.4,
      'north': -6.6,
    });
    expect(hazards.length, lessThanOrEqualTo(100));
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('services-explore');
    await tester.tap(find.byKey(const Key('live-plan')));
    await tester.pumpAndSettle();
    Future<void> search(String key, String text) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('place-query')), text);
      await tester.tap(find.byTooltip('Search places'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 && find.byType(ListTile).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final result = find.byType(ListTile).first;
      expect(result, findsOneWidget);
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await tester.tap(result);
      await tester.pumpAndSettle();
    }

    await search('route-start-search', 'Mlimani City, Dar es Salaam');
    await search('route-destination-search', 'Posta, Dar es Salaam');
    await binding.takeScreenshot('search-directions');
    Future<void> tap(String text) async {
      final finder = find.text(text).last;
      // Drag the page margin: the embedded map correctly owns map gestures.
      for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
        final page = tester.getRect(find.byType(Scrollable).first);
        await tester.dragFrom(
          Offset(page.left + 5, page.bottom - 60),
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
      }
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap('Find live routes');
    for (
      var i = 0;
      i < 100 && find.text('Start selected route').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tap('Start selected route');
    final trip = container.read(tripProvider)!;
    expect(trip.route.hasGeometry, isTrue);
    expect(trip.route.coordinates.length, greaterThan(1));
    expect(trip.route.kilometers, greaterThan(0));
    await binding.takeScreenshot('services-live-trip');
    await tap('Pause');
    expect(container.read(tripProvider)!.paused, isTrue);
    await tap('Resume');
    expect(container.read(tripProvider)!.paused, isFalse);
    await tap('Finish trip');
    expect(container.read(tripProvider), isNull);
    expect(
      (await store.trips()).single.route.coordinates,
      trip.route.coordinates,
    );
    expect(await store.telemetryCount(), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await store.clearUserData();
    await store.close();
    api.dispose();
    guestAuth.dispose();
  });
}
