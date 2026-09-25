import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';

final historyProvider = FutureProvider<List<TripRecord>>((ref) async {
  return (await ref.watch(localStoreProvider).trips())
      .where((trip) => !trip.isActive)
      .toList();
});

final tripProvider = NotifierProvider<TripController, TripRecord?>(
  TripController.new,
);

class TripController extends Notifier<TripRecord?> {
  bool _saving = false;
  @override
  TripRecord? build() => ref.read(initialTripProvider);
  Future<void> _persist(TripRecord trip, {bool end = false}) async {
    if (_saving) throw StateError('A trip update is still saving.');
    _saving = true;
    try {
      await ref.read(localStoreProvider).saveTrip(trip);
      state = end ? null : trip;
      ref.invalidate(historyProvider);
    } finally {
      _saving = false;
    }
  }

  Future<void> start(RouteOption route) async {
    if (state != null) {
      throw StateError('Finish or resume your current trip preview first.');
    }
    await _persist(
      TripRecord(id: newLocalId(), route: route, startedAt: DateTime.now()),
    );
  }

  Future<void> togglePause() async {
    final trip = state;
    if (trip == null) return;
    await _persist(trip.copyWith(paused: !trip.paused, simulatedSpeedKmh: 0));
  }

  /// Replace the active trip's route (navigation rerouting after the driver
  /// left the planned route). The trip itself — id, start time, alerts — stays.
  Future<void> reroute(RouteOption route) async {
    final trip = state;
    if (trip == null || trip.endedAt != null) return;
    await _persist(trip.copyWith(route: route));
  }

  Future<void> simulateSpeed(double speed) async {
    final trip = state;
    if (trip == null || !speed.isFinite || speed < 0) return;
    await _persist(trip.copyWith(simulatedSpeedKmh: speed, paused: false));
  }

  Future<void> end() async {
    final trip = state;
    if (trip == null) return;
    await _persist(
      trip.copyWith(endedAt: DateTime.now(), simulatedSpeedKmh: 0),
      end: true,
    );
  }
}
