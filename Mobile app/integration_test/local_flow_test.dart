
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/photos.dart';

// This test code isolates SQLite/preferences and never clears user data or
// interrupted captures. Also pass --no-uninstall to flutter test, or
// --keep-app-running to flutter drive: SDK cleanup otherwise uninstalls the app.

/// A real route with map geometry, as the routing service returns.
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  WidgetController.hitTestWarningShouldBeFatal = true;

  late String databasePath;
  late String settingsKey;
  late LocalStore store;

  setUp(() async {
    databasePath =
        '${await getDatabasesPath()}/roadguard-test-${newLocalId()}.db';
    settingsKey = 'roadguard.integration.${newLocalId()}';
    store = await openLocalStore(databasePath: databasePath);
  });

  tearDown(() async {
    await store.close();
    await deleteDatabase(databasePath);
    await SharedPreferencesAsync().remove(settingsKey);
  });

  testWidgets('native SQLite opens securely and survives close/reopen', (
    tester,
  ) async {
    final sqlite = store as SqliteLocalStore;
    // Regression: Android rejects execute() for this row-returning PRAGMA.
    expect(
      (await sqlite.db.rawQuery('PRAGMA secure_delete'))
          .single['secure_delete'],
      1,
    );
    final now = DateTime.now();
    final photo = testPhoto();
    final report = LocalReport(
      id: 'isolated-report',
      kind: HazardKind.pothole,
      notes: 'Native SQLite roundtrip',
      fix: GpsFix(
        latitude: -6.7924,
        longitude: 39.2083,
        speedMps: 0,
        accuracyMeters: 5,
        observedAt: now,
      ),
      photo: photo,
      createdAt: now,
    );
    const route = _route;
    await store.saveReport(report);
    await store.saveTrip(
      TripRecord(
        id: 'isolated-trip',
        route: route,
        startedAt: now,
        paused: true,
      ),
    );
    await store.enqueueTelemetry(
      const OutboxRecord(id: 'first', payload: '[]'),
    );
    await store.enqueueTelemetry(
      const OutboxRecord(id: 'second', payload: '[]'),
    );

    await store.close();
    store = await openLocalStore(databasePath: databasePath);
    final restored = (await store.reports()).single;
    expect(restored.notes, report.notes);
    expect(restored.photo, orderedEquals(photo));
    expect(restored.delivery, DeliveryState.localOnly);
    expect(restored.serverStatus, isNull);
    expect((await store.trips()).single.paused, isTrue);
    expect((await store.trips()).single.isActive, isTrue);
    expect((await store.pendingTelemetry()).map((record) => record.id), [
      'first',
      'second',
    ]);
    await store.acknowledgeTelemetry('first');
    expect(await store.telemetryCount(), 1);
    await store.deleteReport(report.id);
    expect(await store.reports(), isEmpty);
    // This is the unique test database, never the installed app's database.
    await store.clearUserData();
    expect(await store.trips(), isEmpty);
    expect(await store.telemetryCount(), 0);
  });
}
