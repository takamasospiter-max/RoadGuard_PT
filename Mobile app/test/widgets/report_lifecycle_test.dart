import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/models/safety_policy.dart';
import 'package:roadguard_ai/core/services/location_service.dart';
import 'package:roadguard_ai/core/services/photo_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/storage/local_store.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';
import 'package:roadguard_ai/modules/reports/presentation/pages/report_screen.dart';
import 'package:roadguard_ai/modules/reports/presentation/pages/reports_screen.dart';

import '../support/photos.dart';

class _Location implements LocationService {
  final fixes = StreamController<GpsFix>.broadcast();
  Object? accessError;
  int settingsOpened = 0;

  @override
  Future<void> requestAccess() async {
    if (accessError case final Object error) throw error;
  }

  @override
  Stream<GpsFix> watch() => fixes.stream;

  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }
}

class _Photos implements PhotoService {
  Uint8List? captured;
  Future<Uint8List?>? recovery;
  int captures = 0;

  @override
  Future<Uint8List?> capture() async {
    captures++;
    return captured;
  }

  @override
  Future<Uint8List?> recover() async =>
      recovery == null ? null : await recovery;
}

void main() {
  late _Location location;
  late _Photos photos;
  late MemoryLocalStore store;
  final photo = testPhoto();

  GpsFix fix({double speed = 0}) => GpsFix(
    latitude: -6.79,
    longitude: 39.2,
    speedMps: speed,
    accuracyMeters: 4,
    observedAt: DateTime.now(),
  );

  Future<void> launch(
    WidgetTester tester, {
    Future<Uint8List?>? recovered,
    SafetyPolicy policy = const SafetyPolicy(),
    Stream<DateTime> ticks = const Stream<DateTime>.empty(),
    Widget screen = const ReportScreen(),
    List<LocalReport> reports = const [],
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    location = _Location();
    photos = _Photos()..recovery = recovered;
    store = MemoryLocalStore();
    for (final report in reports) {
      await store.saveReport(report);
    }
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(location.fixes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          photoServiceProvider.overrideWithValue(photos),
          localStoreProvider.overrideWithValue(store),
          safetyPolicyProvider.overrideWithValue(policy),
          clockProvider.overrideWith((ref) => ticks),
          // A connected (fake) report service; the upload itself always fails,
          // which these tests never reach or rely on.
          roadApiProvider.overrideWithValue(
            RoadApi(
              'https://roadguard.example.test',
              client: MockClient((_) async => http.Response('{}', 503)),
            ),
          ),
        ],
        child: MaterialApp(
          theme: roadTheme(brightness),
          home: screen,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enableGps(WidgetTester tester, {bool scrollUp = false}) async {
    await tester.scrollUntilVisible(
      find.text('Check device location'),
      scrollUp ? -300 : 300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Check device location'));
    await tester.pumpAndSettle();
    location.fixes.add(fix());
    await tester.pumpAndSettle();
  }

  Future<void> expectNotesEnabled(WidgetTester tester, bool enabled) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-notes')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('report-notes'))).enabled,
      enabled,
    );
  }

  for (final cancelled in [false, true]) {
    testWidgets(
      'camera ${cancelled ? 'cancellation' : 'return'} requires a fresh fix without lifecycle events',
      (tester) async {
        await launch(tester);
        photos.captured = cancelled ? null : photo;
        await enableGps(tester);
        final previousFix = fix();
        location.fixes.add(previousFix);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Take a photo'));
        await tester.tap(find.text('Take a photo'));
        await tester.pumpAndSettle();
        expect(photos.captures, 1);
        await expectNotesEnabled(tester, false);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('upload-report')))
              .onPressed,
          isNull,
        );

        location.fixes.add(previousFix);
        await tester.pumpAndSettle();
        await expectNotesEnabled(tester, false);
        location.fixes.add(fix());
        await tester.pumpAndSettle();
        await expectNotesEnabled(tester, true);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('upload-report')))
              .onPressed,
          cancelled ? isNull : isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'permission failure stays visible and provides settings and retry',
    (tester) async {
      await launch(tester);
      location.accessError = StateError(
        'Location is blocked. Open app settings to grant access.',
      );
      await tester.ensureVisible(find.text('Check device location'));
      await tester.tap(find.text('Check device location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location is blocked. Open app settings to grant access.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Open app settings'));
      await tester.tap(find.text('Open app settings'));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
      await expectNotesEnabled(tester, false);
      location.accessError = null;
      await enableGps(tester, scrollUp: true);
      await expectNotesEnabled(tester, true);
      expect(find.text('Open app settings'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background stops GPS and resume rejects a cached stationary fix',
    (tester) async {
      await launch(tester);
      await enableGps(tester);
      final previousFix = fix();
      location.fixes.add(previousFix);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Take a photo'));
      final capture = tester
          .widget<SurfaceCard>(
            find.ancestor(
              of: find.text('Take a photo'),
              matching: find.byType(SurfaceCard),
            ),
          )
          .onTap!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(location.fixes.hasListener, isFalse);
      // No frame renders while paused; even a retained action must reject GPS.
      capture();
      await tester.idle();
      expect(photos.captures, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, false);
      location.fixes.add(previousFix);
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, false);
      location.fixes.add(fix());
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(location.fixes.hasListener, isFalse);
    },
  );

  testWidgets(
    'delayed photo recovery requires GPS newer than the recovered photo',
    (tester) async {
      final recovery = Completer<Uint8List?>();
      await launch(tester, recovered: recovery.future);
      await enableGps(tester);
      final previousFix = fix();
      location.fixes.add(previousFix);
      await tester.pumpAndSettle();
      recovery.complete(photo);
      await tester.pumpAndSettle();
      location.fixes.add(previousFix);
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, false);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-report')))
            .onPressed,
        isNull,
      );
      location.fixes.add(fix());
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-report')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'upload re-checks the latest moving fix before another form frame renders',
    (tester) async {
      await launch(tester);
      photos.captured = photo;
      await enableGps(tester);
      await tester.ensureVisible(find.text('Take a photo'));
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      location.fixes.add(fix());
      await tester.pumpAndSettle();
      final upload = tester
          .widget<FilledButton>(find.byKey(const Key('upload-report')))
          .onPressed!;
      // Moving (above the 0.5 m/s standing-still limit).
      location.fixes.add(fix(speed: 0.6));
      // Deliver the native event without allowing the form to rebuild first.
      await tester.idle();
      upload();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Upload image'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await store.reports(), isEmpty);
      expect(find.text('Please stop safely first'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'clock expiry locks stationary evidence without a new GPS event',
    (tester) async {
      final ticks = StreamController<DateTime>();
      addTearDown(ticks.close);
      await launch(
        tester,
        policy: const SafetyPolicy(maxAge: Duration(seconds: 1)),
        ticks: ticks.stream,
      );
      await enableGps(tester);
      await expectNotesEnabled(tester, true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      ticks.add(DateTime.now());
      await tester.pumpAndSettle();
      await expectNotesEnabled(tester, false);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-report')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'report form, list and detail fit 320px at 200% text in ${brightness.name} theme',
      (tester) async {
        final report = LocalReport(
          id: 'fixture',
          kind: HazardKind.pothole,
          notes: 'Sample surface damage near the crossing.',
          fix: fix(),
          photo: photo,
          createdAt: DateTime.now(),
        );
        for (final screen in [
          const ReportScreen(),
          const Scaffold(body: ReportsScreen()),
          const ReportDetailScreen(id: 'fixture'),
        ]) {
          await launch(
            tester,
            screen: screen,
            reports: [report],
            width: 320,
            scale: 2,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          for (var step = 0; step < 12; step++) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -350),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
