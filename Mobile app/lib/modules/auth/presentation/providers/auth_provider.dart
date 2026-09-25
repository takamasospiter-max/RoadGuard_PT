import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';
import 'package:roadguard_ai/core/config/api_config.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(
    baseUrl: serverUrl,
    storage: const SecureSessionStorage(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final authProvider = AsyncNotifierProvider<AuthController, Traveler?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<Traveler?> {
  @override
  Future<Traveler?> build() => ref.watch(authServiceProvider).restore();

  Future<void> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    // Finish restoration before a new login so an older session response
    // cannot overwrite the identity returned by this request.
    try {
      await future;
    } catch (_) {
      // A failed restore must still allow the traveler to sign in again.
    }
    state = const AsyncLoading();
    try {
      final user = await ref
          .read(authServiceProvider)
          .authenticate(email: email, password: password, name: name);
      state = AsyncData(user);
    } catch (_) {
      state = const AsyncData(null);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    state = const AsyncData(null);
  }
}
