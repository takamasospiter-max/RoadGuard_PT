import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/auth/routes/auth_routes.dart';
import '../../modules/auth/presentation/providers/auth_provider.dart';
import '../../modules/boarding/routes/boarding_routes.dart';
import '../../modules/home/presentation/pages/home_page.dart';
import '../../modules/home/routes/home_routes.dart';
import '../../modules/planner/routes/planner_routes.dart';
import '../../modules/profile/presentation/providers/settings_provider.dart';
import '../../modules/profile/routes/profile_routes.dart';
import '../../modules/reports/routes/report_routes.dart';
import '../../modules/trips/routes/trip_routes.dart';
import '../../shared/widgets/common.dart';
import 'route_paths.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(settingsProvider, (_, next) {
    refresh.value++;
  });
  ref.listen(authProvider, (_, next) {
    refresh.value++;
  });
  final router = GoRouter(
    // First launch starts onboarding. Returning users restore auth before Explore.
    initialLocation: ref.read(settingsProvider).onboardingComplete
        ? AuthPaths.signIn
        : BoardingPaths.welcome,
    refreshListenable: refresh,
    redirect: (context, state) {
      final complete = ref.read(settingsProvider).onboardingComplete;
      final path = state.uri.path;
      final account = ref.read(authProvider);
      final signedIn = account.asData?.value != null;
      final isBoarding =
          path == BoardingPaths.welcome ||
          path == BoardingPaths.onboarding ||
          path == BoardingPaths.permissions;
      final isAuth = path == AuthPaths.signIn || path == AuthPaths.register;

      if (!complete) {
        if (!isBoarding && !isAuth) return BoardingPaths.welcome;
        return null;
      }

      if (signedIn) return isBoarding || isAuth ? HomePaths.explore : null;
      if (!isAuth) return AuthPaths.signIn;
      return null;
    },
    errorBuilder: (context, state) => DetailScaffold(
      title: 'Page not found',
      child: EmptyView(
        icon: Icons.explore_off_outlined,
        title: 'Let’s get you back on track.',
        message: 'That page is not available.',
        action: 'Go to Explore',
        onAction: () => context.go(HomePaths.explore),
      ),
    ),
    routes: [
      ...authRoutes,
      ...boardingRoutes,
      ShellRoute(
        builder: (context, state, child) =>
            HomePage(path: state.uri.path, child: child),
        routes: [
          ...homeRoutes,
          ...tripShellRoutes,
          ...reportShellRoutes,
          ...profileShellRoutes,
        ],
      ),
      ...plannerRoutes,
      ...tripRoutes,
      ...hazardRoutes,
      ...reportRoutes,
      ...profileRoutes,
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
