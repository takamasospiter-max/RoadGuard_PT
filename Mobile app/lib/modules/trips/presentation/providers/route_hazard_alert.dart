import 'dart:math' as math;

import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';

/// Proximity along the selected route. This is an approximate visual warning,
/// not a lane-level or collision warning.
class RouteHazardAlert {
  const RouteHazardAlert(this.hazard, this.distanceMeters);
  final PublicHazard hazard;
  final int distanceMeters;
}

class _RoutePosition {
  const _RoutePosition(this.along, this.offRoute);
  final double along, offRoute;
}

_RoutePosition? _project(
  double latitude,
  double longitude,
  List<List<double>> route,
) {
  if (route.length < 2) return null;
  final radians = latitude * math.pi / 180;
  final eastScale = 111320 * math.cos(radians);
  const northScale = 110540.0;
  var length = 0.0;
  _RoutePosition? best;
  for (var i = 1; i < route.length; i++) {
    if (route[i].length < 2 || route[i - 1].length < 2) return null;
    final a = route[i - 1], b = route[i];
    final dx = (b[0] - a[0]) * eastScale;
    final dy = (b[1] - a[1]) * northScale;
    final segmentLength = math.sqrt(dx * dx + dy * dy);
    if (segmentLength < 1) continue;
    final px = (longitude - a[0]) * eastScale;
    final py = (latitude - a[1]) * northScale;
    final t = ((px * dx + py * dy) / (segmentLength * segmentLength)).clamp(
      0.0,
      1.0,
    );
    final offRoute = math.sqrt(
      math.pow(px - t * dx, 2) + math.pow(py - t * dy, 2),
    );
    if (best == null || offRoute < best.offRoute) {
      best = _RoutePosition(length + t * segmentLength, offRoute);
    }
    length += segmentLength;
  }
  return best;
}

/// Where a point lies relative to a route: [along] = metres from the route's
/// start to the closest point on it, [offRoute] = metres away from the route.
/// Null for malformed routes. Used by navigation guidance (navigation_guide.dart).
({double along, double offRoute})? projectOnRoute(
  double latitude,
  double longitude,
  List<List<double>> route,
) {
  final position = _project(latitude, longitude, route);
  return position == null
      ? null
      : (along: position.along, offRoute: position.offRoute);
}

/// Total length of a route polyline in metres (same flat-earth approximation
/// as the projection, accurate for road-scale distances).
double routeLengthMeters(List<List<double>> route) {
  var length = 0.0;
  for (var i = 1; i < route.length; i++) {
    final a = route[i - 1], b = route[i];
    if (a.length < 2 || b.length < 2) return 0;
    final eastScale = 111320 * math.cos(a[1] * math.pi / 180);
    final dx = (b[0] - a[0]) * eastScale;
    final dy = (b[1] - a[1]) * 110540.0;
    length += math.sqrt(dx * dx + dy * dy);
  }
  return length;
}

/// A hazard this close to the route line (metres) counts as on the route:
/// used both for proximity alerts and for the markers on the route map.
const onRouteMaxMeters = 30.0;

/// The hazards to mark on a route map: those on or beside the route line
/// (within [onRouteMaxMeters]) anywhere along it, in their original order.
/// Hazards on parallel streets or past either end are left off the map.
List<PublicHazard> hazardsAlongRoute(
  RouteOption route,
  List<PublicHazard> hazards,
) => [
  for (final hazard in hazards)
    if ((_project(
              hazard.latitude,
              hazard.longitude,
              route.coordinates,
            )?.offRoute ??
            double.infinity) <=
        onRouteMaxMeters)
      hazard,
];

/// The area to ask the server for hazards along [route]: its bounding box
/// plus [onRouteMaxMeters] on every side, so hazards beside the first and
/// last stretch are included. Shaped like the hazards query's bbox
/// (west/south/east/north). Null for a route without a usable line.
Map<String, double>? routeHazardBounds(RouteOption route) {
  final points = route.coordinates;
  if (points.length < 2 || points.any((p) => p.length < 2)) return null;
  var west = points.first[0], east = west;
  var south = points.first[1], north = south;
  for (final p in points) {
    west = math.min(west, p[0]);
    east = math.max(east, p[0]);
    south = math.min(south, p[1]);
    north = math.max(north, p[1]);
  }
  // Metres → degrees; a degree of longitude shrinks towards the poles.
  final latMargin = onRouteMaxMeters / 110540;
  final widest = math.max(south.abs(), north.abs());
  final lngMargin =
      onRouteMaxMeters /
      (111320 * math.cos(widest * math.pi / 180).clamp(0.2, 1.0));
  return {
    'west': (west - lngMargin).clamp(-180.0, 180.0).toDouble(),
    'south': (south - latMargin).clamp(-90.0, 90.0).toDouble(),
    'east': (east + lngMargin).clamp(-180.0, 180.0).toDouble(),
    'north': (north + latMargin).clamp(-90.0, 90.0).toDouble(),
  };
}

/// The public hazards to mark along [route], fetched from the server for
/// the route's area (routeHazardBounds). Never throws: with no connection,
/// or a route too long for one query (the server allows 5° per side), it
/// returns no hazards, and markers then come only from the nearby refresh.
Future<List<PublicHazard>> fetchRouteHazards(
  RoadApi api,
  RouteOption route,
) async {
  final bounds = routeHazardBounds(route);
  if (bounds == null || !api.configured) return const [];
  try {
    return hazardsAlongRoute(route, await api.hazards(bounds));
  } catch (_) {
    return const [];
  }
}

RouteHazardAlert? nearestRouteHazard({
  required GpsFix fix,
  required RouteOption route,
  required List<PublicHazard> hazards,
  required Set<String> alreadyAlerted,
}) {
  if (fix.isMocked ||
      !fix.accuracyMeters.isFinite ||
      fix.accuracyMeters > 35 ||
      DateTime.now().difference(fix.observedAt).abs() >
          const Duration(seconds: 10)) {
    return null;
  }
  final position = _project(fix.latitude, fix.longitude, route.coordinates);
  if (position == null || position.offRoute > 45) return null;
  RouteHazardAlert? best;
  for (final hazard in hazards) {
    if (alreadyAlerted.contains(hazard.id)) continue;
    final point = _project(
      hazard.latitude,
      hazard.longitude,
      route.coordinates,
    );
    if (point == null || point.offRoute > onRouteMaxMeters) continue;
    final ahead = point.along - position.along;
    if (ahead < 20 || ahead > 250) continue;
    if (best == null || ahead < best.distanceMeters) {
      best = RouteHazardAlert(hazard, ahead.round());
    }
  }
  return best;
}

/// Two fresh fixes must advance along the route before using "ahead" language.
bool advancingOnRoute(GpsFix previous, GpsFix current, RouteOption route) {
  if (current.observedAt.isBefore(previous.observedAt) ||
      current.observedAt == previous.observedAt ||
      current.isMocked ||
      previous.isMocked ||
      current.accuracyMeters > 35 ||
      previous.accuracyMeters > 35) {
    return false;
  }
  final before = _project(
    previous.latitude,
    previous.longitude,
    route.coordinates,
  );
  final after = _project(
    current.latitude,
    current.longitude,
    route.coordinates,
  );
  if (before == null ||
      after == null ||
      before.offRoute > 45 ||
      after.offRoute > 45) {
    return false;
  }
  final progress = after.along - before.along;
  return progress >= 2 && progress <= 80;
}
