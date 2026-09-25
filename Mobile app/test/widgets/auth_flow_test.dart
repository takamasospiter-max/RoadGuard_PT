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

import '../support/map_tiles.dart';
import '../support/auth.dart';

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  bool onboarded = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  MemorySettingsStore? settingsStore,
  MemorySessionStorage? sessionStorage,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final settings = AppSettings(onboardingComplete: onboarded);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(
          testAuthService(storage: sessionStorage),
        ),
        mapTileProviderFactoryProvider.overrideWithValue(
          testMapTileProviderFactory,
        ),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        settingsStoreProvider.overrideWithValue(
          settingsStore ?? MemorySettingsStore(settings),
        ),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const RoadGuardApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RoadGuardApp)));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: finder.toString());
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('welcome opens onboarding without completing it', (tester) async {
    final container = await _launch(tester);
    expect(find.text('Sign in'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('welcome-get-started')));
    expect(find.byKey(const Key('onboarding-next')), findsOneWidget);
    expect(container.read(settingsProvider).onboardingComplete, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed login stays on the form and successful login securely saves a session',
    (tester) async {
      final storage = MemorySessionStorage();
      final container = await _launch(tester, sessionStorage: storage);
      container.read(routerProvider).go(AuthPaths.signIn);
      await tester.pumpAndSettle();
      await _enter(tester, 'sign-in-identity', 'traveler@example.test');
      await _enter(tester, 'sign-in-password', 'wrong-password');
      await _tapVisible(tester, find.byKey(const Key('sign-in-submit')));
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(storage.value, isNull);
      expect(container.read(authProvider).asData?.value, isNull);
      await _enter(tester, 'sign-in-password', 'Cobalt!River-Travel2026');
      await _tapVisible(tester, find.byKey(const Key('sign-in-submit')));
      expect(
        container.read(authProvider).asData?.value?.name,
        'Example Traveler',
      );
      expect(storage.value, isNotNull);
      expect(storage.value, isNot(contains('Cobalt!River')));
      expect(container.read(settingsProvider).onboardingComplete, isFalse);
      expect(find.byKey(const Key('permissions-continue')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration requires matching strong passwords and displays server identity',
    (tester) async {
      final container = await _launch(tester, onboarded: true);
      container.read(routerProvider).go(AuthPaths.register);
      await tester.pumpAndSettle();
      await _enter(tester, 'register-name', 'New Traveler');
      await _enter(tester, 'register-email', 'new@example.test');
      await _enter(tester, 'register-password', 'Cobalt!River-Travel2026');
      await _enter(tester, 'register-confirmation', 'different-password');
      await _tapVisible(tester, find.byKey(const Key('register-submit')));
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(container.read(authProvider).asData?.value, isNull);
      await _enter(tester, 'register-confirmation', 'Cobalt!River-Travel2026');
      await _tapVisible(tester, find.byKey(const Key('register-submit')));
      expect(container.read(authProvider).asData?.value?.name, 'New Traveler');
      container.read(routerProvider).go(ProfilePaths.profile);
      await tester.pumpAndSettle();
      expect(find.text('New Traveler'), findsOneWidget);
      expect(find.text('new@example.test'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('profile-sign-out')));
      // Sign-in is required, so logging out returns to the sign-in screen.
      expect(container.read(authProvider).asData?.value, isNull);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        AuthPaths.signIn,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signed-out travellers are sent to sign-in, keeping onboarding complete', (
    tester,
  ) async {
    final container = await _launch(tester, onboarded: true);
    container.read(routerProvider).go(ProfilePaths.profile);
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      AuthPaths.signIn,
    );
    expect(container.read(settingsProvider).onboardingComplete, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forms remain reachable on a small screen with large text and keyboard',
    (tester) async {
      final container = await _launch(
        tester,
        size: const Size(320, 568),
        textScale: 2,
      );
      container.read(routerProvider).go(AuthPaths.signIn);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetViewInsets);
      await _enter(tester, 'sign-in-identity', 'traveler@example.test');
      await _tapVisible(tester, find.text('Create account'));
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
      expect(find.byKey(const Key('auth-continue-guest')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signed-in Profile shows the account and log out, without introduction actions',
    (tester) async {
      final container = await _launch(
        tester,
        onboarded: true,
        sessionStorage: signedInSessionStorage(),
      );
      container.read(routerProvider).go(ProfilePaths.profile);
      await tester.pumpAndSettle();
      expect(find.text('Example Traveler'), findsOneWidget);
      expect(find.byKey(const Key('profile-sign-out')), findsOneWidget);
      expect(find.text('Create account'), findsNothing);
      expect(find.text('View introduction'), findsNothing);
      expect(find.text('Restart presentation'), findsNothing);
      expect(container.read(settingsProvider).onboardingComplete, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
