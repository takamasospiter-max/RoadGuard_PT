import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class Traveler {
  const Traveler({required this.id, required this.name, required this.email});
  final String id, name, email;

  factory Traveler.fromJson(Map<String, dynamic> value) => Traveler(
    id: value['id'] as String,
    name: value['name'] as String,
    email: value['email'] as String,
  );
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

abstract interface class SessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage({this.key = 'roadguard.traveler.session.v1'});
  static const _storage = FlutterSecureStorage();
  final String key;
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: key);
}

/// Passwords are sent once to Django and are never persisted. Anonymous report
/// and map clients are independent and never receive this token.
class AuthService {
  AuthService({
    required this.baseUrl,
    required this.storage,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final SessionStorage storage;
  final http.Client _client;
  String? _token;
  bool get configured => baseUrl.isNotEmpty;

  /// Full address of an account endpoint (see core/config/api_config.dart).
  /// A bare name ("login") is an auth endpoint: mobile/auth/login/.
  Uri _endpoint(String path) =>
      apiUri(baseUrl, path.contains('/') ? path : 'mobile/auth/$path/') ??
      (throw const AuthFailure('Account connection is not configured.'));

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final url = _endpoint(path);
    try {
      final request = http.Request(body == null ? 'GET' : 'POST', url)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 12));
      if (response.bodyBytes.length > 32768) throw const FormatException();
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthFailure(
          payload['error'] is String
              ? payload['error'] as String
              : 'Unable to complete sign-in. Please try again.',
          status: response.statusCode,
        );
      }
      return payload;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'The server is taking too long. Please try again.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Cannot reach account services. Check your connection and try again.',
      );
    }
  }

  Future<Traveler?> restore() async {
    if (!configured) return null;
    final raw = await storage.read();
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      // Never send a saved token to a newly configured server.
      if (saved['origin'] != baseUrl) return null;
      _token = saved['token'] as String;
    } catch (_) {
      await storage.clear();
      return null;
    }
    try {
      final payload = await _request('session', token: _token);
      return Traveler.fromJson(payload['user'] as Map<String, dynamic>);
    } on AuthFailure catch (error) {
      if (error.status != 401) rethrow;
      _token = null;
      await storage.clear();
      return null;
    }
  }

  Future<Traveler> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    final payload = await _request(
      name == null ? 'login' : 'register',
      body: {
        'email': email.trim(),
        'password': password,
        if (name != null) 'name': name.trim(),
      },
    );
    final traveler = Traveler.fromJson(payload['user'] as Map<String, dynamic>);
    final token = payload['token'] as String;
    try {
      await storage.write(jsonEncode({'origin': baseUrl, 'token': token}));
    } catch (_) {
      try {
        await _request('logout', body: {}, token: token);
      } catch (_) {
        // Never use an unpersisted session. The server token also expires.
      }
      throw const AuthFailure(
        'We could not securely save your session. Please sign in again.',
      );
    }
    _token = token;
    return traveler;
  }

  Future<void> signOut() async {
    // A failed revocation must not leave the traveler signed in on this device.
    try {
      if (_token != null) {
        try {
          await _request('logout', body: {}, token: _token);
        } on AuthFailure {
          // The server session expires independently; clear the local session.
        }
      }
    } finally {
      await storage.clear();
      _token = null;
    }
  }

  void dispose() => _client.close();

  Future<Map<String, dynamic>> mobileGraphql(
    String document,
    Map<String, Object?> variables,
  ) async {
    if (_token == null) {
      throw const AuthFailure(
        'Sign in before sharing sensor data.',
        status: 401,
      );
    }
    final result = await _request(
      'graphql/mobile/',
      token: _token,
      body: {'query': document, 'variables': variables},
    );
    if (result['errors'] case final List errors when errors.isNotEmpty) {
      throw const AuthFailure(
        'Sensor sharing was rejected. Consent or your session may have expired.',
      );
    }
    return result['data'] as Map<String, dynamic>;
  }
}
