import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/models/safety_policy.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';

final reportsProvider = FutureProvider<List<LocalReport>>(
  (ref) => ref.watch(localStoreProvider).reports(),
);

final locationStreamProvider = StreamProvider.autoDispose<GpsFix>(
  (ref) => ref.watch(locationServiceProvider).watch(),
);
final clockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

final reportWriterProvider = Provider<ReportWriter>((ref) => ReportWriter(ref));

class ReportWriter {
  ReportWriter(this.ref);
  final Ref ref;
  bool _saving = false;
  Future<LocalReport> save({
    required HazardKind kind,
    required String notes,
    required GpsFix? fix,
    required Uint8List? photo,
  }) async {
    if (_saving) throw StateError('Your report is already saving.');
    if (notes.trim().length > 500) {
      throw ArgumentError('Keep the description to 500 characters.');
    }
    if (photo == null || photo.isEmpty) {
      throw ArgumentError('Add one confirmation photo before saving.');
    }
    final now = DateTime.now();
    final gate = ref.read(safetyPolicyProvider).evaluate(fix, now);
    if (!gate.allowed) throw StateError(gate.title);
    _saving = true;
    try {
      final report = LocalReport(
        id: newLocalId(),
        kind: kind,
        notes: notes.trim(),
        fix: fix!,
        photo: photo,
        createdAt: now,
      );
      await ref.read(localStoreProvider).saveReport(report);
      ref.invalidate(reportsProvider);
      return report;
    } finally {
      _saving = false;
    }
  }

  Future<void> delete(String id) async {
    await ref.read(localStoreProvider).deleteReport(id);
    ref.invalidate(reportsProvider);
  }
}
