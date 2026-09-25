import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/app.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/photo_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/storage/settings_store.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/auth.dart';
import '../support/map_tiles.dart';

import '../support/photos.dart';

class _Location implements LocationService {
  final fixes = StreamController<GpsFix>.broadcast();
  @override
  Future<void> requestAccess() async {}
  @override
  Stream<GpsFix> watch() => fixes.stream;
  @override
  Future<void> openSettings() async {}
}

class _Photos implements PhotoService {
  @override
  Future<Uint8List?> capture() async => testPhoto();
  @override
  Future<Uint8List?> recover() async => null;
}

GpsFix fix([double speed = 0]) => GpsFix(
  latitude: -6.79,
  longitude: 39.25,
  speedMps: speed,
  accuracyMeters: 4,
  observedAt: DateTime.now(),
);
void main() {
  for (final failure in [false, true]) {
    testWidgets(
      'submit ${failure ? 'failure keeps one retryable local report' : 'binds photo and GPS and waits for server ACK'}',
      (tester) async {
        final location = _Location();
        final store = MemoryLocalStore();
        var submissions = 0;
        Map<String, dynamic>? submitted;
        final api = RoadApi(
          'https://roadguard.example.test',
          client: MockClient((request) async {
            expect(request.headers['authorization'], isNull);
            expect(request.headers['cookie'], isNull);
            if (request.url.path.contains('report-photos')) {
              return http.Response(jsonEncode({'photoToken': 'a' * 43}), 201);
            }
            if (request.body.contains('submitAnonymousReport')) {
              submissions++;
              submitted =
                  (jsonDecode(request.body)['variables']['input'] as Map)
                      .cast<String, dynamic>();
              if (failure) return http.Response('{}', 503);
              return http.Response(
                jsonEncode({
                  'data': {
                    'submitAnonymousReport': {
                      'id': '0a69df2b-982f-4274-a917-2de216553a3a',
                      'clientId': submitted!['clientId'],
                      'status': 'NEW',
                      'receivedAt': DateTime.now().toUtc().toIso8601String(),
                    },
                  },
                }),
                200,
              );
            }
            return http.Response('{"data":{"publicHazards":[]}}', 200);
          }),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.view.physicalSize = const Size(412, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await location.fixes.close();
          api.dispose();
        });
        const settings = AppSettings(onboardingComplete: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // Sign-in is required after onboarding; start as a signed-in traveller.
              authServiceProvider.overrideWithValue(signedInAuthService()),
              roadApiProvider.overrideWithValue(api),
              localStoreProvider.overrideWithValue(store),
              locationServiceProvider.overrideWithValue(location),
              photoServiceProvider.overrideWithValue(_Photos()),
              initialSettingsProvider.overrideWithValue(settings),
              settingsStoreProvider.overrideWithValue(
                MemorySettingsStore(settings),
              ),
              mapTileProviderFactoryProvider.overrideWithValue(
                testMapTileProviderFactory,
              ),
            ],
            child: const RoadGuardApp(),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RoadGuardApp)),
        );
        container.read(routerProvider).go('/report');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Check device location'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Check device location'));
        await tester.pumpAndSettle();
        location.fixes.add(fix());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Take a photo'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Take a photo'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('upload-report')))
              .onPressed,
          isNull,
        );
        location.fixes.add(fix());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('upload-report')));
        await tester.pumpAndSettle();
        expect(submissions, 0);
        expect(await store.reports(), isEmpty);
        // Movement while the confirmation is open must block saving/uploading.
        location.fixes.add(fix(1));
        await tester.pumpAndSettle();
        // The confirm button inside the dialog (the screen's own upload button
        // has the same label, so search within the dialog).
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Upload image'),
          ),
        );
        await tester.pumpAndSettle();
        expect(submissions, 0);
        expect(await store.reports(), isEmpty);
        // The rejection message (a SnackBar) covers the upload button at the
        // bottom for a few seconds; wait for it to go, as a user would.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        location.fixes.add(fix());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('upload-report')));
        await tester.pumpAndSettle();
        location.fixes.add(fix());
        await tester.pumpAndSettle();
        // The confirm button inside the dialog (the screen's own upload button
        // has the same label, so search within the dialog).
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Upload image'),
          ),
        );
        await tester.pumpAndSettle();
        final saved = (await store.reports()).single;
        expect(saved.photo, isNotEmpty);
        expect(saved.fix.latitude, -6.79);
        expect(saved.fix.longitude, 39.25);
        expect(saved.fix.speedMps, 0);
        expect(saved.fix.accuracyMeters, 4);
        expect(submissions, 1);
        expect(submitted!['latitude'], saved.fix.latitude);
        expect(submitted!['longitude'], saved.fix.longitude);
        expect(
          saved.delivery,
          failure ? DeliveryState.queued : DeliveryState.submitted,
        );
        expect(
          container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/reports/${saved.id}',
        );
        if (!failure) expect(saved.serverStatus, HazardStatus.fresh);
        expect(await store.telemetryCount(), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
