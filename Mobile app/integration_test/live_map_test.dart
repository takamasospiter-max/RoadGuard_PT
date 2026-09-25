import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

// A small real-network smoke test: only the visible map tiles are requested.
// No user data, GPS permissions, route services or report submissions are used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForTiles(WidgetTester tester) async {
    for (var attempt = 0; attempt < 90; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byKey(const Key('live-map-loading')).evaluate().isEmpty &&
          find.byKey(const Key('live-map-error')).evaluate().isEmpty) {
        return;
      }
    }
    fail(
      'Real OpenStreetMap tiles did not decode successfully within 45 seconds.',
    );
  }

  testWidgets(
    'Android decodes real OSM tiles, pans and preserves attribution',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: roadTheme(Brightness.light),
            home: Scaffold(
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => LiveRoadMap(
                    height: constraints.maxHeight,
                    fullBleed: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await waitForTiles(tester);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.byKey(const Key('live-location-marker')), findsNothing);
      expect(tester.takeException(), isNull);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('live-map-loaded');
      await tester.drag(
        find.byKey(const Key('live-map')),
        const Offset(-90, 45),
      );
      await waitForTiles(tester);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('live-map-panned');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
