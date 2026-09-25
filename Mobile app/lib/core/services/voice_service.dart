import 'package:flutter_tts/flutter_tts.dart';

abstract interface class VoiceService {
  Future<void> stop();
}

abstract interface class RouteAlertVoiceService {
  /// Spoken hazard warning. [confirmedByOfficer] is false for hazards that
  /// several drivers' phones detected but no officer has verified yet, so the
  /// app never calls those "confirmed".
  Future<void> speakRouteAlert({
    required String hazard,
    required int distanceMeters,
    bool confirmedByOfficer = true,
  });
}

/// Spoken turn-by-turn directions ("In 200 metres, turn left onto ...").
abstract interface class NavigationVoiceService {
  Future<void> speakGuidance(String text);
}

class DeviceVoiceService
    implements VoiceService, RouteAlertVoiceService, NavigationVoiceService {
  final FlutterTts _tts = FlutterTts();
  @override
  Future<void> speakRouteAlert({
    required String hazard,
    required int distanceMeters,
    bool confirmedByOfficer = true,
  }) async {
    await _tts.stop();
    await _tts.setSpeechRate(0.45);
    await _tts.speak(
      confirmedByOfficer
          ? 'Confirmed $hazard ahead in about $distanceMeters meters. Drive carefully.'
          : '$hazard reported by other drivers ahead in about $distanceMeters meters. Drive carefully.',
    );
  }

  @override
  Future<void> speakGuidance(String text) async {
    // The trip screen holds directions back for a few seconds after a hazard
    // warning, so a direction never talks over a warning.
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
