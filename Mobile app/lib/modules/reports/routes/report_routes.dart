import 'package:go_router/go_router.dart';

import '../presentation/pages/report_screen.dart';
import '../presentation/pages/reports_screen.dart';
import 'report_paths.dart';

List<GoRoute> get reportShellRoutes => [
  GoRoute(
    path: ReportPaths.reports,
    builder: (context, state) => const ReportsScreen(),
  ),
];

List<GoRoute> get reportRoutes => [
  GoRoute(
    path: ReportPaths.create,
    builder: (context, state) => const ReportScreen(),
  ),
  GoRoute(
    path: ReportPaths.detail,
    builder: (context, state) =>
        ReportDetailScreen(id: state.pathParameters['id']!),
  ),
];
