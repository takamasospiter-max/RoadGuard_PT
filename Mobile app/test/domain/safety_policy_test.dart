import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/models/safety_policy.dart';

void main() {
  const policy = SafetyPolicy();
  final now = DateTime.utc(2026, 9, 18, 10);
  GpsFix fix({
    double speed = 0,
    double accuracy = 5,
    DateTime? at,
    bool mocked = false,
    double latitude = -6.7924,
  }) => GpsFix(
    latitude: latitude,
    longitude: 39.2083,
    speedMps: speed,
    accuracyMeters: accuracy,
    observedAt: at ?? now,
    isMocked: mocked,
  );
  test('fresh valid zero-speed GPS unlocks reporting', () {
    expect(policy.evaluate(fix(), now), ReportingGate.stationary);
  });
  // Agreed rule (2026-09-25, shared with the backend): up to 0.5 m/s counts as
  // standing still, because phones at rest report small speed drift.
  test('speed above 0.5 m/s is blocked; small GPS drift counts as stationary', () {
    for (final speed in [.500001, .6, 10.0, 35.0]) {
      expect(policy.evaluate(fix(speed: speed), now), ReportingGate.moving);
    }
    for (final speed in [0.0, .000001, .3, .5]) {
      expect(policy.evaluate(fix(speed: speed), now), ReportingGate.stationary);
    }
  });
  test('negative speed does not become zero', () {
    expect(policy.evaluate(fix(speed: -1), now), ReportingGate.unavailable);
  });
  test('unknown position fails closed', () {
    expect(policy.evaluate(null, now), ReportingGate.unavailable);
  });
  test('NaN and infinite speed fail closed', () {
    for (final speed in [double.nan, double.infinity]) {
      expect(
        policy.evaluate(fix(speed: speed), now),
        ReportingGate.unavailable,
      );
    }
  });
  test('stale GPS locks previously stationary reports', () {
    expect(
      policy.evaluate(fix(at: now.subtract(const Duration(seconds: 11))), now),
      ReportingGate.stale,
    );
  });
  test('exact freshness boundary remains valid', () {
    expect(
      policy.evaluate(fix(at: now.subtract(const Duration(seconds: 10))), now),
      ReportingGate.stationary,
    );
  });
  test('future GPS timestamps fail closed', () {
    expect(
      policy.evaluate(fix(at: now.add(const Duration(milliseconds: 1))), now),
      ReportingGate.stale,
    );
  });
  test('poor or invalid accuracy fails closed', () {
    for (final accuracy in [26.0, -1.0, double.nan, double.infinity]) {
      expect(
        policy.evaluate(fix(accuracy: accuracy), now),
        ReportingGate.inaccurate,
      );
    }
  });
  test('mock GPS never verifies real reports', () {
    expect(policy.evaluate(fix(mocked: true), now), ReportingGate.simulated);
  });
  test('invalid coordinates fail closed', () {
    expect(policy.evaluate(fix(latitude: 91), now), ReportingGate.unavailable);
    expect(
      policy.evaluate(fix(latitude: double.nan), now),
      ReportingGate.unavailable,
    );
  });
  test('telemetry requires every eligibility condition', () {
    expect(
      telemetryEligible(
        registered: true,
        consent: true,
        activeTrip: true,
        foreground: true,
      ),
      isTrue,
    );
    expect(
      telemetryEligible(
        registered: false,
        consent: true,
        activeTrip: true,
        foreground: true,
      ),
      isFalse,
    );
    expect(
      telemetryEligible(
        registered: true,
        consent: false,
        activeTrip: true,
        foreground: true,
      ),
      isFalse,
    );
    expect(
      telemetryEligible(
        registered: true,
        consent: true,
        activeTrip: false,
        foreground: true,
      ),
      isFalse,
    );
    expect(
      telemetryEligible(
        registered: true,
        consent: true,
        activeTrip: true,
        foreground: false,
      ),
      isFalse,
    );
  });
}
