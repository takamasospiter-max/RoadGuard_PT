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

_RoutePosition? _project(double latitude, double longitude, List<List<double>> route) {
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
    final t = ((px * dx + py * dy) / (segmentLength * segmentLength)).clamp(0.0, 1.0);
    final offRoute = math.sqrt(math.pow(px - t * dx, 2) + math.pow(py - t * dy, 2));
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

RouteHazardAlert? nearestRouteHazard({
  required GpsFix fix,
  required RouteOption route,
  required List<PublicHazard> hazards,
  required Set<String> alreadyAlerted,
}) {
  if (fix.isMocked || !fix.accuracyMeters.isFinite || fix.accuracyMeters > 35 ||
      DateTime.now().difference(fix.observedAt).abs() > const Duration(seconds: 10)) {
    return null;
  }
  final position = _project(fix.latitude, fix.longitude, route.coordinates);
  if (position == null || position.offRoute > 45) return null;
  RouteHazardAlert? best;
  for (final hazard in hazards) {
    if (alreadyAlerted.contains(hazard.id)) continue;
    final point = _project(hazard.latitude, hazard.longitude, route.coordinates);
    if (point == null || point.offRoute > 30) continue;
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
      current.isMocked || previous.isMocked ||
      current.accuracyMeters > 35 || previous.accuracyMeters > 35) {
    return false;
  }
  final before = _project(previous.latitude, previous.longitude, route.coordinates);
  final after = _project(current.latitude, current.longitude, route.coordinates);
  if (before == null || after == null || before.offRoute > 45 || after.offRoute > 45) return false;
  final progress = after.along - before.along;
  return progress >= 2 && progress <= 80;
}
