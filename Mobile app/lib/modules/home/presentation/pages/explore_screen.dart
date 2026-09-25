import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/live_services_screens.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/alerts_dashboard.dart';
import 'package:roadguard_ai/modules/planner/presentation/pages/place_search_sheet.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';
import 'package:roadguard_ai/shared/widgets/map_actions.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';

import '../providers/map_location_session.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen>
    with WidgetsBindingObserver {
  final _map = MapController();
  late final MapLocationSession _location;
  late final GoRouter _router;
  bool _mapReady = false;
  bool _centerNextFix = false;
  bool _selectingDestination = false;

  @override
  void initState() {
    super.initState();
    _location = MapLocationSession(ref.read(locationServiceProvider));
    _location.addListener(_locationChanged);
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(_routeChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _routeChanged() {
    // Imperative pushes do not necessarily update the browser URL. Inspect
    // the top route so a covered Explore never retains its GPS subscription.
    if (_router
                .routerDelegate
                .currentConfiguration
                .lastOrNull
                ?.matchedLocation !=
            HomePaths.explore &&
        _location.active) {
      _location.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _location.active) {
      _location.stop();
    }
  }

  void _locationChanged() {
    if (!mounted) return;
    final fix = _location.fix;
    if (_mapReady && _centerNextFix && fix != null) {
      _map.move(LatLng(fix.latitude, fix.longitude), 16);
      _centerNextFix = false;
    }
    _showLocationError();
    setState(() {});
  }

  /// Tell the driver why My location didn't work (e.g. permission denied),
  /// with a shortcut to the settings — otherwise the button would just seem
  /// to do nothing. Each distinct error is shown once.
  String? _shownLocationError;
  void _showLocationError() {
    final error = _location.error;
    if (error == null) {
      _shownLocationError = null;
      return;
    }
    if (error == _shownLocationError) return;
    _shownLocationError = error;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(error),
        action: SnackBarAction(
          label: 'Open settings',
          onPressed: () => unawaited(_location.openSettings()),
        ),
      ),
    );
  }

  void _locate() {
    _centerNextFix = true;
    if (_location.fix != null) {
      _locationChanged();
    } else {
      unawaited(_location.start());
    }
  }

  Future<void> _openPlaceSearch() async {
    final place = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute<PlaceResult>(
        builder: (_) => Scaffold(
          body: PlaceSearchSheet(
            start: false,
            onChooseOnMap: _enableMapSelection,
          ),
        ),
      ),
    );
    if (!mounted || place == null) return;
    await context.push(PlannerPaths.plan, extra: place);
  }

  void _enableMapSelection() {
    if (mounted) setState(() => _selectingDestination = true);
  }

  void _selectMapPoint(LatLng point) {
    if (!_selectingDestination) return;
    setState(() => _selectingDestination = false);
    final place = PlaceResult(
      label:
          'Map pin · ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
      latitude: point.latitude,
      longitude: point.longitude,
    );
    context.go(PlannerPaths.plan, extra: place);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_routeChanged);
    _location.removeListener(_locationChanged);
    _location.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(roadApiProvider).configured) return const LiveExploreScreen();
    final active = ref.watch(tripProvider);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              key: const Key('explore-map-canvas'),
              fit: StackFit.expand,
              children: [
                LiveRoadMap(
                  height: constraints.maxHeight,
                  fullBleed: true,
                  showAttribution: false,
                  controller: _map,
                  location: _location.fix,
                  onTap: (_, point) => _selectMapPoint(point),
                  onMapReady: () => _mapReady = true,
                ),
                Positioned(
                  top: 14,
                  left: 16,
                  right: 16,
                  child: _selectingDestination
                      ? Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          elevation: 4,
                          child: ListTile(
                            leading: const Icon(Icons.add_location_alt_outlined),
                            title: const Text('Tap the map to choose a destination'),
                            trailing: IconButton(
                              tooltip: 'Cancel map selection',
                              onPressed: () => setState(
                                () => _selectingDestination = false,
                              ),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                      MapSearchBar(
                        actionKey: const Key('explore-plan'),
                        onTap: () => unawaited(_openPlaceSearch()),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 2,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off_outlined, size: 17),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Live routes and hazard data need a RoadGuard connection.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                          ],
                        ),
                ),
                Positioned(
                  bottom: 12,
                  right: 16,
                  child: MapActionButtons(
                    onDirections: () => context.push(PlannerPaths.plan),
                    locationActive: _location.active,
                    onLocate: _location.requesting
                        ? null
                        : () {
                            if (_location.active) {
                              _location.stop();
                            } else {
                              _locate();
                            }
                          },
                    onReport: () => context.push(ReportPaths.create),
                    onResume: active == null
                        ? null
                        : () => context.push(TripPaths.active),
                  ),
                ),
                  const Positioned(
                    left: 10,
                    bottom: 5,
                    child: MapAttribution(compact: true),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context) => const AlertsDashboard();
}

class HazardCard extends StatelessWidget {
  const HazardCard({super.key, required this.hazard});
  final PublicHazard hazard;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: () => showPublicHazard(context, hazard),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hazard.kind.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Severity: ${hazard.severity ?? 'Not assigned'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 5),
              Text(
                'Server confirmed · ${hazard.latitude.toStringAsFixed(4)}, ${hazard.longitude.toStringAsFixed(4)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: 20),
      ],
    ),
  );
}

class HazardsScreen extends ConsumerWidget {
  const HazardsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hazards = ref.watch(latestPublicHazardsProvider);
    final connected = ref.watch(roadApiProvider).configured;
    return DetailScaffold(
      title: 'Confirmed hazards',
      child: hazards.isEmpty
          ? EmptyView(
              icon: Icons.warning_amber_rounded,
              title: connected
                  ? 'No confirmed hazards loaded'
                  : 'Road services are not connected',
              message: connected
                  ? 'Open Explore and refresh the live map to load confirmed hazards in your area.'
                  : 'Connect to RoadGuard to load server-confirmed hazards.',
              action: 'Explore map',
              onAction: () => context.go(HomePaths.explore),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final hazard in hazards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: HazardCard(hazard: hazard),
                  ),
              ],
            ),
    );
  }
}

class HazardDetailScreen extends ConsumerWidget {
  const HazardDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref
        .watch(latestPublicHazardsProvider)
        .where((hazard) => hazard.id == id);
    if (matches.isEmpty) {
      return DetailScaffold(
        title: 'Hazard',
        child: EmptyView(
          icon: Icons.search_off_rounded,
          title: 'Hazard is not loaded',
          message:
              'Return to Explore and refresh the map to load current server-confirmed hazards.',
          action: 'Explore map',
          onAction: () => context.go(HomePaths.explore),
        ),
      );
    }
    final hazard = matches.first;
    return DetailScaffold(
      title: 'Hazard details',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading(
            'Confirmed ${hazard.kind.label.toLowerCase()}',
            'Server-confirmed road hazard',
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Severity: ${hazard.severity ?? 'Not assigned'}'),
                const SizedBox(height: 8),
                Text(
                  'Location: ${hazard.latitude.toStringAsFixed(5)}, ${hazard.longitude.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 8),
                Text('Reviewed: ${hazard.updatedAt.toLocal()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
