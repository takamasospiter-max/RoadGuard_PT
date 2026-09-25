import 'package:roadguard_ai/core/services/road_api.dart';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/modules/auth/presentation/widgets/auth_layout.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../test/support/map_tiles.dart';

// Real Django HTTP + Android secure storage, with a dedicated test account/key.
// No existing device preferences, credentials, reports or accounts are cleared.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const base = String.fromEnvironment('ROADGUARD_API_URL');
  const email = String.fromEnvironment('ROADGUARD_TEST_EMAIL');
  const storage = SecureSessionStorage(
    key: 'roadguard.presentation.integration',
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final field = find.byKey(Key(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field).controller!.text == value,
      isTrue,
      reason: '$key must contain the entered value (value withheld).',
    );
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(finder, findsOneWidget);
  }

  testWidgets('real registration, secure restore, logout and login on Android', (
    tester,
  ) async {
    // Flutter documents that injected text may conflict with a real IME.
    // Control text entry here; HTTP, Android secure storage and widgets are real.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    expect(base, isNotEmpty);
    expect(email.endsWith('@roadguard.example'), isTrue);
    await storage.clear(); // This test's dedicated key only.
    final random = Random.secure();
    final password =
        '${base64UrlEncode(List.generate(24, (_) => random.nextInt(256)))}R!7';
    final service = AuthService(baseUrl: base, storage: storage);
    final settings = MemorySettingsStore();
    final store = MemoryLocalStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(service),
          // This test isolates auth; live road services have their own device flow.
          roadApiProvider.overrideWithValue(RoadApi('')),
          mapTileProviderFactoryProvider.overrideWithValue(
            testMapTileProviderFactory,
          ),
          localStoreProvider.overrideWithValue(store),
          settingsStoreProvider.overrideWithValue(settings),
          initialSettingsProvider.overrideWithValue(const AppSettings()),
        ],
        child: const RoadGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RoadGuardApp)),
    );
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('presentation-welcome');
    await tap(tester, find.text('Sign in'));
    await binding.takeScreenshot('presentation-login');
    await tap(tester, find.text('Create account'));
    await binding.takeScreenshot('presentation-register');
    await enter(tester, 'register-name', 'Presentation Test');
    await enter(tester, 'register-email', email);
    await enter(tester, 'register-password', password);
    await enter(tester, 'register-confirmation', password);
    await tap(tester, find.byKey(const Key('register-submit')));
    await waitFor(tester, find.byKey(const Key('onboarding-next')));
    expect(container.read(authProvider).asData?.value?.email, email);
    expect(await storage.read(), isNotNull);
    await binding.takeScreenshot('presentation-onboarding');
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byKey(const Key('onboarding-next')));
    }
    await tap(tester, find.text('Start exploring'));
    expect((await settings.load()).onboardingComplete, isTrue);
    await tap(tester, find.byKey(const Key('replay-map-alert')));
    expect(find.byKey(const Key('explore-alert-sheet')), findsOneWidget);
    await binding.takeScreenshot('presentation-alert');
    final accessible = MediaQuery.accessibleNavigationOf(
      tester.element(find.byKey(const Key('explore-alert-sheet'))),
    );
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    if (accessible) {
      expect(find.byKey(const Key('explore-alert-sheet')), findsOneWidget);
      await tap(tester, find.byKey(const Key('dismiss-map-alert')));
    }
    expect(find.byKey(const Key('explore-alert-sheet')), findsNothing);
    await binding.takeScreenshot('presentation-explore');

    // Reconstruct the HTTP service and read the token from actual secure storage.
    final restoredService = AuthService(baseUrl: base, storage: storage);
    expect((await restoredService.restore())?.email, email);
    restoredService.dispose();
    container.read(routerProvider).go(ProfilePaths.profile);
    await tester.pumpAndSettle();
    expect(find.text('Presentation Test'), findsOneWidget);
    await tap(tester, find.byKey(const Key('profile-sign-out')));
    await waitFor(tester, find.text('Sign in'));
    expect(await storage.read(), isNull);
    await tap(tester, find.text('Sign in'));
    await enter(tester, 'sign-in-identity', email);
    await enter(tester, 'sign-in-password', 'incorrect-password');
    await tap(tester, find.byKey(const Key('sign-in-submit')));
    await waitFor(tester, find.byKey(const Key('auth-error')));
    expect(container.read(authProvider).asData?.value, isNull);
    await enter(tester, 'sign-in-password', password);
    await tap(tester, find.byKey(const Key('sign-in-submit')));
    for (var i = 0; i < 80 && container.read(authProvider).isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final errors = tester.widgetList<AuthError>(find.byType(AuthError));
    expect(errors.map((error) => error.message), isEmpty);
    await waitFor(tester, find.byKey(const Key('explore-plan')));
    expect(container.read(authProvider).asData?.value?.email, email);
    expect(await store.telemetryCount(), 0);
    await service.signOut();
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await storage.clear();
  });
}
