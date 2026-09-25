import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';

/// The queue is scoped to the currently signed-in traveler or the guest
/// profile on this device. It contains only warnings delivered in a trip.
final routeAlertsProvider = FutureProvider.autoDispose.family<List<RouteAlertRecord>, String>(
  (ref, ownerKey) => ref.read(localStoreProvider).routeAlerts(ownerKey),
);

final routeAlertTripsProvider = FutureProvider.autoDispose<List<TripRecord>>(
  (ref) => ref.read(localStoreProvider).trips(),
);
