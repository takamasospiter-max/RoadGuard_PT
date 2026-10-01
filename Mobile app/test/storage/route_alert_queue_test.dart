import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

void main() {
  test(
    'received warnings are idempotent, newest first and scoped to a traveler',
    () async {
      final store = MemoryLocalStore();
      final time = DateTime.now();
      RouteAlertRecord alert(String id, String owner, DateTime when) =>
          RouteAlertRecord(
            id: id,
            tripId: 'trip-1',
            ownerKey: owner,
            hazardId: id,
            kind: HazardKind.pothole,
            distanceMeters: 120,
            receivedAt: when,
          );
      await store.saveRouteAlert(
        alert('older', 'guest', time.subtract(const Duration(minutes: 1))),
      );
      await store.saveRouteAlert(alert('newer', 'guest', time));
      await store.saveRouteAlert(alert('newer', 'guest', time));
      await store.saveRouteAlert(alert('other', 'account-1', time));
      expect((await store.routeAlerts('guest')).map((entry) => entry.id), [
        'newer',
        'older',
      ]);
      expect(
        RouteAlertRecord.fromJson(alert('newer', 'guest', time).toJson())
            .distanceMeters,
        120,
      );
      expect((await store.routeAlerts('account-1')).single.id, 'other');
      await store.clearUserData();
      expect(await store.routeAlerts('guest'), isEmpty);
    },
  );

  test('sample records saved by older demo-capable builds are recognised and skipped', () {
    // SqliteLocalStore skips rows these helpers flag, so old sample data can
    // never appear, or be uploaded, as real.
    expect(RouteAlertRecord.isLegacySample({'isDemo': true}), isTrue);
    expect(RouteAlertRecord.isLegacySample({'isDemo': false}), isFalse);
    expect(RouteAlertRecord.isLegacySample({}), isFalse);
    expect(LocalReport.isLegacySample({'isDemo': true}), isTrue);
    expect(LocalReport.isLegacySample({}), isFalse);
  });
}
