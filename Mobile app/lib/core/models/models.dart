import 'dart:math';
import 'dart:typed_data';

String newLocalId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

enum HazardKind {
  pothole('Pothole'),
  crack('Crack');

  const HazardKind(this.label);
  final String label;
}

// These are SERVER lifecycle values. A local draft has no server status.
enum HazardStatus {
  fresh('New'),
  underVerification('Under Verification'),
  confirmed('Confirmed'),
  resolved('Resolved'),
  expired('Expired');

  const HazardStatus(this.label);
  final String label;
}

enum DeliveryState { localOnly, queued, submitted }

class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.accuracyMeters,
    required this.observedAt,
    this.isMocked = false,
  });
  final double latitude, longitude, speedMps, accuracyMeters;
  final DateTime observedAt;
  final bool isMocked;
  double get speedKmh => speedMps * 3.6;
  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speedMps': speedMps,
    'accuracyMeters': accuracyMeters,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'isMocked': isMocked,
  };
  factory GpsFix.fromJson(Map<String, dynamic> json) => GpsFix(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    speedMps: (json['speedMps'] as num).toDouble(),
    accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
    observedAt: DateTime.parse(json['observedAt'] as String),
    isMocked: json['isMocked'] as bool? ?? false,
  );
}

/// One turn-by-turn manoeuvre of a route ("Turn left onto Morogoro Road"),
/// as sent by the backend's `drivingRoutes.stepsJson` (new-backend/mobile/routing.py).
class RouteStep {
  const RouteStep({
    required this.type,
    required this.modifier,
    required this.name,
    required this.instruction,
    required this.distanceMeters,
    required this.alongMeters,
    required this.location,
    this.exit,
  });

  /// OSRM manoeuvre type: depart, turn, merge, roundabout, fork, arrive, ...
  final String type;

  /// Direction detail: left, right, slight left, sharp right, straight, uturn, ...
  final String modifier;

  /// Road name after the manoeuvre ('' when unnamed).
  final String name;

  /// Ready-made English text, e.g. "Turn left onto Morogoro Road".
  final String instruction;

  /// Length of this step, until the next manoeuvre.
  final double distanceMeters;

  /// Where the manoeuvre happens, in metres from the start of the route.
  final double alongMeters;

  /// [longitude, latitude] of the manoeuvre.
  final List<double> location;

  /// Roundabout exit number, when relevant.
  final int? exit;

  bool get isArrival => type == 'arrive';

  Map<String, Object?> toJson() => {
    'type': type,
    'modifier': modifier,
    'name': name,
    'instruction': instruction,
    'distanceMeters': distanceMeters,
    'alongMeters': alongMeters,
    'location': location,
    'exit': exit,
  };

  factory RouteStep.fromJson(Map<String, dynamic> json) => RouteStep(
    type: json['type'] as String? ?? 'turn',
    modifier: json['modifier'] as String? ?? '',
    name: json['name'] as String? ?? '',
    instruction: json['instruction'] as String? ?? 'Continue',
    distanceMeters: (json['distanceMeters'] as num? ?? 0).toDouble(),
    alongMeters: (json['alongMeters'] as num? ?? 0).toDouble(),
    location: (json['location'] as List? ?? const [0, 0])
        .map((v) => (v as num).toDouble())
        .toList(),
    exit: (json['exit'] as num?)?.toInt(),
  );
}

class RouteOption {
  const RouteOption({
    required this.id,
    required this.origin,
    required this.destination,
    required this.road,
    required this.kilometers,
    required this.minutes,
    required this.hazardIds,
    this.coordinates = const [],
    this.computedAt,
    this.steps = const [],
  });
  final String id, origin, destination, road;
  final double kilometers;
  final int minutes;
  final List<String> hazardIds;
  final List<List<double>> coordinates; // [longitude, latitude], OSRM geometry.
  final DateTime? computedAt;

  /// Turn-by-turn manoeuvres. Empty for routes saved before navigation
  /// existed; the trip screen then shows no guidance.
  final List<RouteStep> steps;

  /// True when this route can drive turn-by-turn guidance.
  bool get hasGuidance => steps.isNotEmpty && coordinates.length >= 2;

  /// True when the route has real map geometry (every route from the
  /// routing service does; only very old saved trips may not).
  bool get hasGeometry => coordinates.length >= 2;
  // Older saved routes used coordinate strings as labels. Keep their stored
  // values, but present a readable name in trip/history screens.
  String get originLabel => _readablePlace(origin, 'Selected starting point');
  String get destinationLabel =>
      _readablePlace(destination, 'Selected destination');
  static String _readablePlace(String value, String fallback) =>
      RegExp(r'^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$').hasMatch(value)
      ? fallback
      : value;
  Map<String, Object?> toJson() => {
    'id': id,
    'origin': origin,
    'destination': destination,
    'road': road,
    'kilometers': kilometers,
    'minutes': minutes,
    'hazardIds': hazardIds,
    'coordinates': coordinates,
    'computedAt': computedAt?.toUtc().toIso8601String(),
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  factory RouteOption.fromJson(Map<String, dynamic> json) => RouteOption(
    id: json['id'] as String,
    origin: json['origin'] as String,
    destination: json['destination'] as String,
    road: json['road'] as String,
    kilometers: (json['kilometers'] as num).toDouble(),
    minutes: json['minutes'] as int,
    hazardIds: (json['hazardIds'] as List<dynamic>).cast<String>(),
    coordinates: (json['coordinates'] as List? ?? [])
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
    computedAt: DateTime.tryParse(json['computedAt'] as String? ?? ''),
    // Older saved trips have no 'steps' key; they load with no guidance.
    steps: (json['steps'] as List? ?? const [])
        .map((s) => RouteStep.fromJson((s as Map).cast<String, dynamic>()))
        .toList(),
  );
}

/// A warning actually shown during a trip. Stored on this device so the
/// Alerts tab can show received warnings after the trip has ended.
class RouteAlertRecord {
  const RouteAlertRecord({
    required this.id,
    required this.tripId,
    required this.ownerKey,
    required this.hazardId,
    required this.kind,
    required this.distanceMeters,
    required this.receivedAt,
    this.severity,
  });
  final String id, tripId, ownerKey, hazardId;
  final HazardKind kind;
  final int distanceMeters;
  final DateTime receivedAt;
  final String? severity;

  /// Older app builds could store sample ("demo") alerts; they are skipped
  /// when loading so they never appear as real warnings.
  static bool isLegacySample(Map<String, dynamic> json) =>
      json['isDemo'] == true;

  Map<String, Object?> toJson() => {
    'id': id,
    'tripId': tripId,
    'ownerKey': ownerKey,
    'hazardId': hazardId,
    'kind': kind.name,
    'distanceMeters': distanceMeters,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'severity': severity,
  };
  factory RouteAlertRecord.fromJson(Map<String, dynamic> json) =>
      RouteAlertRecord(
        id: json['id'] as String,
        tripId: json['tripId'] as String,
        ownerKey: json['ownerKey'] as String,
        hazardId: json['hazardId'] as String,
        kind: HazardKind.values.byName(json['kind'] as String),
        distanceMeters: (json['distanceMeters'] as num).toInt(),
        receivedAt: DateTime.parse(json['receivedAt'] as String),
        severity: json['severity'] as String?,
      );
}

class TripRecord {
  const TripRecord({
    required this.id,
    required this.route,
    required this.startedAt,
    this.endedAt,
    this.paused = false,
    this.simulatedSpeedKmh = 0,
  });
  final String id;
  final RouteOption route;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool paused;
  final double simulatedSpeedKmh;
  bool get isActive => endedAt == null;
  TripRecord copyWith({
    DateTime? endedAt,
    bool? paused,
    double? simulatedSpeedKmh,
    RouteOption? route, // a new route after rerouting; same trip id
  }) => TripRecord(
    id: id,
    route: route ?? this.route,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    paused: paused ?? this.paused,
    simulatedSpeedKmh: simulatedSpeedKmh ?? this.simulatedSpeedKmh,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'route': route.toJson(),
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'paused': paused,
    'simulatedSpeedKmh': simulatedSpeedKmh,
  };
  factory TripRecord.fromJson(Map<String, dynamic> json) => TripRecord(
    id: json['id'] as String,
    route: RouteOption.fromJson(json['route'] as Map<String, dynamic>),
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
    paused: json['paused'] as bool? ?? false,
    simulatedSpeedKmh: (json['simulatedSpeedKmh'] as num? ?? 0).toDouble(),
  );
}

class LocalReport {
  const LocalReport({
    required this.id,
    required this.kind,
    required this.notes,
    required this.fix,
    required this.photo,
    required this.createdAt,
    this.delivery = DeliveryState.localOnly,
    this.serverStatus,
    this.photoToken,
    this.serverId,
    this.receivedAt,
    this.uploadOrigin,
  });
  final String id, notes;
  final HazardKind kind;
  final GpsFix fix;
  final Uint8List photo;
  final DateTime createdAt;
  // Reports are anonymous: identity fields do not exist in this model.
  final DeliveryState delivery;
  final HazardStatus? serverStatus;
  final String? photoToken, serverId, uploadOrigin;
  final DateTime? receivedAt;
  LocalReport withDelivery({
    DeliveryState? delivery,
    String? photoToken,
    String? serverId,
    HazardStatus? serverStatus,
    DateTime? receivedAt,
    String? uploadOrigin,
  }) => LocalReport(
    id: id,
    kind: kind,
    notes: notes,
    fix: fix,
    photo: photo,
    createdAt: createdAt,
    delivery: delivery ?? this.delivery,
    photoToken: photoToken ?? this.photoToken,
    serverId: serverId ?? this.serverId,
    serverStatus: serverStatus ?? this.serverStatus,
    receivedAt: receivedAt ?? this.receivedAt,
    uploadOrigin: uploadOrigin ?? this.uploadOrigin,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'notes': notes,
    'fix': fix.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'delivery': delivery.name,
    'serverStatus': serverStatus?.name,
    'photoToken': photoToken,
    'serverId': serverId,
    'receivedAt': receivedAt?.toUtc().toIso8601String(),
    'uploadOrigin': uploadOrigin,
  };

  /// Older app builds could store sample ("demo") reports; they are skipped
  /// when loading so they can never be shown or uploaded as real reports.
  static bool isLegacySample(Map<String, dynamic> json) =>
      json['isDemo'] == true;

  factory LocalReport.fromJson(Map<String, dynamic> json, Uint8List photo) =>
      LocalReport(
        id: json['id'] as String,
        kind: HazardKind.values.byName(json['kind'] as String),
        notes: json['notes'] as String,
        fix: GpsFix.fromJson(json['fix'] as Map<String, dynamic>),
        photo: photo,
        createdAt: DateTime.parse(json['createdAt'] as String),
        delivery: DeliveryState.values.byName(json['delivery'] as String),
        photoToken: json['photoToken'] as String?,
        serverId: json['serverId'] as String?,
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? ''),
        uploadOrigin: json['uploadOrigin'] as String?,
        serverStatus: json['serverStatus'] == null
            ? null
            : HazardStatus.values.byName(json['serverStatus'] as String),
      );
}

/// A traveller's standing answer about sharing road sensor data.
enum SensorSharingChoice {
  /// Not asked yet (or asked about an older notice): ask when a trip starts.
  ask,

  /// "Share on every trip": collection starts automatically with each trip.
  everyTrip,

  /// "Not now": no collection, and no question on every trip. Can be turned
  /// on later in Profile.
  declined,
}

class AppSettings {
  const AppSettings({
    this.onboardingComplete = false,
    this.voiceEnabled = true,
    this.appearance = 'system',
    this.sensorSharing = const {},
  });
  final bool onboardingComplete, voiceEnabled;
  final String appearance;

  /// Sensor-sharing answers per account id: the notice version accepted for
  /// "every trip", or 0 for "Not now". Per account, because a shared phone
  /// must not reuse one person's consent for another; per notice version,
  /// because new wording needs a new answer.
  final Map<String, int> sensorSharing;

  SensorSharingChoice sensorSharingFor(String accountId, int noticeVersion) =>
      switch (sensorSharing[accountId]) {
        null => SensorSharingChoice.ask,
        0 => SensorSharingChoice.declined,
        final accepted when accepted == noticeVersion =>
          SensorSharingChoice.everyTrip,
        _ => SensorSharingChoice.ask, // accepted an older notice: ask again
      };

  AppSettings withSensorSharing(
    String accountId, {
    required bool everyTrip,
    required int noticeVersion,
  }) => AppSettings(
    onboardingComplete: onboardingComplete,
    voiceEnabled: voiceEnabled,
    appearance: appearance,
    sensorSharing: {...sensorSharing, accountId: everyTrip ? noticeVersion : 0},
  );

  AppSettings copyWith({
    bool? onboardingComplete,
    bool? voiceEnabled,
    String? appearance,
  }) => AppSettings(
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    appearance: appearance ?? this.appearance,
    sensorSharing: sensorSharing,
  );
  Map<String, Object?> toJson() => {
    'onboardingComplete': onboardingComplete,
    'voiceEnabled': voiceEnabled,
    'appearance': appearance,
    'sensorSharing': sensorSharing,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    voiceEnabled: json['voiceEnabled'] as bool? ?? true,
    appearance: ['system', 'light', 'dark'].contains(json['appearance'])
        ? json['appearance'] as String
        : 'system',
    // Settings saved before this existed have no entry: nobody was asked.
    sensorSharing: {
      for (final entry
          in (json['sensorSharing'] as Map<String, dynamic>? ?? const {})
              .entries)
        if (entry.value is int) entry.key: entry.value as int,
    },
  );
}
