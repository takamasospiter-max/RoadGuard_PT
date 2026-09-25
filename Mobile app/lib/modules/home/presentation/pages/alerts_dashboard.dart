import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/modules/home/presentation/providers/route_alerts_provider.dart';
import 'package:roadguard_ai/shared/providers_list.dart';

/// Inbox of warnings actually displayed during a live trip on this device.
class AlertsDashboard extends ConsumerStatefulWidget {
  const AlertsDashboard({super.key});
  @override
  ConsumerState<AlertsDashboard> createState() => _AlertsDashboardState();
}

enum _QueueScope { all, current, previous }

class _AlertsDashboardState extends ConsumerState<AlertsDashboard> {
  _QueueScope _scope = _QueueScope.all;


  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authProvider);
    final ownerKey = account.asData?.value?.id ?? 'guest';
    final queue = ref.watch(routeAlertsProvider(ownerKey));
    final trips = ref.watch(routeAlertTripsProvider).asData?.value ?? const <TripRecord>[];
    final active = ref.watch(tripProvider);
    final tripById = {for (final trip in trips) trip.id: trip};
    if (active != null) tripById[active.id] = active;
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(routeAlertsProvider(ownerKey));
          ref.invalidate(routeAlertTripsProvider);
          await ref.read(routeAlertsProvider(ownerKey).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
          Text('Road alerts', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Warnings you received during your trips',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          queue.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (_, _) => _EmptyQueue(
              title: 'Could not load your alert history',
              message: 'Pull down to try again.',
            ),
            data: (alerts) {
              final visible = alerts.where((alert) => switch (_scope) {
                _QueueScope.all => true,
                _QueueScope.current => active != null && alert.tripId == active.id,
                _QueueScope.previous => active == null || alert.tripId != active.id,
              }).toList();
              final grouped = <String, List<RouteAlertRecord>>{};
              for (final alert in visible) {
                grouped.putIfAbsent(alert.tripId, () => []).add(alert);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Summary(count: alerts.length, active: active != null,
                    currentCount: active == null ? 0 : alerts.where((alert) => alert.tripId == active.id).length),
                const SizedBox(height: 22),
                Text('Your alert queue', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(label: const Text('All'), selected: _scope == _QueueScope.all,
                      onSelected: (_) => setState(() => _scope = _QueueScope.all)),
                  if (active != null) ChoiceChip(label: const Text('This trip'), selected: _scope == _QueueScope.current,
                      onSelected: (_) => setState(() => _scope = _QueueScope.current)),
                  ChoiceChip(label: const Text('Previous trips'), selected: _scope == _QueueScope.previous,
                      onSelected: (_) => setState(() => _scope = _QueueScope.previous)),
                ]),
                const SizedBox(height: 14),
                if (visible.isEmpty) _EmptyQueue(
                  title: alerts.isEmpty ? 'No route alerts received yet' : 'No alerts in this view',
                  message: active != null && _scope == _QueueScope.current
                      ? 'No confirmed route warning has been received on this trip.'
                      : 'Confirmed route warnings appear here after they are shown during a live trip.',
                ),
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entry.key == active?.id ? 'Current trip' : 'Previous trip',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(tripById[entry.key] == null
                          ? 'Saved trip'
                          : '${tripById[entry.key]!.route.originLabel} → ${tripById[entry.key]!.route.destinationLabel}',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  ),
                  for (final alert in entry.value)
                    _ReceivedAlertCard(
                      key: ValueKey('received-alert-${alert.id}'), alert: alert,
                      trip: tripById[entry.key],
                    ),
                ],
              ]);
            },
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(onPressed: () => context.go(HomePaths.explore),
              icon: const Icon(Icons.map_outlined), label: const Text('Explore map')),
          const SizedBox(height: 8),
          Text('Saved on this device. Distances are approximate values from when each warning appeared.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.active, required this.currentCount});
  final int count, currentCount;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [RoadColors.heroGradientStart, RoadColors.welcomeButton],
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.notifications_active_outlined, color: RoadColors.welcomeAi),
        SizedBox(width: 10), Expanded(child: Text('RECEIVED ON YOUR ROUTES',
          style: TextStyle(color: RoadColors.welcomeAi, fontWeight: FontWeight.bold, letterSpacing: 1)))]),
      const SizedBox(height: 18),
      Text('$count', style: const TextStyle(fontSize: 44, height: 1, color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(count == 1 ? 'warning received' : 'warnings received', style: const TextStyle(color: Colors.white70)),
      if (active) ...[
        const SizedBox(height: 15),
        Text('$currentCount on your current trip', style: const TextStyle(color: RoadColors.welcomeAi)),
      ],
    ]),
  );
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20)),
    child: Column(children: [
      Icon(Icons.notifications_none_rounded, size: 43, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 6), Text(message, textAlign: TextAlign.center),
    ]),
  );
}

class _ReceivedAlertCard extends StatelessWidget {
  const _ReceivedAlertCard({super.key, required this.alert, this.trip});
  final RouteAlertRecord alert;
  final TripRecord? trip;

  void _showDetails(BuildContext context) => showModalBottomSheet<void>(
    context: context, showDragHandle: true,
    builder: (context) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${alert.kind.label} warning', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        Text('Received ${MaterialLocalizations.of(context).formatMediumDate(alert.receivedAt.toLocal())} '
            'at ${TimeOfDay.fromDateTime(alert.receivedAt.toLocal()).format(context)}'),
        const SizedBox(height: 10),
        Text('Approx. ${alert.distanceMeters} m ahead when this warning was shown'),
        if (alert.severity != null) ...[
          const SizedBox(height: 10), Text('Reported severity: ${alert.severity}'),
        ],
        if (trip != null) ...[
          const SizedBox(height: 10),
          Text('Trip: ${trip!.route.originLabel} → ${trip!.route.destinationLabel}'),
        ],
        const SizedBox(height: 18),
        const Text('RoadGuard had published this hazard (officer-confirmed or reported by several drivers) when you were warned. It is not a collision prediction.'),
      ]),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = alert.receivedAt.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero, elevation: 0, clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(onTap: () => _showDetails(context), child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 47, height: 47,
              decoration: BoxDecoration(color: const Color(0xffffeadb), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xffb7541f))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${alert.kind.label} ahead', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('About ${alert.distanceMeters} m when alerted'),
              const SizedBox(height: 5),
              Text('${MaterialLocalizations.of(context).formatShortDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ]),
        )),
      ),
    );
  }
}
