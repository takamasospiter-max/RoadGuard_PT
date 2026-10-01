import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadguard_ai/core/services/location_service.dart';

// GPS fixes must be timed on the phone's own clock, like sensor readings.
// The fix's own timestamp comes from the satellites; a phone clock just over
// a second behind made every sensor reading look older than the latest fix,
// so all were dropped and sensor sharing never queued a batch.
void main() {
  Position position(DateTime timestamp) => Position(
    latitude: -6.2149,
    longitude: 35.8084,
    timestamp: timestamp,
    accuracy: 8,
    altitude: 1200,
    altitudeAccuracy: 3,
    heading: 90,
    headingAccuracy: 5,
    speed: 12.5,
    speedAccuracy: 1,
    isMocked: false,
  );

  test('a fix is timed when it arrives, on the phone clock', () {
    final arrived = DateTime.utc(2026, 10, 1, 13, 0, 0);
    // Satellite time is 1.3 s ahead of this phone's clock.
    final fix = fixFromPosition(
      position(arrived.add(const Duration(milliseconds: 1300))),
      receivedAt: arrived,
    );
    expect(fix.observedAt, arrived);
  });

  test('position values are kept as they are', () {
    final arrived = DateTime.utc(2026, 10, 1, 13);
    final fix = fixFromPosition(position(arrived), receivedAt: arrived);
    expect(
      [
        fix.latitude,
        fix.longitude,
        fix.speedMps,
        fix.accuracyMeters,
        fix.isMocked,
      ],
      [-6.2149, 35.8084, 12.5, 8, false],
    );
  });
}
