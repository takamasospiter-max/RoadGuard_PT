import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'local_data_cipher.dart';

class QueueFullException implements Exception {
  const QueueFullException();
  @override
  String toString() =>
      'The 500-record telemetry buffer is full. Collection must pause; unsent records were preserved.';
}

class OutboxRecord {
  const OutboxRecord({required this.id, required this.payload});
  final String id, payload;
}

abstract interface class LocalStore {
  Future<List<LocalReport>> reports();
  Future<void> saveReport(LocalReport report);
  Future<void> updateReport(LocalReport report);
  Future<void> deleteReport(String id);
  Future<List<TripRecord>> trips();
  Future<void> saveTrip(TripRecord trip);
  Future<List<RouteAlertRecord>> routeAlerts(String ownerKey);
  Future<void> saveRouteAlert(RouteAlertRecord alert);
  Future<int> telemetryCount();
  Future<void> enqueueTelemetry(OutboxRecord record);
  Future<List<OutboxRecord>> pendingTelemetry({int limit = 25});
  Future<void> acknowledgeTelemetry(String id);
  Future<void> clearUserData();
  Future<void> close();
}

Future<LocalStore> openLocalStore({String? databasePath}) async {
  // Browser is a secondary UI preview, not the SRS's native SQLite implementation.
  if (kIsWeb) return MemoryLocalStore();
  final cipher = await LocalDataCipher.load();
  final path = databasePath ?? '${await getDatabasesPath()}/roadguard-v1.db';
  return SqliteLocalStore(
    cipher,
    await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // This PRAGMA returns a row, so Android requires a query call.
        await db.rawQuery('PRAGMA secure_delete = ON');
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE reports (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, payload TEXT NOT NULL, photo BLOB NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE trips (id TEXT PRIMARY KEY, started_at INTEGER NOT NULL, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE telemetry_outbox (sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE route_alerts (id TEXT PRIMARY KEY, owner_key TEXT NOT NULL, received_at INTEGER NOT NULL, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE INDEX route_alerts_owner_time ON route_alerts (owner_key, received_at DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE route_alerts (id TEXT PRIMARY KEY, owner_key TEXT NOT NULL, received_at INTEGER NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX route_alerts_owner_time ON route_alerts (owner_key, received_at DESC)',
          );
        }
      },
      onOpen: (db) async {
        // Encrypt records created by earlier builds before exposing the store.
        for (final table in const [
          'reports',
          'trips',
          'route_alerts',
          'telemetry_outbox',
        ]) {
          final rows = await db.query(
            table,
            columns: ['id', 'payload', if (table == 'reports') 'photo'],
          );
          for (final row in rows) {
            final values = <String, Object?>{
              'payload': await cipher.encryptText(row['payload'] as String),
            };
            if (table == 'reports') {
              values['photo'] = Uint8List.fromList(
                await cipher.encryptBytes(row['photo'] as Uint8List),
              );
            }
            await db.update(
              table,
              values,
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      },
    ),
  );
}

class SqliteLocalStore implements LocalStore {
  SqliteLocalStore(this.cipher, this.db);
  final LocalDataCipher cipher;
  final Database db;
  @override
  Future<List<LocalReport>> reports() async {
    final rows = await db.query('reports', orderBy: 'created_at DESC');
    final reports = <LocalReport>[];
    for (final row in rows) {
      final json =
          jsonDecode(await cipher.decryptText(row['payload'] as String))
              as Map<String, dynamic>;
      // Sample reports from older (demo-capable) builds are never loaded.
      if (LocalReport.isLegacySample(json)) continue;
      reports.add(
        LocalReport.fromJson(
          json,
          Uint8List.fromList(
            await cipher.decryptBytes(row['photo'] as Uint8List),
          ),
        ),
      );
    }
    return reports;
  }

  @override
  Future<void> saveReport(LocalReport report) async {
    await db.insert('reports', {
      'id': report.id,
      'created_at': report.createdAt.millisecondsSinceEpoch,
      'payload': await cipher.encryptText(jsonEncode(report.toJson())),
      'photo': Uint8List.fromList(await cipher.encryptBytes(report.photo)),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> updateReport(LocalReport report) async {
    final count = await db.update(
      'reports',
      {'payload': await cipher.encryptText(jsonEncode(report.toJson()))},
      where: 'id = ?',
      whereArgs: [report.id],
    );
    if (count != 1) throw StateError('Report no longer exists on this device.');
  }

  @override
  Future<void> deleteReport(String id) async {
    await db.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<TripRecord>> trips() async => Future.wait(
    (await db.query('trips', orderBy: 'started_at DESC')).map(
      (row) async => TripRecord.fromJson(
        jsonDecode(await cipher.decryptText(row['payload'] as String))
            as Map<String, dynamic>,
      ),
    ),
  );
  @override
  Future<void> saveTrip(TripRecord trip) async {
    await db.insert('trips', {
      'id': trip.id,
      'started_at': trip.startedAt.millisecondsSinceEpoch,
      'payload': await cipher.encryptText(jsonEncode(trip.toJson())),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RouteAlertRecord>> routeAlerts(String ownerKey) async {
    final rows = await db.query(
      'route_alerts',
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
      orderBy: 'received_at DESC',
    );
    final alerts = <RouteAlertRecord>[];
    for (final row in rows) {
      final json =
          jsonDecode(await cipher.decryptText(row['payload'] as String))
              as Map<String, dynamic>;
      // Sample alerts from older (demo-capable) builds are never loaded.
      if (RouteAlertRecord.isLegacySample(json)) continue;
      alerts.add(RouteAlertRecord.fromJson(json));
    }
    return alerts;
  }
  @override
  Future<void> saveRouteAlert(RouteAlertRecord alert) async {
    await db.insert('route_alerts', {
      'id': alert.id,
      'owner_key': alert.ownerKey,
      'received_at': alert.receivedAt.millisecondsSinceEpoch,
      'payload': await cipher.encryptText(jsonEncode(alert.toJson())),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<int> telemetryCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM telemetry_outbox'),
      ) ??
      0;
  @override
  Future<void> enqueueTelemetry(OutboxRecord record) async {
    final payload = await cipher.encryptText(record.payload);
    return db.transaction((txn) async {
      final existing = await txn.query(
        'telemetry_outbox',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [record.id],
      );
      if (existing.isNotEmpty) return;
      final count =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM telemetry_outbox'),
          ) ??
          0;
      if (count >= 500) throw const QueueFullException();
      await txn.insert('telemetry_outbox', {
        'id': record.id,
        'payload': payload,
      });
    });
  }

  @override
  Future<List<OutboxRecord>> pendingTelemetry({int limit = 25}) async =>
      Future.wait(
        (await db.query(
          'telemetry_outbox',
          orderBy: 'sequence ASC',
          limit: limit,
        )).map(
          (row) async => OutboxRecord(
            id: row['id'] as String,
            payload: await cipher.decryptText(row['payload'] as String),
          ),
        ),
      );
  @override
  Future<void> acknowledgeTelemetry(String id) async {
    await db.delete('telemetry_outbox', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearUserData() => db.transaction((txn) async {
    await txn.delete('reports');
    await txn.delete('trips');
    await txn.delete('route_alerts');
    await txn.delete('telemetry_outbox');
  });
  @override
  Future<void> close() => db.close();
}

/// Used for widget tests and the non-persistent browser preview ONLY.
class MemoryLocalStore implements LocalStore {
  final Map<String, LocalReport> _reports = {};
  final Map<String, TripRecord> _trips = {};
  final Map<String, RouteAlertRecord> _routeAlerts = {};
  final LinkedHashMap<String, OutboxRecord> _outbox = LinkedHashMap();
  @override
  Future<List<LocalReport>> reports() async =>
      _reports.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  @override
  Future<void> saveReport(LocalReport report) async {
    if (_reports.containsKey(report.id)) {
      throw StateError('This draft is already saved.');
    }
    _reports[report.id] = report;
  }

  @override
  Future<void> updateReport(LocalReport report) async {
    if (!_reports.containsKey(report.id)) {
      throw StateError('Report no longer exists.');
    }
    _reports[report.id] = report;
  }

  @override
  Future<void> deleteReport(String id) async {
    _reports.remove(id);
  }

  @override
  Future<List<TripRecord>> trips() async =>
      _trips.values.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  @override
  Future<void> saveTrip(TripRecord trip) async {
    _trips[trip.id] = trip;
  }

  @override
  Future<List<RouteAlertRecord>> routeAlerts(String ownerKey) async =>
      _routeAlerts.values.where((alert) => alert.ownerKey == ownerKey).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  @override
  Future<void> saveRouteAlert(RouteAlertRecord alert) async {
    _routeAlerts.putIfAbsent(alert.id, () => alert);
  }

  @override
  Future<int> telemetryCount() async => _outbox.length;
  @override
  Future<void> enqueueTelemetry(OutboxRecord record) async {
    if (_outbox.containsKey(record.id)) return;
    if (_outbox.length >= 500) throw const QueueFullException();
    _outbox[record.id] = record;
  }

  @override
  Future<List<OutboxRecord>> pendingTelemetry({int limit = 25}) async =>
      _outbox.values.take(limit).toList();
  @override
  Future<void> acknowledgeTelemetry(String id) async {
    _outbox.remove(id);
  }

  @override
  Future<void> clearUserData() async {
    _reports.clear();
    _trips.clear();
    _routeAlerts.clear();
    _outbox.clear();
  }

  @override
  Future<void> close() async {}
}
