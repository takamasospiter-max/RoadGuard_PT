import 'models.dart';

enum ReportingGate {
  stationary,
  moving,
  unavailable,
  stale,
  inaccurate,
  simulated,
}

extension ReportingGateMessage on ReportingGate {
  bool get allowed => this == ReportingGate.stationary;
  String get title => switch (this) {
    ReportingGate.stationary => 'Stationary check passed',
    ReportingGate.moving => 'Please stop safely first',
    ReportingGate.unavailable => 'Waiting for a reliable GPS fix',
    ReportingGate.stale => 'GPS fix is out of date',
    ReportingGate.inaccurate => 'A more accurate location is needed',
    ReportingGate.simulated => 'Simulated GPS cannot verify a real report',
  };
  String get detail => switch (this) {
    ReportingGate.stationary =>
      'Location is current and GPS speed is near zero. Reporting is unlocked.',
    ReportingGate.moving =>
      'GPS indicates movement. Stop safely and wait for speed to settle.',
    ReportingGate.unavailable =>
      'Enable location and wait. Unknown speed is never treated as zero.',
    ReportingGate.stale =>
      'Wait for a fresh position before entering or saving a report.',
    ReportingGate.inaccurate =>
      'Move to a safe, open location and wait for a better signal.',
    ReportingGate.simulated =>
      'Turn off any mock-location app and use the device GPS.',
  };
}

/// When a manual pothole report may be saved. The SAME limits are enforced by
/// the backend (new-backend/mobile/reports.py: MAX_STATIONARY_SPEED_MPS,
/// MAX_GPS_ACCURACY_M) — change both together, or the backend will refuse
/// reports this app lets people save.
///
/// - Speed ≤ 0.5 m/s (1.8 km/h) counts as standing still. A phone at rest
///   often reports small GNSS speed drift, so demanding exactly 0 would block
///   genuine reports. NOTE: this is a deliberate, documented exception to the
///   SRS's strict zero-speed rule (agreed 2026-09-25); set
///   stationarySpeedThresholdMps to 0 (and the backend limit to 0) to restore it.
/// - Horizontal accuracy ≤ 25 m: a vaguer position can't reliably locate the
///   pothole or match it with sensor detections (grouped within 15 m).
/// - Fix no older than 10 s, not from the future, not mocked.
class SafetyPolicy {
  const SafetyPolicy({
    this.maxAge = const Duration(seconds: 10),
    this.maxAccuracyMeters = 25,
    this.stationarySpeedThresholdMps = 0.5,
  });
  final Duration maxAge;
  final double maxAccuracyMeters, stationarySpeedThresholdMps;
  ReportingGate evaluate(GpsFix? fix, DateTime now) {
    if (fix == null ||
        !fix.speedMps.isFinite ||
        fix.speedMps < 0 ||
        !fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180) {
      return ReportingGate.unavailable;
    }
    if (fix.isMocked) return ReportingGate.simulated;
    final age = now.difference(fix.observedAt);
    if (age.isNegative || age > maxAge) return ReportingGate.stale;
    if (!fix.accuracyMeters.isFinite ||
        fix.accuracyMeters < 0 ||
        fix.accuracyMeters > maxAccuracyMeters) {
      return ReportingGate.inaccurate;
    }
    if (fix.speedMps > stationarySpeedThresholdMps) {
      return ReportingGate.moving;
    }
    return ReportingGate.stationary;
  }
}

bool telemetryEligible({
  required bool registered,
  required bool consent,
  required bool activeTrip,
  required bool foreground,
}) => registered && consent && activeTrip && foreground;
