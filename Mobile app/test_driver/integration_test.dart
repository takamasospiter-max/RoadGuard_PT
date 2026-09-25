import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

// Alternate SDK runner for devices affected by flutter test's DDS discovery race.
// Runs the same assertions. Optional Android screenshots use isolated test data.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 5),
  responseDataCallback: (data) async {
    final screenshots = data?['screenshots'] as List<dynamic>? ?? [];
    for (final screenshot in screenshots) {
      final name = screenshot['screenshotName'] as String;
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
        throw FormatException('Unexpected screenshot name', name);
      }
      final directory = Directory(
        name.startsWith('live-map-')
            ? 'build/verification/live-map-2026-09-21/screenshots'
            : 'build/verification/design-2026-09-21/screenshots',
      );
      await directory.create(recursive: true);
      final bytes = (screenshot['bytes'] as List<dynamic>).cast<int>();
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
    }
    await writeResponseData({'screenshotsSaved': screenshots.length});
  },
);
