import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

Future<ProviderContainer> launch(
  WidgetTester tester, {
  bool accessible = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      ],
      child: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: const RoadGuardApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
}

void main() {
  testWidgets(
    'map fills Explore, keeps attribution and a reachable My location button',
    (tester) async {
      await launch(tester);
      expect(
        tester.getSize(find.byKey(const Key('live-map'))).height,
        tester.getSize(find.byKey(const Key('explore-map-canvas'))).height,
      );
      // The redesigned Explore no longer overlays a sample alert on the map.
      expect(find.byKey(const Key('explore-alert-sheet')), findsNothing);
      expect(find.byKey(const Key('map-attribution')) /* OpenStreetMap credit */, findsOneWidget);
      expect(
        find.byKey(const Key('map-my-location')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving Explore cancels the sheet timer without reopening it over another page',
    (tester) async {
      final container = await launch(tester);
      container.read(routerProvider).go(HomePaths.alerts);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 12));
      expect(find.byKey(const Key('explore-alert-sheet')), findsNothing);
      expect(find.text('Road alerts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
