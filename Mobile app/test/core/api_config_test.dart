import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/config/api_config.dart';

// Every request address is server address + API prefix + path (api_config.dart).
void main() {
  test('builds every endpoint under the one API base', () {
    expect(
      apiBase('https://roadguard.example.test').toString(),
      'https://roadguard.example.test/api/v1/',
    );
    expect(
      apiUri('https://roadguard.example.test', 'graphql/anonymous/').toString(),
      'https://roadguard.example.test/api/v1/graphql/anonymous/',
    );
    // A leading "/" doesn't escape the prefix.
    expect(
      apiUri(
        'https://roadguard.example.test/',
        '/mobile/auth/login/',
      ).toString(),
      'https://roadguard.example.test/api/v1/mobile/auth/login/',
    );
    // A server hosted under a sub-path keeps it.
    expect(
      apiUri('https://example.test/roadguard', 'health/').toString(),
      'https://example.test/roadguard/api/v1/health/',
    );
  });

  test('local debug server over plain http is allowed, others are not', () {
    // Tests run in debug mode, like `flutter run`.
    expect(
      apiBase('http://127.0.0.1:8000').toString(),
      'http://127.0.0.1:8000/api/v1/',
    );
    expect(apiBase('http://localhost:8000'), isNotNull);
    expect(
      apiBase('http://192.168.1.142:8000'),
      isNull,
    ); // Android blocks it anyway
    expect(apiBase('http://example.test'), isNull);
    expect(apiBase('https://user:pw@example.test'), isNull);
    expect(apiBase('https://example.test?x=1'), isNull);
    expect(apiBase(''), isNull);
  });
}
