import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';

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
  late ProviderContainer container;
  late MemoryLocalStore store;
  late MemorySettingsStore preferences;
  setUp(() {
    store = MemoryLocalStore();
    preferences = MemorySettingsStore();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWithValue(preferences),
      ],
    );
  });
  tearDown(() => container.dispose());
  test('onboarding choice is written before state changes', () async {
    await container
        .read(settingsProvider.notifier)
        .update((value) => value.copyWith(onboardingComplete: true));
    expect(preferences.value.onboardingComplete, isTrue);
    expect(container.read(settingsProvider).onboardingComplete, isTrue);
  });
  test('trip cannot start twice and finishes into history', () async {
    const route = _route;
    final controller = container.read(tripProvider.notifier);
    await controller.start(route);
    expect(container.read(tripProvider)?.route.id, route.id);
    await expectLater(controller.start(route), throwsStateError);
    await controller.end();
    expect(container.read(tripProvider), isNull);
    expect((await store.trips()).single.isActive, isFalse);
  });
  test(
    'local report has no claimed server lifecycle status or identity fields',
    () async {
      final fix = GpsFix(
        latitude: -6.79,
        longitude: 39.2,
        speedMps: 0,
        accuracyMeters: 4,
        observedAt: DateTime.now(),
      );
      final report = await container
          .read(reportWriterProvider)
          .save(
            kind: HazardKind.pothole,
            notes: '  Pothole near the crossing.  ',
            fix: fix,
            photo: Uint8List.fromList([1, 2, 3]),
          );
      expect(report.delivery, DeliveryState.localOnly);
      expect(report.serverStatus, isNull);
      expect(report.notes, 'Pothole near the crossing.');
      expect(report.toJson().containsKey('user_id'), isFalse);
      expect(report.toJson().containsKey('device_token'), isFalse);
      expect((await store.reports()).length, 1);
    },
  );
  test('save independently rejects moving GPS', () async {
    await expectLater(
      container
          .read(reportWriterProvider)
          .save(
            kind: HazardKind.pothole,
            notes: '',
            fix: GpsFix(
              latitude: -6.79,
              longitude: 39.2,
              speedMps: .6, // above the 0.5 m/s standing-still limit
              accuracyMeters: 4,
              observedAt: DateTime.now(),
            ),
            photo: Uint8List.fromList([1]),
          ),
      throwsStateError,
    );
    expect(await store.reports(), isEmpty);
  });
  test('a confirmation photo is required', () async {
    await expectLater(
      container
          .read(reportWriterProvider)
          .save(kind: HazardKind.pothole, notes: '', fix: null, photo: null),
      throwsArgumentError,
    );
  });
}
