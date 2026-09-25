import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

class _FailingStore extends MemoryLocalStore {
  bool fail = true;

  @override
  Future<void> saveReport(LocalReport report) async {
    if (fail) throw StateError('Storage unavailable');
    return super.saveReport(report);
  }
}

void main() {
  test(
    'writer rejects missing, expired, future, invalid and mocked real evidence',
    () async {
      final store = MemoryLocalStore();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final now = DateTime.now();
      GpsFix fix({
        double speed = 0,
        double latitude = -6.79,
        DateTime? at,
        bool mocked = false,
      }) => GpsFix(
        latitude: latitude,
        longitude: 39.2,
        speedMps: speed,
        accuracyMeters: 4,
        observedAt: at ?? now,
        isMocked: mocked,
      );
      for (final evidence in <GpsFix?>[
        null,
        fix(speed: -1),
        fix(speed: double.nan),
        fix(speed: double.infinity),
        fix(speed: 0.6), // moving: above the 0.5 m/s standing-still limit
        fix(latitude: 91),
        fix(mocked: true),
        fix(at: now.subtract(const Duration(seconds: 11))),
        fix(at: now.add(const Duration(minutes: 1))),
      ]) {
        await expectLater(
          container
              .read(reportWriterProvider)
              .save(
                kind: HazardKind.pothole,
                notes: '',
                fix: evidence,
                photo: Uint8List.fromList([1]),
              ),
          throwsStateError,
        );
      }
      expect(await store.reports(), isEmpty);
    },
  );

  test(
    'failed persistence does not report success and permits a later retry',
    () async {
      final store = _FailingStore();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      Future<LocalReport> save() => container
          .read(reportWriterProvider)
          .save(
            kind: HazardKind.pothole,
            notes: 'Retry after a storage failure',
            photo: Uint8List.fromList([1]),
            fix: GpsFix(
              latitude: -6.79,
              longitude: 39.2,
              speedMps: 0,
              accuracyMeters: 4,
              observedAt: DateTime.now(),
            ),
          );
      await expectLater(save(), throwsStateError);
      expect(await store.reports(), isEmpty);
      store.fail = false;
      final report = await save();
      expect((await store.reports()).single.id, report.id);
      expect(report.delivery, DeliveryState.localOnly);
      expect(report.serverStatus, isNull);
    },
  );
}
