import 'package:go_router/go_router.dart';

import '../presentation/pages/onboarding_screen.dart';
import '../presentation/pages/permissions_screen.dart';
import '../presentation/pages/welcome_screen.dart';
import 'boarding_paths.dart';

List<GoRoute> get boardingRoutes => [
  GoRoute(
    path: BoardingPaths.welcome,
    builder: (context, state) => const WelcomeScreen(),
  ),
  GoRoute(
    path: BoardingPaths.onboarding,
    builder: (context, state) => const OnboardingScreen(),
  ),
  GoRoute(
    path: BoardingPaths.permissions,
    builder: (context, state) => const PermissionsScreen(),
  ),
];
