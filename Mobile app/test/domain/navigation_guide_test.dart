import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/modules/trips/presentation/providers/navigation_guide.dart';

// A straight 1 km route heading east near Dar es Salaam, with a left turn at
// 600 m and the destination at 1000 m. 0.009° of longitude ≈ 1 km here.
const lat = -6.79;
const start = 39.200;
const end = 39.209;

RouteStep step(
  String type,
  String instruction,
  double along, {
  String modifier = '',
}) => RouteStep(
  type: type,
  modifier: modifier,
  name: '',
  instruction: instruction,
  distanceMeters: 0,
  alongMeters: along,
  location: [start + (end - start) * along / 1000, lat],
);

final route = RouteOption(
  id: 'r1',
  origin: 'A',
  destination: 'B',
  road: 'OSRM',
  kilometers: 1,
  minutes: 2,
  hazardIds: const [],
  coordinates: const [
    [start, lat],
    [end, lat],
  ],
  steps: [
    step('depart', 'Head east on Morogoro Road', 0),
    step('turn', 'Turn left onto Bibi Titi Street', 600, modifier: 'left'),
    step('arrive', 'You have arrived at your destination', 1000),
  ],
);

/// A GPS fix `metres` along the route and `offset` metres north of it.
GpsFix fixAt(double metres, {double offset = 0, double speed = 10}) => GpsFix(
  latitude: lat + offset / 110540,
  longitude: start + (end - start) * metres / 993.7, // the line's own length
  speedMps: speed,
  accuracyMeters: 5,
  observedAt: DateTime.now(),
  isMocked: false,
);

void main() {
  test('progress finds the next manoeuvre and what remains', () {
    final p = navigationProgress(fix: fixAt(200), route: route)!;
    expect(p.nextStep.instruction, 'Turn left onto Bibi Titi Street');
    expect(p.distanceToNextStep, closeTo(400, 15));
    expect(p.remainingMeters, closeTo(800, 15));
    expect(p.remainingSeconds, closeTo(96, 3)); // 80 % of 2 minutes
    expect(p.arrived, isFalse);
  });

  test(
    'after the turn, the arrival is next; near the end counts as arrived',
    () {
      expect(
        navigationProgress(fix: fixAt(700), route: route)!.nextStep.isArrival,
        isTrue,
      );
      expect(
        navigationProgress(fix: fixAt(990), route: route)!.arrived,
        isTrue,
      );
    },
  );

  test('routes without steps give no guidance', () {
    final plain = RouteOption(
      id: 'x',
      origin: 'A',
      destination: 'B',
      road: 'r',
      kilometers: 1,
      minutes: 1,
      hazardIds: const [],
      coordinates: const [
        [start, lat],
        [end, lat],
      ],
    );
    expect(navigationProgress(fix: fixAt(100), route: plain), isNull);
  });

  test('announcer: early heads-up, reminder, then "now" — each once', () {
    final announcer = GuidanceAnnouncer();
    String? say(double metres) => announcer.next(
      navigationProgress(fix: fixAt(metres), route: route)!,
      speedMps: 10,
    );

    expect(
      say(150),
      isNull,
    ); // 450 m away: too early at 36 km/h (first prompt at 400 m)
    expect(say(250), 'In 350 metres, turn left onto Bibi Titi Street.');
    expect(say(260), isNull); // not repeated
    expect(say(500), 'In 100 metres, turn left onto Bibi Titi Street.');
    expect(say(585), 'Turn left onto Bibi Titi Street.');
    expect(say(590), isNull);
    expect(say(995), 'You have arrived at your destination.');
  });

  test('off-route monitor needs three clearly-off fixes in a row', () {
    final monitor = OffRouteMonitor();
    expect(monitor.update(offRouteMeters: 80, accuracyMeters: 5), isFalse);
    expect(monitor.update(offRouteMeters: 80, accuracyMeters: 5), isFalse);
    expect(
      monitor.update(offRouteMeters: 10, accuracyMeters: 5),
      isFalse,
    ); // back on: reset
    expect(monitor.update(offRouteMeters: 80, accuracyMeters: 5), isFalse);
    expect(monitor.update(offRouteMeters: 80, accuracyMeters: 5), isFalse);
    expect(monitor.update(offRouteMeters: 80, accuracyMeters: 5), isTrue);
    // With poor GPS (±60 m), 80 m off isn't conclusive.
    final fuzzy = OffRouteMonitor();
    for (var i = 0; i < 5; i++) {
      expect(fuzzy.update(offRouteMeters: 80, accuracyMeters: 60), isFalse);
    }
  });

  test('distances are phrased the way a driver would say them', () {
    expect(spokenDistance(447), '450 metres');
    expect(spokenDistance(73), '70 metres');
    expect(spokenDistance(1000), '1 kilometre');
    expect(spokenDistance(1540), '1.5 kilometres');
    expect(shortDistance(1540), '1.5 km');
    expect(shortDistance(230), '250 m');
  });

  test('route steps survive saving and loading a trip', () {
    final restored = RouteOption.fromJson(
      jsonDecode(jsonEncode(route.toJson())) as Map<String, dynamic>,
    );
    expect(
      restored.steps.map((s) => s.instruction),
      route.steps.map((s) => s.instruction),
    );
    expect(restored.steps[1].alongMeters, 600);
    // Trips saved before navigation existed still load (with no guidance).
    final old = route.toJson()..remove('steps');
    expect(RouteOption.fromJson(old).hasGuidance, isFalse);
  });

  test('hazards say whether an officer confirmed them', () {
    Map<String, dynamic> hazard(String? verification) => {
      'id': 'RG-00001',
      'category': 'POTHOLE',
      'severity': 'HIGH',
      'latitude': lat,
      'longitude': start,
      'confirmedAt': '2026-09-24T10:00:00Z',
      'updatedAt': '2026-09-24T10:00:00Z',
      'verification': ?verification,
      'deviceCount': 3,
    };
    expect(
      PublicHazard.fromJson(hazard('CONFIRMED')).confirmedByOfficer,
      isTrue,
    );
    expect(
      PublicHazard.fromJson(hazard('CROWD_REPORTED')).confirmedByOfficer,
      isFalse,
    );
    expect(
      PublicHazard.fromJson(hazard(null)).confirmedByOfficer,
      isTrue,
    ); // older servers
    expect(PublicHazard.fromJson(hazard('CROWD_REPORTED')).deviceCount, 3);
  });
}
