import 'package:flutter/foundation.dart';

/// The ONE place the app decides where the RoadGuard backend is.
///
/// Every request address is built here: server address + API prefix + path,
/// e.g. `http://127.0.0.1:8000` + `api/v1/` + `graphql/anonymous/`.
/// Both the account client (AuthService) and the road client (RoadApi) use it,
/// so they always agree on the server and on the security rules.

/// The server address, fixed when the app is built:
///   flutter run --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
/// Empty = not configured (the app then shows "not configured" states).
const serverUrl = String.fromEnvironment('ROADGUARD_API_URL');

/// The backend's base path for every endpoint. Must match the backend setting
/// ROADGUARD_API_PREFIX (settings.API_PREFIX, default "api/v1").
const apiPrefix = 'api/v1/';

/// Servers a *debug* build may reach over plain http: this PC through the ADB
/// tunnel (`adb reverse tcp:8000 tcp:8000`). Must match the domains in
/// android/app/src/debug/res/xml/debug_network_security.xml, because Android
/// blocks plain http to any other address anyway. Release builds need https.
const localDebugHosts = ['localhost', '127.0.0.1'];

/// The API base (server address + prefix, ending in "/"), or null when the
/// address is missing or unsafe: not https (except local debug), or carrying
/// credentials, a query or a fragment.
Uri? apiBase(String server) {
  final base = Uri.tryParse(server);
  if (base == null ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    return null;
  }
  final localDebug =
      kDebugMode &&
      base.scheme == 'http' &&
      localDebugHosts.contains(base.host);
  if (base.scheme != 'https' && !localDebug) return null;
  // Keep any path already in the address (e.g. a server behind /roadguard/),
  // then add the API prefix.
  final path = base.path.endsWith('/') ? base.path : '${base.path}/';
  return base.replace(path: '$path$apiPrefix');
}

/// The full address of one API endpoint, or null if the server isn't usable.
/// `path` is relative to the API base, e.g. `graphql/anonymous/`.
Uri? apiUri(String server, String path) =>
    apiBase(server)?.resolve(path.startsWith('/') ? path.substring(1) : path);
