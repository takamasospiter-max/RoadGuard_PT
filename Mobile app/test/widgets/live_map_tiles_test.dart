import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/map_tiles.dart';

void main() {
  Future<void> showMap(
    WidgetTester tester,
    TestMapTileProvider tiles, {
    GpsFix? location,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileProviderFactoryProvider.overrideWithValue(() => tiles),
        ],
        child: MaterialApp(
          home: Scaffold(body: LiveRoadMap(height: 360, location: location)),
        ),
      ),
    );
    // Image decoding runs outside the fake test clock. Wait for its observable
    // result, with a deadline, instead of depending on a single 100 ms delay.
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      if (find.byKey(const Key('live-map-loading')).evaluate().isEmpty) break;
    }
  }

  testWidgets(
    'decoded tiles keep attribution visible without inventing a GPS marker',
    (tester) async {
      final tiles = TestMapTileProvider();
      await showMap(tester, tiles);

      expect(tiles.requests, greaterThan(0));
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const Key('map-attribution')) /* OpenStreetMap credit */, findsOneWidget);
      expect(find.byKey(const Key('live-map-loading')), findsNothing);
      expect(find.byKey(const Key('live-map-error')), findsNothing);
      expect(find.byKey(const Key('live-location-marker')), findsNothing);
      final attribution = tester.getRect(
        find.byKey(const Key('map-attribution')),
      );
      final map = tester.getRect(find.byType(FlutterMap));
      expect(attribution.top, greaterThanOrEqualTo(map.bottom));
      expect(attribution.height, greaterThanOrEqualTo(48));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tiles.disposed, isTrue);
    },
  );

  testWidgets('tile failures show retry and recover after decoding succeeds', (
    tester,
  ) async {
    final tiles = TestMapTileProvider(fail: true);
    await showMap(tester, tiles);

    expect(find.byKey(const Key('live-map-error')), findsOneWidget);
    expect(find.byKey(const Key('map-attribution')) /* OpenStreetMap credit */, findsOneWidget);
    final requestsBeforeRetry = tiles.requests;
    tiles.fail = false;
    await tester.tap(find.byKey(const Key('live-map-retry')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(tiles.requests, greaterThan(requestsBeforeRetry));
    expect(find.byKey(const Key('live-map-error')), findsNothing);
    expect(find.byKey(const Key('live-map-loading')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a supplied real position adds a marker at its coordinates', (
    tester,
  ) async {
    final location = GpsFix(
      latitude: -6.7924,
      longitude: 39.2083,
      speedMps: 0,
      accuracyMeters: 10,
      observedAt: DateTime.now(),
    );
    await showMap(tester, TestMapTileProvider(), location: location);

    expect(find.byKey(const Key('live-location-marker')), findsOneWidget);
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers.single.point.latitude, location.latitude);
    expect(markers.single.point.longitude, location.longitude);
  });
}
