import 'dart:math' as math;

import 'package:roadguard_ai/core/models/models.dart';

import 'route_hazard_alert.dart';

/// Turn-by-turn navigation guidance, computed from the route's steps
/// (backend `drivingRoutes.stepsJson`) and the latest GPS fix.
///
/// Pure Dart with no widgets, so it can be unit-tested; the trip screen
/// (LiveTripScreen) calls it on every location update.

/// Where the driver is on the route, and what's coming next.
class NavigationProgress {
  const NavigationProgress({
    required this.alongMeters,
    required this.offRouteMeters,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.nextStepIndex,
    required this.nextStep,
    required this.distanceToNextStep,
    required this.arrived,
    this.thenStep,
  });

  /// Metres driven along the route so far.
  final double alongMeters;

  /// How far the phone is from the route line.
  final double offRouteMeters;
  final double remainingMeters;
  final int remainingSeconds;

  /// The next manoeuvre ahead of the driver, and how far away it is.
  final int nextStepIndex;
  final RouteStep nextStep;
  final double distanceToNextStep;

  /// The manoeuvre right after the next one, when it follows closely
  /// ("Turn left, then turn right") — otherwise null.
  final RouteStep? thenStep;

  final bool arrived;
}

/// Within this distance of the end, the trip counts as arrived.
const arrivalRadiusMeters = 25.0;

/// Compute [NavigationProgress] for [fix] on [route], or null when the route
/// has no guidance data or the position can't be placed on it.
NavigationProgress? navigationProgress({
  required GpsFix fix,
  required RouteOption route,
}) {
  if (!route.hasGuidance) return null;
  final position = projectOnRoute(
    fix.latitude,
    fix.longitude,
    route.coordinates,
  );
  if (position == null) return null;

  // Step positions (alongMeters) come from OSRM's own distances, which can
  // differ slightly from the drawn line's length. Scale the projected position
  // onto OSRM's distances so the two are measured the same way.
  final steps = route.steps;
  final total = math.max(steps.last.alongMeters, 1.0);
  final lineLength = routeLengthMeters(route.coordinates);
  final scale = lineLength > 0 ? total / lineLength : 1.0;
  final along = (position.along * scale).clamp(0.0, total);

  // The next manoeuvre is the first one still ahead (a few metres of slack so
  // a manoeuvre isn't dropped before the driver has actually made it).
  var index = steps.indexWhere(
    (s) => s.type != 'depart' && s.alongMeters > along + 3,
  );
  if (index < 0) index = steps.length - 1; // only the arrival is left
  final next = steps[index];
  final after = index + 1 < steps.length ? steps[index + 1] : null;

  final remaining = math.max(0.0, total - along);
  final totalSeconds = route.minutes * 60;
  return NavigationProgress(
    alongMeters: along,
    offRouteMeters: position.offRoute,
    remainingMeters: remaining,
    remainingSeconds: (totalSeconds * remaining / total).round(),
    nextStepIndex: index,
    nextStep: next,
    distanceToNextStep: math.max(0.0, next.alongMeters - along),
    thenStep:
        after != null &&
            !next.isArrival &&
            after.alongMeters - next.alongMeters < 100
        ? after
        : null,
    arrived: remaining <= arrivalRadiusMeters,
  );
}

/// Decides when the driver has really left the route (so a new route should
/// be requested). One bad GPS reading isn't enough: it takes three fixes in
/// a row clearly off the route.
class OffRouteMonitor {
  int _consecutive = 0;

  /// Feed each new fix; returns true once rerouting should happen.
  bool update({
    required double offRouteMeters,
    required double accuracyMeters,
  }) {
    // Allow more slack when GPS is imprecise.
    final limit = math.max(50.0, accuracyMeters * 1.5);
    _consecutive = offRouteMeters > limit ? _consecutive + 1 : 0;
    return _consecutive >= 3;
  }

  void reset() => _consecutive = 0;
}

/// Picks what to say, and when, as the driver approaches each manoeuvre:
/// an early heads-up, a reminder close to it, and "now" at the manoeuvre.
/// Each prompt is spoken once.
class GuidanceAnnouncer {
  final Set<String> _spoken = {};

  /// Text to speak for this progress update, or null if nothing new is due.
  String? next(NavigationProgress progress, {required double speedMps}) {
    if (progress.arrived) {
      return _once('arrived', 'You have arrived at your destination.');
    }
    final step = progress.nextStep;
    final distance = progress.distanceToNextStep;
    final key = '${progress.nextStepIndex}';
    // Faster driving → earlier prompts (over ~58 km/h).
    final fast = speedMps > 16;
    final farMeters = fast ? 800.0 : 400.0;
    final nearMeters = fast ? 250.0 : 120.0;

    if (step.isArrival) {
      if (distance <= nearMeters) {
        return _once(
          '$key-near',
          'Your destination is ahead in about ${spokenDistance(distance)}.',
        );
      }
      return null;
    }
    final then = progress.thenStep == null
        ? ''
        : ', then ${_lowerFirst(progress.thenStep!.instruction)}';
    if (distance <= 30) {
      _spoken.addAll(['$key-far', '$key-near']);
      return _once('$key-now', '${step.instruction}$then.');
    }
    if (distance <= nearMeters) {
      _spoken.add('$key-far');
      return _once(
        '$key-near',
        'In ${spokenDistance(distance)}, ${_lowerFirst(step.instruction)}$then.',
      );
    }
    if (distance <= farMeters) {
      return _once(
        '$key-far',
        'In ${spokenDistance(distance)}, ${_lowerFirst(step.instruction)}.',
      );
    }
    return null;
  }

  String? _once(String key, String text) => _spoken.add(key) ? text : null;
}

String _lowerFirst(String text) =>
    text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

/// "150 metres", "1.5 kilometres" — rounded the way a driver would say it.
String spokenDistance(double meters) {
  if (meters >= 1000) {
    final km = (meters / 100).round() / 10;
    return '${km == km.roundToDouble() ? km.toInt() : km} kilometre${km == 1 ? '' : 's'}';
  }
  final rounded = meters < 100
      ? (meters / 10).round() * 10
      : (meters / 50).round() * 50;
  return '${math.max(10, rounded)} metres';
}

/// "150 m", "1.2 km" — for the on-screen banner.
String shortDistance(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  final rounded = meters < 100
      ? (meters / 10).round() * 10
      : (meters / 50).round() * 50;
  return '${math.max(0, rounded)} m';
}
