import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';

LocalReport report({bool mocked = false}) {
  final now = DateTime.now();
  return LocalReport(
    id: '00112233445566778899aabbccddeeff',
    kind: HazardKind.pothole,
    notes: 'Test evidence',
    fix: GpsFix(
      latitude: -6.8,
      longitude: 39.25,
      speedMps: 0,
      accuracyMeters: 5,
      observedAt: now,
      isMocked: mocked,
    ),
    photo: Uint8List.fromList([1, 2, 3]),
    createdAt: now,
  );
}

String acknowledgement({String id = '00112233-4455-6677-8899-aabbccddeeff'}) =>
    jsonEncode({
      'data': {
        'submitAnonymousReport': {
          'id': 'a0112233-4455-6677-8899-aabbccddeeff',
          'clientId': id,
          'status': 'NEW',
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        },
      },
    });

void main() {
  test(
    'lost ACK preserves token and client ID; retry records real server status',
    () async {
      final store = MemoryLocalStore();
      await store.saveReport(report());
      var photoCalls = 0, submits = 0;
      final payloads = <Map<String, dynamic>>[];
      final api = RoadApi(
        'https://roadguard.example.test',
        client: MockClient((r) async {
          expect(r.headers.containsKey('Authorization'), isFalse);
          expect(r.headers.containsKey('Cookie'), isFalse);
          expect(r.followRedirects, isFalse);
          if (r.url.path.endsWith('report-photos/')) {
            photoCalls++;
            return http.Response(jsonEncode({'photoToken': 'A' * 43}), 201);
          }
          payloads.add(
            (jsonDecode(r.body)['variables']['input'] as Map)
                .cast<String, dynamic>(),
          );
          if (submits++ == 0) {
            throw http.ClientException('Lost acknowledgement');
          }
          return http.Response(acknowledgement(), 200);
        }),
      );
      addTearDown(api.dispose);
      final uploader = ReportUploader(api, store);
      await expectLater(uploader.upload(report().id), throwsStateError);
      expect((await store.reports()).single.delivery, DeliveryState.queued);
      expect((await store.reports()).single.photoToken, 'A' * 43);
      // A reconstructed uploader models retry after process restart.
      await ReportUploader(api, store).upload(report().id);
      expect(photoCalls, 1);
      expect(payloads[0], payloads[1]);
      final saved = (await store.reports()).single;
      expect(saved.delivery, DeliveryState.submitted);
      expect(saved.serverStatus, HazardStatus.fresh);
      expect(saved.serverId, isNotNull);
      final restored = LocalReport.fromJson(saved.toJson(), saved.photo);
      expect(restored.serverId, saved.serverId);
    },
  );
  test('mocked-GPS upload is rejected without any network request', () async {
    final store = MemoryLocalStore();
    final sample = report(mocked: true);
    await store.saveReport(sample);
    var calls = 0;
    final api = RoadApi(
      'https://roadguard.example.test',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
      ReportUploader(api, store).upload(sample.id),
      throwsStateError,
    );
    expect(calls, 0);
    expect((await store.reports()).single.delivery, DeliveryState.localOnly);
  });
  test('mismatched server ACK never marks a report submitted', () async {
    final store = MemoryLocalStore();
    await store.saveReport(report().withDelivery(photoToken: 'A' * 43));
    final api = RoadApi(
      'https://roadguard.example.test',
      client: MockClient(
        (_) async => http.Response(acknowledgement(id: 'wrong'), 200),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(
      ReportUploader(api, store).upload(report().id),
      throwsStateError,
    );
    expect((await store.reports()).single.serverStatus, isNull);
  });
  test('live route geometry persists and errors never fall back to a made-up route', () async {
    var fail = false;
    final api = RoadApi(
      'https://roadguard.example.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            fail
                ? {
                    'errors': [
                      {'message': 'Routing unavailable'},
                    ],
                  }
                : {
                    'data': {
                      'drivingRoutes': [
                        {
                          'id': 'live',
                          'provider': 'OSRM',
                          'distanceMeters': 2000,
                          'durationSeconds': 300,
                          'coordinatesJson': '[[39.2,-6.8],[39.21,-6.81]]',
                          'computedAt': DateTime.now()
                              .toUtc()
                              .toIso8601String(),
                        },
                      ],
                    },
                  },
          ),
          200,
        ),
      ),
    );
    addTearDown(api.dispose);
    final routes = await api.routes([39.2, -6.8], [39.21, -6.81]);
    expect(routes.single.hasGeometry, isTrue);
    expect(
      RouteOption.fromJson(routes.single.toJson()).coordinates,
      routes.single.coordinates,
    );
    fail = true;
    await expectLater(
      api.routes([39.2, -6.8], [39.21, -6.81]),
      throwsStateError,
    );
  });
  test(
    'queued upload cannot move its photo capability to another server',
    () async {
      final store = MemoryLocalStore();
      await store.saveReport(
        report().withDelivery(
          delivery: DeliveryState.queued,
          uploadOrigin: 'https://original.example.test',
          photoToken: 'A' * 43,
        ),
      );
      var calls = 0;
      final api = RoadApi(
        'https://different.example.test',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        ReportUploader(api, store).upload(report().id),
        throwsStateError,
      );
      expect(calls, 0);
      expect((await store.reports()).single.photoToken, 'A' * 43);
    },
  );
  test('explicit expired unclaimed photo may be uploaded again', () async {
    final store = MemoryLocalStore();
    await store.saveReport(report().withDelivery(photoToken: 'A' * 43));
    var photos = 0, submissions = 0;
    final api = RoadApi(
      'https://roadguard.example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('report-photos/')) {
          photos++;
          return http.Response(jsonEncode({'photoToken': 'B' * 43}), 201);
        }
        submissions++;
        if (submissions == 1) {
          return http.Response(
            jsonEncode({
              'errors': [
                {'message': 'Photo token has expired.'},
              ],
            }),
            200,
          );
        }
        expect(
          jsonDecode(request.body)['variables']['input']['photoToken'],
          'B' * 43,
        );
        return http.Response(acknowledgement(), 200);
      }),
    );
    addTearDown(api.dispose);
    await ReportUploader(api, store).upload(report().id);
    expect(photos, 1);
    expect(submissions, 2);
    expect((await store.reports()).single.delivery, DeliveryState.submitted);
  });
}
