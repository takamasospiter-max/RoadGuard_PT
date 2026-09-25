import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/utils/trip_time.dart';

// Trip times shown in the planner, the trip screen and trip history.
void main() {
  test('short trips stay in minutes', () {
    expect(formatTripMinutes(0), '0 min');
    expect(formatTripMinutes(45), '45 min');
    expect(formatTripMinutes(59), '59 min');
  });

  test('long trips are shown in hours and minutes', () {
    expect(formatTripMinutes(60), '1 h');
    expect(formatTripMinutes(61), '1 h 1 min');
    expect(formatTripMinutes(559), '9 h 19 min'); // Dodoma -> Mwanza
  });

  test('elapsed time keeps seconds only under an hour', () {
    expect(formatElapsed(const Duration(minutes: 4, seconds: 12)), '4m 12s');
    expect(formatElapsed(const Duration(hours: 2, minutes: 5, seconds: 40)), '2h 05m');
    expect(formatElapsed(const Duration(seconds: -3)), '0m 0s');
  });
}
