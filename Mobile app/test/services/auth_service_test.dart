import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';

import '../support/auth.dart';

void main() {
  test('register sends actual fields without identity and keeps only token in protected storage', () async {
    final storage = MemorySessionStorage();
    final requests = <http.Request>[];
    final service = testAuthService(storage: storage, requests: requests);
    addTearDown(service.dispose);
    final user = await service.authenticate(
      email: ' traveler@example.test ',
      password: 'private-password',
      name: 'Traveler',
    );
    expect(user.name, 'Traveler');
    expect(requests.single.url.path, '/api/v1/mobile/auth/register/');
    expect(requests.single.followRedirects, isFalse);
    expect(requests.single.headers.containsKey('Authorization'), isFalse);
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
    expect(jsonDecode(requests.single.body)['email'], 'traveler@example.test');
    expect(storage.value, isNot(contains('private-password')));
    expect(storage.value, isNot(contains('traveler@example.test')));
    await service.signOut();
    expect(requests.last.url.path, '/api/v1/mobile/auth/logout/');
    expect(requests.last.headers['Authorization'], startsWith('Bearer '));
    expect(storage.value, isNull);
  });

  test(
    'session restore checks server and expiry removes invalid token',
    () async {
      final storage = MemorySessionStorage()
        ..value = jsonEncode({
          'origin': 'https://accounts.example.test',
          'token': 'expired-token',
        });
      final service = AuthService(
        baseUrl: 'https://accounts.example.test',
        storage: storage,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/mobile/auth/session/');
          expect(request.headers['Authorization'], 'Bearer expired-token');
          return http.Response('{"error":"Expired"}', 401);
        }),
      );
      addTearDown(service.dispose);
      expect(await service.restore(), isNull);
      expect(storage.value, isNull);
    },
  );

  test(
    'offline restore retains secure token for retry without authenticating',
    () async {
      final storage = MemorySessionStorage()
        ..value = jsonEncode({
          'origin': 'https://accounts.example.test',
          'token': 'stored-token',
        });
      final service = AuthService(
        baseUrl: 'https://accounts.example.test',
        storage: storage,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      addTearDown(service.dispose);
      await expectLater(service.restore(), throwsA(isA<AuthFailure>()));
      expect(storage.value, contains('stored-token'));
    },
  );

  test('tokens are never restored to another API origin', () async {
    final storage = MemorySessionStorage()
      ..value = jsonEncode({
        'origin': 'https://old.example.test',
        'token': 'old-token',
      });
    final service = AuthService(
      baseUrl: 'https://new.example.test',
      storage: storage,
      client: MockClient(
        (_) async => throw StateError('Must not send a request'),
      ),
    );
    addTearDown(service.dispose);
    expect(await service.restore(), isNull);
  });

  test(
    'secure storage failure revokes the new session and fails authentication',
    () async {
      final storage = MemorySessionStorage()..failWrite = true;
      final requests = <http.Request>[];
      final service = testAuthService(storage: storage, requests: requests);
      addTearDown(service.dispose);
      await expectLater(
        service.authenticate(
          email: 'test@example.test',
          password: 'private-password',
        ),
        throwsA(isA<AuthFailure>()),
      );
      expect(requests.last.url.path, '/api/v1/mobile/auth/logout/');
      expect(storage.value, isNull);
    },
  );

  test(
    'nonlocal cleartext credentials are rejected before a network request',
    () async {
      final service = AuthService(
        baseUrl: 'http://example.test',
        storage: MemorySessionStorage(),
        client: MockClient(
          (_) async => throw StateError('Must not send credentials'),
        ),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.authenticate(
          email: 'test@example.test',
          password: 'private-password',
        ),
        throwsA(isA<AuthFailure>()),
      );
    },
  );
}
