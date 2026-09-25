import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/voice_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

class _SilentVoice implements VoiceService {
  @override
  Future<void> stop() async {}
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
    'navigation banner and trip controls stay reachable beneath the trip sheet at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      const settings = AppSettings(onboardingComplete: true);
      final store = MemoryLocalStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Sign-in is required after onboarding; start as a signed-in traveller.
            authServiceProvider.overrideWithValue(signedInAuthService()),
            mapTileProviderFactoryProvider.overrideWithValue(
              testMapTileProviderFactory,
            ),
            localStoreProvider.overrideWithValue(store),
            settingsStoreProvider.overrideWithValue(
              MemorySettingsStore(settings),
            ),
            initialSettingsProvider.overrideWithValue(settings),
            voiceServiceProvider.overrideWithValue(_SilentVoice()),
          ],
          child: const RoadGuardApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RoadGuardApp)),
      );
      await container.read(tripProvider.notifier).start(_route);
      final router = container.read(routerProvider);
      router.go(TripPaths.active);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The redesigned trip screen has no hazard list (warnings arrive as
      // banners); what must stay reachable beneath the trip sheet at large text
      // on a small phone is the navigation banner and every trip control.
      for (final control in [
        find.byKey(const Key('trip-direction-banner')),
        find.byKey(const Key('trip-recenter')),
        find.text('Pause'),
        find.text('Finish trip'),
      ]) {
        expect(control.hitTestable(), findsOneWidget, reason: '$control');
      }
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider)!.paused, isTrue);
      expect(find.text('Resume').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect((await store.trips()).single.isActive, isTrue);
    },
  );
}
