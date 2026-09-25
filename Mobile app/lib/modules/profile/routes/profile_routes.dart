import 'package:go_router/go_router.dart';

import '../presentation/pages/profile_screen.dart';
import 'profile_paths.dart';

List<GoRoute> get profileShellRoutes => [
  GoRoute(
    path: ProfilePaths.profile,
    builder: (context, state) => const ProfileScreen(),
  ),
];

List<GoRoute> get profileRoutes => [
  GoRoute(
    path: ProfilePaths.privacy,
    builder: (context, state) => const PrivacyScreen(),
  ),
  GoRoute(
    path: ProfilePaths.storage,
    builder: (context, state) => const StorageScreen(),
  ),
];
