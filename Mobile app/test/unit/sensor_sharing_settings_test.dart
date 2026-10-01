import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/models/models.dart';

// The traveller's standing choice about sensor sharing, saved per account
// (a shared phone must not reuse one person's consent for another) and per
// notice version (new wording needs a new answer).
void main() {
  const notice = 2;

  test('nobody has been asked yet', () {
    expect(
      const AppSettings().sensorSharingFor('alice', notice),
      SensorSharingChoice.ask,
    );
  });

  test('"Share on every trip" applies to that account only', () {
    final settings = const AppSettings().withSensorSharing(
      'alice',
      everyTrip: true,
      noticeVersion: notice,
    );
    expect(
      settings.sensorSharingFor('alice', notice),
      SensorSharingChoice.everyTrip,
    );
    expect(settings.sensorSharingFor('bob', notice), SensorSharingChoice.ask);
  });

  test('"Not now" is remembered, so the app does not ask on every trip', () {
    final settings = const AppSettings().withSensorSharing(
      'alice',
      everyTrip: false,
      noticeVersion: notice,
    );
    expect(
      settings.sensorSharingFor('alice', notice),
      SensorSharingChoice.declined,
    );
  });

  test('a new notice version asks again', () {
    final settings = const AppSettings().withSensorSharing(
      'alice',
      everyTrip: true,
      noticeVersion: notice,
    );
    expect(
      settings.sensorSharingFor('alice', notice + 1),
      SensorSharingChoice.ask,
    );
  });

  test('the choice survives saving and loading', () {
    final saved = const AppSettings(voiceEnabled: false)
        .withSensorSharing('alice', everyTrip: true, noticeVersion: notice)
        .withSensorSharing('bob', everyTrip: false, noticeVersion: notice);
    final loaded = AppSettings.fromJson(saved.toJson());
    expect(
      loaded.sensorSharingFor('alice', notice),
      SensorSharingChoice.everyTrip,
    );
    expect(
      loaded.sensorSharingFor('bob', notice),
      SensorSharingChoice.declined,
    );
    expect(loaded.voiceEnabled, isFalse);
  });

  test('settings saved before this feature load as "not asked"', () {
    final loaded = AppSettings.fromJson({'onboardingComplete': true});
    expect(loaded.sensorSharingFor('alice', notice), SensorSharingChoice.ask);
  });
}
