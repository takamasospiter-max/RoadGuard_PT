import 'package:go_router/go_router.dart';

import '../presentation/pages/register_screen.dart';
import '../presentation/pages/sign_in_screen.dart';
import 'auth_paths.dart';

List<GoRoute> get authRoutes => [
  GoRoute(
    path: AuthPaths.signIn,
    builder: (context, state) => const SignInScreen(),
  ),
  GoRoute(
    path: AuthPaths.register,
    builder: (context, state) => const RegisterScreen(),
  ),
];
