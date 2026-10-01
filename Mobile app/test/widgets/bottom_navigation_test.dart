import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/home_page.dart';

// The bottom navigation uses Material Design icons (not text characters,
// which every phone draws in a different font): filled for the current tab,
// outlined for the others, as Material's navigation bar guidelines suggest.
void main() {
  Future<void> pumpHome(WidgetTester tester, String path) => tester.pumpWidget(
    MaterialApp(
      home: HomePage(path: path, child: const SizedBox()),
    ),
  );

  testWidgets('Explore selected: filled Explore, outlined others', (
    tester,
  ) async {
    await pumpHome(tester, HomePaths.explore);
    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('Alerts selected: filled Alerts', (tester) async {
    await pumpHome(tester, HomePaths.alerts);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('Profile selected: filled Profile, and no text-character icons', (
    tester,
  ) async {
    await pumpHome(tester, ProfilePaths.profile);
    expect(find.byIcon(Icons.person), findsOneWidget);
    for (final character in ['▣', '⚠', '◯']) {
      expect(find.text(character), findsNothing);
    }
  });

  testWidgets('tabs keep their labels and accessibility keys', (tester) async {
    await pumpHome(tester, HomePaths.explore);
    for (final label in ['Explore', 'Alerts', 'Profile']) {
      expect(find.text(label), findsOneWidget);
      expect(find.byKey(Key('nav-${label.toLowerCase()}')), findsOneWidget);
    }
  });
}
