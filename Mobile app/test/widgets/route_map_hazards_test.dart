import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/live_services_screens.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../support/map_tiles.dart';

// The route map (route preview and live trip) marks the hazards on the
// route, so travellers see what is coming before the proximity alert.
void main() {
  const route = RouteOption(
    id: 'route', origin: 'A', destination: 'B', road: 'OSRM',
    kilometers: 1, minutes: 2, hazardIds: [],
    coordinates: [[39.2, -6.8], [39.21, -6.8]],
  );
  PublicHazard hazard(String id, double longitude, {double latitude = -6.8}) =>
      PublicHazard.fromJson({
        'id': id, 'category': 'pothole', 'latitude': latitude,
        'longitude': longitude, 'severity': 'medium',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> pumpRouteMap(WidgetTester tester, List<PublicHazard> hazards) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileProviderFactoryProvider.overrideWithValue(testMapTileProviderFactory),
        ],
        child: MaterialApp(
          home: Scaffold(body: RouteMap(route: route, hazards: hazards)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('marks each hazard on the route, and only those', (tester) async {
    await pumpRouteMap(tester, [
      hazard('on-route-1', 39.203),
      hazard('on-route-2', 39.207),
      hazard('parallel-street', 39.205, latitude: -6.801), // ~110 m away
    ]);
    expect(find.byKey(const Key('route-hazard-on-route-1')), findsOneWidget);
    expect(find.byKey(const Key('route-hazard-on-route-2')), findsOneWidget);
    expect(find.byKey(const Key('route-hazard-parallel-street')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a route map without hazards shows no markers', (tester) async {
    await pumpRouteMap(tester, const []);
    expect(find.byIcon(Icons.warning_rounded), findsNothing);
  });
}
