import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/photo_service.dart';
import 'package:roadguard_ai/core/services/voice_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

import '../support/photos.dart';

class TestPhotoService implements PhotoService {
  @override
  Future<Uint8List?> capture() async => testPhoto();
  @override
  Future<Uint8List?> recover() async => null;
}

/// Fake GPS: the test pushes fixes into [fixes].
class _Location implements LocationService {
  final fixes = StreamController<GpsFix>.broadcast();
  @override
  Future<void> requestAccess() async {}
  @override
  Stream<GpsFix> watch() => fixes.stream;
  @override
  Future<void> openSettings() async {}
}

class TestVoiceService implements VoiceService {
  @override
  Future<void> stop() async {}
}

void main() {
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    bool onboarded = false,
    double width = 390,
    LocationService? location,
  }) async {
    tester.view.physicalSize = Size(width, 844);
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
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
          settingsStoreProvider.overrideWithValue(
            MemorySettingsStore(settings),
          ),
          initialSettingsProvider.overrideWithValue(settings),
          photoServiceProvider.overrideWithValue(TestPhotoService()),
          voiceServiceProvider.overrideWithValue(TestVoiceService()),
          if (location != null)
            locationServiceProvider.overrideWithValue(location),
        ],
        child: const RoadGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
  }

  testWidgets('first launch offers welcome and the complete guest onboarding', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Safer Roads. Smarter Journeys'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Know the road ahead'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('onboarding pages lead to the optional permission choices', (
    tester,
  ) async {
    final container = await launch(tester);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    // Three onboarding pages; the button on the last one opens permissions.
    for (var page = 0; page < 3; page++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Make it yours'), findsOneWidget);
    await tester.tap(find.byKey(const Key('permissions-continue')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).onboardingComplete, isTrue);
    // Signed in (see launch), so the app opens Explore.
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/explore',
    );
  });
  testWidgets('unknown GPS keeps report form disabled', (tester) async {
    final container = await launch(tester, onboarded: true);
    container.read(routerProvider).go('/report');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-notes')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('report-notes'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('upload-report')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('moving GPS locks form fields as well as uploading', (
    tester,
  ) async {
    final location = _Location();
    final container = await launch(tester, onboarded: true, location: location);
    container.read(routerProvider).go('/report');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check device location'));
    await tester.pumpAndSettle();
    location.fixes.add(
      GpsFix(
        latitude: -6.79,
        longitude: 39.25,
        speedMps: 1.2, // walking pace: above the 0.5 m/s standing-still limit
        accuracyMeters: 4,
        observedAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Please stop safely first'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-notes')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('report-notes'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('upload-report')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('explore fits a small mobile viewport', (tester) async {
    await launch(tester, onboarded: true, width: 320);
    expect(find.text('Explore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('local report empty state provides an action', (tester) async {
    final container = await launch(tester, onboarded: true);
    container.read(routerProvider).go('/reports');
    await tester.pumpAndSettle();
    expect(find.text('Notice something on the road?'), findsOneWidget);
    expect(find.text('Report a hazard'), findsOneWidget);
  });
}
