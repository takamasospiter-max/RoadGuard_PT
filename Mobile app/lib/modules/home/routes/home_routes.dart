import 'package:go_router/go_router.dart';

import '../presentation/pages/explore_screen.dart';
import 'home_paths.dart';

List<GoRoute> get homeRoutes => [
  GoRoute(
    path: HomePaths.explore,
    builder: (context, state) => const ExploreScreen(),
  ),
  GoRoute(
    path: HomePaths.alerts,
    builder: (context, state) => const AlertsScreen(),
  ),
];

List<GoRoute> get hazardRoutes => [
  GoRoute(
    path: HomePaths.hazards,
    builder: (context, state) => const HazardsScreen(),
  ),
  GoRoute(
    path: HomePaths.hazard,
    builder: (context, state) =>
        HazardDetailScreen(id: state.pathParameters['id']!),
  ),
];
