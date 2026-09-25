import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

void main() {
  test(
    '500-record queue rejects overflow without discarding oldest records',
    () async {
      final store = MemoryLocalStore();
      for (var i = 0; i < 500; i++) {
        await store.enqueueTelemetry(OutboxRecord(id: '$i', payload: '{}'));
      }
      await expectLater(
        store.enqueueTelemetry(
          const OutboxRecord(id: 'overflow', payload: '{}'),
        ),
        throwsA(isA<QueueFullException>()),
      );
      expect(await store.telemetryCount(), 500);
      expect((await store.pendingTelemetry()).first.id, '0');
    },
  );
  test('duplicate record IDs are idempotent', () async {
    final store = MemoryLocalStore();
    await store.enqueueTelemetry(
      const OutboxRecord(id: 'same', payload: 'first'),
    );
    await store.enqueueTelemetry(
      const OutboxRecord(id: 'same', payload: 'second'),
    );
    expect(await store.telemetryCount(), 1);
    expect((await store.pendingTelemetry()).single.payload, 'first');
  });
  test('unacknowledged records survive a failed send', () async {
    final store = MemoryLocalStore();
    await store.enqueueTelemetry(const OutboxRecord(id: 'a', payload: '{}'));
    expect(await OutboxSync(store).flush((_) async => false), 0);
    expect(await store.telemetryCount(), 1);
  });
  test(
    'thrown send errors preserve remaining records and release sync lock',
    () async {
      final store = MemoryLocalStore();
      await store.enqueueTelemetry(const OutboxRecord(id: 'a', payload: '{}'));
      final sync = OutboxSync(store);
      await expectLater(
        sync.flush((_) async => throw StateError('offline')),
        throwsStateError,
      );
      expect(await store.telemetryCount(), 1);
      expect(await sync.flush((_) async => true), 1);
      expect(await store.telemetryCount(), 0);
    },
  );
  test('concurrent flushes do not upload the same batch twice', () async {
    final store = MemoryLocalStore();
    await store.enqueueTelemetry(const OutboxRecord(id: 'a', payload: '{}'));
    final gate = Completer<bool>();
    final sync = OutboxSync(store);
    final first = sync.flush((_) => gate.future);
    expect(await sync.flush((_) async => true), 0);
    gate.complete(true);
    expect(await first, 1);
  });
  test('empty and oversized sensor batches are rejected', () {
    expect(() => makeTelemetryChunk('trip', []), throwsArgumentError);
    expect(
      () => makeTelemetryChunk(
        'trip',
        List.generate(21, (_) => <String, Object?>{'x': 1}),
      ),
      throwsArgumentError,
    );
  });
  test('local data clear includes telemetry rows', () async {
    final store = MemoryLocalStore();
    await store.enqueueTelemetry(const OutboxRecord(id: 'a', payload: '{}'));
    await store.clearUserData();
    expect(await store.telemetryCount(), 0);
  });
}
