import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/live_services_screens.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';

class ActiveTripScreen extends ConsumerWidget {
  const ActiveTripScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    if (!await confirmAction(
      context,
      title: 'End this trip?',
      message: 'The trip will be saved to your on-device history.',
      confirm: 'End trip',
    )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () async {
      await ref.read(voiceServiceProvider).stop();
      await ref.read(tripProvider.notifier).end();
      if (context.mounted) context.go(TripPaths.history);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    if (trip == null) {
      return DetailScaffold(
        title: 'Trip preview',
        child: EmptyView(
          icon: Icons.route_rounded,
          title: 'No active trip',
          message: 'Choose a real destination and load a live route to begin.',
          action: 'Choose a route',
          onAction: () => context.go(PlannerPaths.plan),
        ),
      );
    }
    // Only a trip saved by a very old app version can lack route geometry.
    if (!trip.route.hasGeometry) {
      return DetailScaffold(
        title: 'Trip cannot resume',
        child: EmptyView(
          icon: Icons.route_outlined,
          title: 'This saved trip has no route map',
          message: 'It was saved without route geometry, so it cannot resume as navigation. End it and plan a new route.',
          action: 'End this saved trip',
          onAction: () => _finish(context, ref),
        ),
      );
    }
    return LiveTripScreen(trip: trip);
  }
}
