import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../models/safety_policy.dart';
import '../storage/local_store.dart';
import '../injection/service_providers.dart';
import '../config/api_config.dart';

final roadApiProvider = Provider<RoadApi>((ref) {
  final api = RoadApi(serverUrl);
  ref.onDispose(api.dispose);
  return api;
});

class RoadApi {
  RoadApi(this.baseUrl, {http.Client? client})
    : client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  bool get configured => baseUrl.isNotEmpty;

  /// Full address of a road-service endpoint (see core/config/api_config.dart).
  Uri endpoint(String path) =>
      apiUri(baseUrl, path) ??
      (throw StateError('The road service is not configured securely.'));

  Future<Map<String, dynamic>> send(http.BaseRequest request) async {
    request.followRedirects = false;
    // This client never receives a token or cookies, even when signed in.
    request.headers['Accept'] = 'application/json';
    try {
      final response = await (() async {
        final stream = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 2000000) throw const FormatException();
        }
        if (stream.statusCode < 200 || stream.statusCode >= 300) {
          throw StateError(
            'Road service request failed (HTTP ${stream.statusCode}). Your local data is preserved.',
          );
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 20));
      return response;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'Cannot reach road services. Check your connection and retry.',
      );
    }
  }

  Future<Map<String, dynamic>> query(
    String document,
    Map<String, Object?> variables,
  ) async {
    final request = http.Request('POST', endpoint('graphql/anonymous/'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'query': document, 'variables': variables});
    final payload = await send(request);
    final errors = payload['errors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      final message = (errors.first as Map)['message'];
      throw StateError(
        message is String ? message : 'The server rejected the request.',
      );
    }
    return payload['data'] as Map<String, dynamic>;
  }

  Future<String> uploadPhoto(LocalReport report) async {
    if (report.fix.isMocked) {
      throw StateError(
        'Reports recorded with simulated GPS cannot be uploaded.',
      );
    }
    final request =
        http.MultipartRequest('POST', endpoint('anonymous/report-photos/'))
          ..files.add(
            http.MultipartFile.fromBytes(
              'photo',
              report.photo,
              filename: 'report.jpg',
            ),
          );
    final result = await send(request);
    final token = result['photoToken'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw StateError('Invalid photo acknowledgement.');
    }
    return token;
  }

  Future<Map<String, dynamic>> submit(LocalReport report) async =>
      (await query(
            r'''
    mutation Submit($input: AnonymousReportInput!) {
      submitAnonymousReport(input:$input) { id clientId status receivedAt }
    }''',
            {
              'input': {
                'clientId': report.id,
                'category': report.kind.name.toUpperCase(),
                'notes': report.notes,
                ...report.fix.toJson(),
                'recordedAt': report.createdAt.toUtc().toIso8601String(),
                // Required by the server's schema; this app only sends real reports.
                'isDemo': false,
                'photoToken': report.photoToken,
              },
            },
          ))['submitAnonymousReport']
          as Map<String, dynamic>;

  Future<List<PublicHazard>> hazards(Map<String, double> bbox) async {
    final data = await query(
      r'''query Hazards($bbox:BboxInput!) {
      publicHazards(bbox:$bbox,first:100) { id category severity latitude longitude confirmedAt updatedAt verification deviceCount }
    }''',
      {'bbox': bbox},
    );
    return (data['publicHazards'] as List)
        .map((j) => PublicHazard.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<PlaceResult>> searchPlaces(String text) async {
    final data = await query(
      r'query Places($query:String!) { searchPlaces(query:$query) { label latitude longitude } }',
      {'query': text},
    );
    return (data['searchPlaces'] as List)
        .map(
          (j) => PlaceResult(
            label: j['label'] as String,
            latitude: (j['latitude'] as num).toDouble(),
            longitude: (j['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<RouteOption>> routes(
    List<double> origin,
    List<double> destination, {
    String? originLabel,
    String? destinationLabel,
  }) async {
    final data = await query(
      r'''query Routes($origin:CoordinateInput!,$destination:CoordinateInput!) {
      drivingRoutes(origin:$origin,destination:$destination) { id distanceMeters durationSeconds coordinatesJson stepsJson computedAt provider }
    }''',
      {
        'origin': {'longitude': origin[0], 'latitude': origin[1]},
        'destination': {
          'longitude': destination[0],
          'latitude': destination[1],
        },
      },
    );
    return (data['drivingRoutes'] as List)
        .map(
          (j) => RouteOption(
            id: j['id'] as String,
            origin: originLabel ?? 'Selected starting point',
            destination: destinationLabel ?? 'Selected destination',
            road: j['provider'] as String,
            kilometers: (j['distanceMeters'] as num).toDouble() / 1000,
            minutes: ((j['durationSeconds'] as num) / 60).ceil(),
            hazardIds: const [],
            coordinates: (jsonDecode(j['coordinatesJson'] as String) as List)
                .map(
                  (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
                )
                .toList(),
            computedAt: DateTime.parse(j['computedAt'] as String),
            // Turn-by-turn manoeuvres for navigation guidance.
            steps: (jsonDecode(j['stepsJson'] as String? ?? '[]') as List)
                .map(
                  (s) => RouteStep.fromJson((s as Map).cast<String, dynamic>()),
                )
                .toList(),
          ),
        )
        .toList();
  }

  void dispose() => client.close();
}

class PublicHazard {
  PublicHazard.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      kind = HazardKind.values.byName(
        (value['category'] as String).toLowerCase(),
      ),
      latitude = (value['latitude'] as num).toDouble(),
      longitude = (value['longitude'] as num).toDouble(),
      severity = value['severity'] as String?,
      updatedAt = DateTime.parse(value['updatedAt'] as String),
      // CONFIRMED = an officer verified it; CROWD_REPORTED = several phones
      // detected it but no officer has checked yet. Older servers didn't send
      // this and only published confirmed hazards.
      confirmedByOfficer =
          (value['verification'] as String? ?? 'CONFIRMED') == 'CONFIRMED',
      deviceCount = (value['deviceCount'] as num?)?.toInt() ?? 0;
  final String id;
  final HazardKind kind;
  final double latitude, longitude;
  final String? severity;
  final DateTime updatedAt;
  final bool confirmedByOfficer;
  final int deviceCount;
}

final reportUploaderProvider = Provider<ReportUploader>(
  (ref) =>
      ReportUploader(ref.read(roadApiProvider), ref.read(localStoreProvider)),
);

class ReportUploader {
  ReportUploader(this.api, this.store);
  final RoadApi api;
  final LocalStore store;
  final _pending = <String>{};
  Future<void> upload(String id) async {
    if (!_pending.add(id)) {
      throw StateError('This report is already uploading.');
    }
    try {
      var report = (await store.reports()).firstWhere((r) => r.id == id);
      if (!const SafetyPolicy()
          .evaluate(report.fix, report.createdAt)
          .allowed) {
        throw StateError(
          'Only genuine, safely recorded reports can be uploaded.',
        );
      }
      if (report.delivery == DeliveryState.submitted) return;
      final origin = api.endpoint('').origin;
      if (report.uploadOrigin != null && report.uploadOrigin != origin) {
        throw StateError(
          'This upload belongs to a different server. Restore the original server to retry.',
        );
      }
      report = report.withDelivery(
        delivery: DeliveryState.queued,
        uploadOrigin: origin,
      );
      await store.updateReport(report);
      if (report.photoToken == null) {
        report = report.withDelivery(photoToken: await api.uploadPhoto(report));
        // Persist before submission so lost ACKs retry the identical payload.
        await store.updateReport(report);
      }
      Map<String, dynamic> ack;
      try {
        ack = await api.submit(report);
      } on StateError catch (error) {
        // Only an explicit expired, unclaimed photo response permits replacing
        // the token. An accepted report retries its original token even later.
        if (!error.message.toString().contains('Photo token has expired.')) {
          rethrow;
        }
        report = report.withDelivery(photoToken: await api.uploadPhoto(report));
        await store.updateReport(report);
        ack = await api.submit(report);
      }
      if ((ack['clientId'] as String).replaceAll('-', '') !=
              report.id.replaceAll('-', '') ||
          !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(ack['id'] as String)) {
        throw StateError(
          'The server acknowledgement did not match this report.',
        );
      }
      final status = switch (ack['status']) {
        'NEW' => HazardStatus.fresh,
        'UNDER_VERIFICATION' => HazardStatus.underVerification,
        'CONFIRMED' => HazardStatus.confirmed,
        'RESOLVED' => HazardStatus.resolved,
        'EXPIRED' => HazardStatus.expired,
        _ => throw StateError('Unknown server status.'),
      };
      await store.updateReport(
        report.withDelivery(
          delivery: DeliveryState.submitted,
          serverId: ack['id'] as String,
          serverStatus: status,
          receivedAt: DateTime.parse(ack['receivedAt'] as String),
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }
}

class PlaceResult {
  const PlaceResult({
    required this.label,
    required this.latitude,
    required this.longitude,
  });
  final String label;
  final double latitude, longitude;
  List<double> get coordinates => [longitude, latitude];
}
