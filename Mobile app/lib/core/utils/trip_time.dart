/// Human-friendly trip times, used wherever the app shows how long a drive
/// takes (route planner, trip screen ETA, trip history).
///
///   formatTripMinutes(45)  -> "45 min"
///   formatTripMinutes(60)  -> "1 h"
///   formatTripMinutes(559) -> "9 h 19 min"
///
/// Long trips used to read "559 min", which is hard to take in at a glance.
String formatTripMinutes(int minutes) {
  if (minutes < 60) return '${minutes < 0 ? 0 : minutes} min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// Elapsed time of a finished trip, e.g. "4m 12s" or "2h 05m".
/// Seconds are only shown for trips under an hour, where they still matter.
String formatElapsed(Duration value) {
  if (value.isNegative) value = Duration.zero;
  if (value.inHours == 0) {
    return '${value.inMinutes}m ${value.inSeconds.remainder(60)}s';
  }
  return '${value.inHours}h ${value.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
}
