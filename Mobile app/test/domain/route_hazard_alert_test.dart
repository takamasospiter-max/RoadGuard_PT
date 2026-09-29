import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/modules/trips/presentation/providers/route_hazard_alert.dart';

void main() {
  const route = RouteOption(
    id: 'route', origin: 'A', destination: 'B', road: 'OSRM',
    kilometers: 1, minutes: 2, hazardIds: [],
    coordinates: [[0, 0], [0.01, 0]],
  );
  GpsFix fix({double longitude = 0.001, double accuracy = 8}) => GpsFix(
    latitude: 0, longitude: longitude, speedMps: 8,
    accuracyMeters: accuracy, observedAt: DateTime.now(),
  );
  PublicHazard hazard(String id, double longitude, {double latitude = 0}) =>
      PublicHazard.fromJson({
        'id': id, 'category': 'pothole', 'latitude': latitude,
        'longitude': longitude, 'severity': 'medium',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

  test('shows only a confirmed route hazard ahead of an accurate GPS fix', () {
    final alert = nearestRouteHazard(
      fix: fix(), route: route,
      hazards: [hazard('behind', 0.0005), hazard('off-route', 0.002, latitude: 0.001), hazard('ahead', 0.002)],
      alreadyAlerted: {},
    );
    expect(alert?.hazard.id, 'ahead');
    expect(alert!.distanceMeters, inInclusiveRange(90, 130));
  });
  test('requires movement forward on the selected route', () {
    final earlier = fix(longitude: 0.0009);
    final forward = GpsFix(latitude: 0, longitude: 0.001,
      speedMps: 8, accuracyMeters: 8,
      observedAt: earlier.observedAt.add(const Duration(seconds: 1)));
    final backward = GpsFix(latitude: 0, longitude: 0.0008,
      speedMps: 8, accuracyMeters: 8,
      observedAt: earlier.observedAt.add(const Duration(seconds: 1)));
    expect(advancingOnRoute(earlier, forward, route), isTrue);
    expect(advancingOnRoute(earlier, backward, route), isFalse);
  });
  // Markers on the route map: hazards on or beside the route line (≤ 30 m),
  // along its whole length; everything else is left off the map.
  group('hazardsAlongRoute', () {
    test('keeps hazards on or beside the route, anywhere along it', () {
      final kept = hazardsAlongRoute(route, [
        hazard('start', 0),
        hazard('middle-beside', 0.005, latitude: 0.0002), // ~22 m off the line
        hazard('end', 0.01),
      ]);
      expect(kept.map((h) => h.id), ['start', 'middle-beside', 'end']);
    });
    test('leaves out hazards away from the route', () {
      final kept = hazardsAlongRoute(route, [
        hazard('parallel-street', 0.005, latitude: 0.0005), // ~55 m off
        hazard('past-the-end', 0.012), // ~220 m beyond the destination
      ]);
      expect(kept, isEmpty);
    });
    test('shows nothing for a route without a usable line', () {
      const noLine = RouteOption(
        id: 'r', origin: 'A', destination: 'B', road: 'OSRM',
        kilometers: 0, minutes: 0, hazardIds: [], coordinates: [[0, 0]],
      );
      expect(hazardsAlongRoute(noLine, [hazard('h', 0)]), isEmpty);
    });
  });
  // The area to fetch hazards for: the whole route plus a margin, so hazards
  // just beside the first and last stretch are included too.
  group('routeHazardBounds', () {
    test('covers the whole route plus a margin on every side', () {
      final box = routeHazardBounds(route)!;
      expect(box['west']!, lessThan(0));
      expect(box['east']!, greaterThan(0.01));
      expect(box['south']!, lessThan(0));
      expect(box['north']!, greaterThan(0));
      // The margin is small (tens of metres), not kilometres.
      expect(box['north']! - box['south']!, lessThan(0.002));
    });
    test('is null for a route without a usable line', () {
      const noLine = RouteOption(
        id: 'r', origin: 'A', destination: 'B', road: 'OSRM',
        kilometers: 0, minutes: 0, hazardIds: [], coordinates: [[0, 0]],
      );
      expect(routeHazardBounds(noLine), isNull);
    });
  });
  test('does not repeat or fabricate a proximity warning', () {
    final ahead = hazard('ahead', 0.002);
    expect(nearestRouteHazard(fix: fix(), route: route, hazards: [ahead], alreadyAlerted: {'ahead'}), isNull);
    expect(nearestRouteHazard(fix: fix(accuracy: 80), route: route, hazards: [ahead], alreadyAlerted: {}), isNull);
    expect(nearestRouteHazard(fix: fix(longitude: 0.006), route: route, hazards: [ahead], alreadyAlerted: {}), isNull);
  });
}
