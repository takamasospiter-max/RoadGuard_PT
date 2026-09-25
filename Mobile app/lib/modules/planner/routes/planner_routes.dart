import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/services/road_api.dart';

import '../presentation/pages/planner_screen.dart';
import 'planner_paths.dart';

List<GoRoute> get plannerRoutes => [
  GoRoute(
    path: PlannerPaths.plan,
    builder: (context, state) => PlannerScreen(destination: state.extra is PlaceResult ? state.extra as PlaceResult : null),
  ),
];
