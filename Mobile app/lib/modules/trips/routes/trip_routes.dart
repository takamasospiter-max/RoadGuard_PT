import 'package:go_router/go_router.dart';

import '../presentation/pages/active_trip_screen.dart';
import '../presentation/pages/trips_screen.dart';
import 'trip_paths.dart';

List<GoRoute> get tripShellRoutes => [
  GoRoute(
    path: TripPaths.history,
    builder: (context, state) => const TripsScreen(),
  ),
];

List<GoRoute> get tripRoutes => [
  GoRoute(
    path: TripPaths.active,
    builder: (context, state) => const ActiveTripScreen(),
  ),
];
