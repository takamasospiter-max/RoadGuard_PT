import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';

class MemorySessionStorage implements SessionStorage {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    if (failWrite) throw StateError('storage unavailable');
    value = text;
  }

  @override
  Future<void> clear() async => value = null;
}

AuthService testAuthService({
  MemorySessionStorage? storage,
  List<http.Request>? requests,
}) {
  return AuthService(
    baseUrl: testAuthBaseUrl,
    storage: storage ?? MemorySessionStorage(),
    client: MockClient((request) async {
      requests?.add(request);
      if (request.url.path.endsWith('/logout/')) {
        return http.Response('{"ok":true}', 200);
      }
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] == 'wrong-password') {
        return http.Response(
          '{"error":"Email or password is incorrect."}',
          401,
        );
      }
      return http.Response(
        jsonEncode({
          'token': 'test-token-never-used-outside-tests',
          'user': {
            'id': 'test-traveler',
            'name': body['name'] ?? 'Example Traveler',
            'email': body['email'] ?? 'traveler@example.test',
          },
        }),
        request.url.path.endsWith('/register/') ? 201 : 200,
      );
    }),
  );
}

/// Base URL used by [testAuthService].
const testAuthBaseUrl = 'https://accounts.example.test';

/// An [AuthService] that starts already signed in as "Example Traveler".
///
/// The app requires sign-in before any screen after onboarding (see
/// core/routes/app_router.dart), so widget tests of Explore, Reports, Profile,
/// trips, etc. use this: on launch the app restores the saved session from
/// storage and confirms it with the (fake) server, exactly like a real
/// returning traveller, then opens Explore.
AuthService signedInAuthService({List<http.Request>? requests}) =>
    testAuthService(storage: signedInSessionStorage(), requests: requests);

/// Session storage already holding a saved "Example Traveler" session.
MemorySessionStorage signedInSessionStorage() => MemorySessionStorage()
  ..value = jsonEncode({
    'origin': testAuthBaseUrl,
    'token': 'test-token-never-used-outside-tests',
  });
