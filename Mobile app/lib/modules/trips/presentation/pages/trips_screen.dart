import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';
import 'package:roadguard_ai/core/utils/trip_time.dart';

String formatDate(DateTime time) {
  final local = time.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

// Elapsed trip time: "4m 12s", or "2h 05m" for long drives (see trip_time.dart).
String formatDuration(Duration value) => formatElapsed(value);

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(tripProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(historyProvider);
        await ref.read(historyProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const PageHeading(
            'Your journeys.',
            'A little perspective on where you’ve been.',
          ),
          const SizedBox(height: 24),
          if (!ref.watch(roadApiProvider).configured)
            const SurfaceCard(
              child: Text(
                'Live route planning needs the RoadGuard service. Trips recorded from real routes will appear here.',
              ),
            ),
          const SizedBox(height: 22),
          if (active != null) ...[
            SurfaceCard(
              onTap: () => context.push(TripPaths.active),
              child: Row(
                children: [
                  Icon(
                    Icons.navigation_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active trip',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${active.route.originLabel} → ${active.route.destinationLabel}',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          AsyncPanel(
            value: ref.watch(historyProvider),
            onRetry: () => ref.invalidate(historyProvider),
            builder: (trips) {
              if (trips.isEmpty) {
                return EmptyView(
                  icon: Icons.route_outlined,
                  title: 'Your next journey starts here.',
                  message: 'Finish a live trip to save its route and elapsed time here.',
                  action: 'Plan a trip',
                  onAction: () => context.push(PlannerPaths.plan),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trips.length} completed ${trips.length == 1 ? 'trip' : 'trips'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  for (final trip in trips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _TripCard(trip: trip),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});
  final TripRecord trip;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatDate(trip.startedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              Icons.route_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${trip.route.originLabel} → ${trip.route.destinationLabel}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              '${trip.route.kilometers.toStringAsFixed(1)} KM OSRM ROUTE',
            ),
            StatusPill(
              '${formatDuration(trip.endedAt!.difference(trip.startedAt))} ELAPSED',
            ),
          ],
        ),
      ],
    ),
  );
}
