import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/injection/injection_container.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/modules/profile/presentation/providers/settings_provider.dart';
import 'package:roadguard_ai/modules/trips/presentation/providers/trip_provider.dart';
import 'package:roadguard_ai/shared/widgets/storage_failure_app.dart';

const _route = RouteOption(
  id: 'bootstrap-route',
  origin: 'Mlimani City',
  destination: 'Posta',
  road: 'OSRM / OpenStreetMap',
  kilometers: 12.4,
  minutes: 28,
  hazardIds: [],
);

TripRecord _trip({required String id, bool finished = false}) => TripRecord(
  id: id,
  route: _route,
  startedAt: DateTime.utc(2026, 9, 1),
  endedAt: finished ? DateTime.utc(2026, 9, 1, 1) : null,
  paused: !finished,
);

void main() {
  testWidgets('restores persisted preferences and the active trip into scope', (
    tester,
  ) async {
    const settings = AppSettings(
      onboardingComplete: true,
      voiceEnabled: false,
      appearance: 'dark',
    );
    final preferences = MemorySettingsStore(settings);
    final store = _TrackingStore();
    final activeTrip = _trip(id: 'paused-trip');
    await store.saveTrip(_trip(id: 'finished-trip', finished: true));
    await store.saveTrip(activeTrip);

    final dependencies = await AppDependencies.load(
      settingsStore: preferences,
      openStore: () async => store,
    );
    await tester.pumpWidget(
      dependencies.scope(
        child: Consumer(
          builder: (context, ref, child) {
            expect(ref.read(localStoreProvider), same(store));
            expect(ref.read(settingsStoreProvider), same(preferences));
            expect(ref.watch(settingsProvider).toJson(), settings.toJson());
            expect(ref.watch(tripProvider)?.toJson(), activeTrip.toJson());
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(store.closeCount, 0);
    expect(store.clearCount, 0);
  });

  test('finished history does not become an active trip', () async {
    final store = _TrackingStore();
    await store.saveTrip(_trip(id: 'finished-trip', finished: true));
    final dependencies = await AppDependencies.load(
      settingsStore: MemorySettingsStore(),
      openStore: () async => store,
    );

    expect(dependencies.activeTrip, isNull);
    expect((await store.trips()).single.id, 'finished-trip');
    expect(store.clearCount, 0);
  });

  test('failed settings load does not open the database', () async {
    var openCount = 0;
    await expectLater(
      AppDependencies.load(
        settingsStore: _FailedSettingsStore(),
        openStore: () async {
          openCount++;
          return _TrackingStore();
        },
      ),
      throwsFormatException,
    );

    expect(openCount, 0);
  });

  test('failed trip read closes without erasure and allows retry', () async {
    final store = _TrackingStore()..failTripRead = true;
    final activeTrip = _trip(id: 'saved-trip');
    await store.saveTrip(activeTrip);
    await store.enqueueTelemetry(
      const OutboxRecord(id: 'existing-record', payload: 'preserve-me'),
    );
    final preferences = MemorySettingsStore();
    var openCount = 0;
    Future<LocalStore> openStore() async {
      openCount++;
      return store;
    }

    await expectLater(
      AppDependencies.load(settingsStore: preferences, openStore: openStore),
      throwsStateError,
    );
    expect(store.closeCount, 1);
    expect(store.clearCount, 0);
    expect(await store.telemetryCount(), 1);

    store.failTripRead = false;
    final retried = await AppDependencies.load(
      settingsStore: preferences,
      openStore: openStore,
    );
    expect(openCount, 2);
    expect(retried.activeTrip?.toJson(), activeTrip.toJson());
    expect(store.closeCount, 1);
    expect(store.clearCount, 0);
    expect((await store.pendingTelemetry()).single.payload, 'preserve-me');
  });

  testWidgets('storage failure keeps recovery guidance and a working retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(StorageFailureApp(onRetry: () => retries++));

    expect(find.text('Local storage could not be opened.'), findsOneWidget);
    expect(
      find.text(
        'Your existing data has not been cleared. Check device storage and try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });
}

class _TrackingStore extends MemoryLocalStore {
  bool failTripRead = false;
  int closeCount = 0;
  int clearCount = 0;

  @override
  Future<List<TripRecord>> trips() async {
    if (failTripRead) throw StateError('Trip data could not be read.');
    return super.trips();
  }

  @override
  Future<void> close() async {
    closeCount++;
    await super.close();
  }

  @override
  Future<void> clearUserData() async {
    clearCount++;
    await super.clearUserData();
  }
}

class _FailedSettingsStore extends MemorySettingsStore {
  @override
  Future<AppSettings> load() async =>
      throw const FormatException('Preferences');
}
