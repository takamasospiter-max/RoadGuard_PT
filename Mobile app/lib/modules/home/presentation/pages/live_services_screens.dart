import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:roadguard_ai/modules/trips/presentation/providers/navigation_guide.dart';
import 'package:roadguard_ai/modules/trips/presentation/providers/route_hazard_alert.dart';
import 'package:roadguard_ai/modules/home/presentation/providers/route_alerts_provider.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/services/trip_collection.dart';
import 'package:roadguard_ai/core/services/telemetry_service.dart';
import 'package:roadguard_ai/core/services/voice_service.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/live_road_map.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';
import 'package:roadguard_ai/shared/widgets/map_actions.dart';
import 'package:roadguard_ai/modules/planner/presentation/pages/place_search_sheet.dart';
import 'package:roadguard_ai/core/utils/trip_time.dart';

import '../providers/map_location_session.dart';

final latestPublicHazardsProvider =
    NotifierProvider<HazardSnapshot, List<PublicHazard>>(HazardSnapshot.new);

class HazardSnapshot extends Notifier<List<PublicHazard>> {
  @override
  List<PublicHazard> build() => [];
  void replace(List<PublicHazard> value) => state = value;
}

/// The red ⚠ map marker for a public hazard, the same on every map (Explore,
/// route preview, live trip). Tapping it zooms to about ±30 m around the
/// hazard, then shows its details.
Marker publicHazardMarker(
  BuildContext context,
  MapController map,
  PublicHazard hazard, {
  Key? key,
}) => Marker(
  key: key,
  point: LatLng(hazard.latitude, hazard.longitude),
  width: 48,
  height: 48,
  child: IconButton(
    tooltip: hazard.confirmedByOfficer
        ? 'Confirmed ${hazard.kind.label}'
        : '${hazard.kind.label} reported by drivers',
    onPressed: () {
      focusMapOn(map, LatLng(hazard.latitude, hazard.longitude));
      showPublicHazard(context, hazard);
    },
    icon: Icon(Icons.warning_rounded, color: RoadColors.red, size: 32),
  ),
);

void showPublicHazard(
  BuildContext context,
  PublicHazard hazard,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    // Only an officer's review makes a hazard "confirmed"; crowd spots are
    // "reported by drivers" (the same wording as the map markers).
    title: Text(
      hazard.confirmedByOfficer
          ? 'Confirmed ${hazard.kind.label.toLowerCase()}'
          : '${hazard.kind.label} reported by drivers',
    ),
    content: Text(
      'Severity: ${hazard.severity ?? 'Not assigned'}\nNear ${hazard.latitude.toStringAsFixed(4)}, ${hazard.longitude.toStringAsFixed(4)}\nUpdated: ${hazard.updatedAt.toLocal()}\n\n'
      '${hazard.confirmedByOfficer ? 'Confirmed by a road officer.' : 'Detected by several drivers’ phones; not yet checked by an officer.'}'
      ' This is not a proximity or collision warning.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class LiveExploreScreen extends ConsumerStatefulWidget {
  const LiveExploreScreen({super.key});
  @override
  ConsumerState<LiveExploreScreen> createState() => _LiveExploreScreenState();
}

class _LiveExploreScreenState extends ConsumerState<LiveExploreScreen>
    with WidgetsBindingObserver {
  final _map = MapController();
  late final MapLocationSession _location;
  late final GoRouter _router;
  Timer? _poll;
  List<PublicHazard> _hazards = [];
  Map<String, double> _bounds = {
    'west': 39.1,
    'south': -6.95,
    'east': 39.4,
    'north': -6.6,
  };
  String _status = 'Loading confirmed hazards…';
  bool _loading = false, _foreground = true, _ready = false;
  bool _centerNextFix = false, _zoomTooWide = false;
  bool _selectingDestination = false;
  int _version = 0;
  bool get _visible =>
      _foreground &&
      _router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ==
          HomePaths.explore;
  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(_routeChanged);
    _location = MapLocationSession(ref.read(locationServiceProvider))
      ..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_visible) unawaited(_refresh());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _changed() {
    if (!mounted) return;
    final fix = _location.fix;
    if (_centerNextFix && _ready && fix != null) {
      _centerNextFix = false;
      _map.move(LatLng(fix.latitude, fix.longitude), 16);
    }
    setState(() {});
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
    if (place != null && mounted) {
      unawaited(context.push(PlannerPaths.plan, extra: place));
    }
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

  void _routeChanged() {
    if (!_visible) {
      _location.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _location.stop();
    } else if (_visible) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_loading || !mounted || !_visible || _zoomTooWide) return;
    _loading = true;
    final version = _version;
    try {
      final items = await ref.read(roadApiProvider).hazards(Map.from(_bounds));
      if (!mounted || version != _version || !_visible) return;
      ref.read(latestPublicHazardsProvider.notifier).replace(items);
      setState(() {
        _hazards = items;
        _status = items.isEmpty
            ? 'No confirmed hazards in this view'
            // Not all shown hazards are officer-confirmed (crowd-reported ones
            // are too), so the count doesn't call them all "confirmed".
            : '${items.length}${items.length == 100 ? '+' : ''} hazard${items.length == 1 ? '' : 's'} · refreshed now';
      });
    } catch (_) {
      if (!mounted || version != _version || !_visible) return;
      if (mounted) {
        setState(() {
          _status = 'Hazards unavailable · tap refresh to retry';
          _hazards = [];
        });
      }
      if (mounted) ref.read(latestPublicHazardsProvider.notifier).replace([]);
    } finally {
      _loading = false;
    }
  }

  void _updateBounds(MapCamera camera, bool gesture) {
    final b = camera.visibleBounds;
    _version++;
    final valid =
        b.east - b.west <= 5 &&
        b.north - b.south <= 5 &&
        b.west < b.east &&
        b.west >= -180 &&
        b.east <= 180 &&
        b.south >= -90 &&
        b.north <= 90;
    setState(() {
      _zoomTooWide = !valid;
      _hazards = [];
      _status = valid
          ? 'Map moved · awaiting hazard refresh'
          : 'Zoom in to load confirmed hazards';
      if (valid) {
        _bounds = {
          'west': b.west,
          'south': b.south,
          'east': b.east,
          'north': b.north,
        };
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _location.removeListener(_changed);
    _location.dispose();
    _router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trip = ref.watch(tripProvider);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LiveRoadMap(
                  height: double.infinity,
                  fullBleed: true,
                  showAttribution: false,
                  controller: _map,
                  location: _location.fix,
                  onTap: (_, point) => _selectMapPoint(point),
                  onMapReady: () {
                    _ready = true;
                    _updateBounds(_map.camera, false);
                  },
                  onPositionChanged: _updateBounds,
                  overlays: [
                    MarkerLayer(
                      markers: [
                        for (final h in _hazards)
                          publicHazardMarker(context, _map, h),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _selectingDestination
                    ? Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        elevation: 4,
                        child: ListTile(
                          leading: const Icon(Icons.add_location_alt_outlined),
                          title: const Text(
                            'Tap the map to choose a destination',
                          ),
                          trailing: IconButton(
                            tooltip: 'Cancel map selection',
                            onPressed: () =>
                                setState(() => _selectingDestination = false),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          MapSearchBar(
                            actionKey: const Key('live-plan'),
                            onTap: _openPlaceSearch,
                          ),
                          const SizedBox(height: 8),
                          Material(
                            borderRadius: BorderRadius.circular(18),
                            elevation: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _status,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Refresh hazards',
                                    onPressed: _refresh,
                                    icon: const Icon(Icons.refresh),
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
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _location.active || _location.error != null
                          ? Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * .3,
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _location.error?.toString() ??
                                        (_location.fix == null
                                            ? 'Waiting for location…'
                                            : 'Location accuracy ±${_location.fix!.accuracyMeters.round()} m'),
                                    key: const Key('map-location-status'),
                                    style: TextStyle(
                                      color: _location.error == null
                                          ? scheme.onSurface
                                          : scheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 12),
                    MapActionButtons(
                      onDirections: () => context.push(PlannerPaths.plan),
                      locationActive: _location.active,
                      onLocate: _location.requesting
                          ? null
                          : () async {
                              if (_location.active) {
                                _location.stop();
                              } else {
                                _centerNextFix = true;
                                await _location.start();
                              }
                            },
                      onReport: () => context.push(ReportPaths.create),
                      onResume: trip == null
                          ? null
                          : () => context.push(TripPaths.active),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const MapAttribution(),
      ],
    );
  }
}

class LivePlannerScreen extends ConsumerStatefulWidget {
  const LivePlannerScreen({super.key, this.destination});
  final PlaceResult? destination;
  @override
  ConsumerState<LivePlannerScreen> createState() => _LivePlannerScreenState();
}

class _LivePlannerScreenState extends ConsumerState<LivePlannerScreen> {
  List<double>? _start, _end;
  String? _startLabel, _endLabel;
  final _map = MapController();
  bool _mapReady = false;
  @override
  void initState() {
    super.initState();
    if (widget.destination != null) {
      _end = widget.destination!.coordinates;
      _endLabel = widget.destination!.label;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadDirectionsFromLocation());
      });
    }
  }

  Future<void> _loadDirectionsFromLocation() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(roadApiProvider);
      if (!api.configured) {
        throw StateError(
          'Live routing is unavailable. Try again when the route service is connected.',
        );
      }
      final location = ref.read(locationServiceProvider);
      await location.requestAccess();
      if (!mounted) return;
      final fix = await location.watch().first.timeout(
        const Duration(seconds: 12),
      );
      if (fix.isMocked ||
          !fix.latitude.isFinite ||
          !fix.longitude.isFinite ||
          !fix.accuracyMeters.isFinite ||
          fix.accuracyMeters > 100 ||
          DateTime.now().difference(fix.observedAt).abs() >
              const Duration(seconds: 10)) {
        throw StateError(
          'Current location is not accurate enough. Choose a starting point.',
        );
      }
      if (!mounted || _start != null) return;
      setState(() {
        _start = [fix.longitude, fix.latitude];
        _startLabel = 'My location';
      });
      if (_mapReady) _map.move(LatLng(fix.latitude, fix.longitude), 13);
      final routes = await api.routes(
        _start!,
        _end!,
        originLabel: _startLabel,
        destinationLabel: _endLabel,
      );
      if (mounted) {
        final liveRoutes = routes
            .where((route) => route.coordinates.length >= 2)
            .toList();
        unawaited(_loadRouteHazards(liveRoutes));
        setState(() {
          _routes = liveRoutes;
          _selectedRouteId = liveRoutes.firstOrNull?.id;
          if (liveRoutes.isEmpty) {
            _error = routes.isEmpty
                ? 'No driving route found. Choose another starting point.'
                : 'The route service did not return live map geometry. Try again later.';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message.toString() : 'Could not find a live route. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Hazards on each route option (by route id), shown on the route preview
  /// so travellers can pick a route that avoids them.
  Map<String, List<PublicHazard>> _hazardsByRoute = {};

  Future<void> _loadRouteHazards(List<RouteOption> routes) async {
    final api = ref.read(roadApiProvider);
    final found = await Future.wait(
      routes.map((route) => fetchRouteHazards(api, route)),
    );
    if (!mounted) return;
    setState(
      () => _hazardsByRoute = {
        for (var i = 0; i < routes.length; i++) routes[i].id: found[i],
      },
    );
  }

  bool _busy = false;
  List<RouteOption> _routes = [];
  String? _selectedRouteId;
  RouteOption? get _chosenRoute =>
      _routes.where((route) => route.id == _selectedRouteId).firstOrNull ??
      _routes.firstOrNull;

  String? _error;
  @override
  Widget build(BuildContext context) {
    final route = _chosenRoute;
    final end = _end;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Stack(
        children: [
          Positioned.fill(
            child: route == null
                ? LiveRoadMap(
                    fullBleed: true,
                    showAttribution: false,
                    controller: _map,
                    onMapReady: () {
                      _mapReady = true;
                      if (_start != null) {
                        _map.move(LatLng(_start![1], _start![0]), 13);
                      } else if (end != null) {
                        _map.move(LatLng(end[1], end[0]), 13);
                      }
                    },
                    overlays: end == null
                        ? const []
                        : [
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(end[1], end[0]),
                                  width: 48,
                                  height: 48,
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    size: 42,
                                    color: RoadColors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                  )
                : RouteMap(
                    route: route,
                    hazards: _hazardsByRoute[route.id] ?? const [],
                  ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            left: 16,
            right: 16,
            child: _RoutePlacesCard(
              origin: _startLabel ?? 'Your location',
              destination:
                  widget.destination?.label ??
                  'Select a destination from Explore',
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.paddingOf(context).bottom + 18,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 14,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7DFE1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (route != null) ...[
                    Text(
                      '${formatTripMinutes(route.minutes)}  ·  ${route.kilometers.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2B36),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'To ${route.destinationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF607984),
                      ),
                    ),
                    if (_routes.length > 1) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Route options',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      for (final entry in _routes.take(3).indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () =>
                                setState(() => _selectedRouteId = entry.$2.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedRouteId == entry.$2.id
                                    ? RoadColors.sky
                                    : const Color(0xFFF5F7F8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _selectedRouteId == entry.$2.id
                                      ? RoadColors.blue
                                      : const Color(0xFFE1E8E8),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedRouteId == entry.$2.id
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    color: RoadColors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      entry.$1 == 0
                                          ? 'Recommended route'
                                          : 'Alternative ${entry.$1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${formatTripMinutes(entry.$2.minutes)} · ${entry.$2.kilometers.toStringAsFixed(1)} km',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ] else
                    Text(
                      _busy
                          ? 'Finding your route…'
                          : (_error ??
                                (widget.destination == null
                                    ? 'Choose a destination from Explore'
                                    : 'Route details will appear here')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: _error == null
                            ? const Color(0xFF607984)
                            : const Color(0xFFB3261E),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('start-trip'),
                      onPressed: _busy || route == null
                          ? null
                          : () => runAction(context, () async {
                              await ref
                                  .read(tripProvider.notifier)
                                  .start(route);
                              if (context.mounted) context.go(TripPaths.active);
                            }),
                      style: FilledButton.styleFrom(
                        backgroundColor: RoadColors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(58),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _busy ? 'Loading…' : 'Start',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePlacesCard extends StatelessWidget {
  const _RoutePlacesCard({required this.origin, required this.destination});
  final String origin, destination;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 5,
    borderRadius: BorderRadius.circular(26),
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.my_location_rounded,
                color: RoadColors.blue,
                size: 23,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: Color(0xFF82949B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2B36),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 39, right: 4, top: 12, bottom: 12),
            child: Divider(height: 1, color: Color(0xFFE0E7EA)),
          ),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: RoadColors.blue,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TO',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: Color(0xFF82949B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2B36),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.route,
    this.location,
    this.followLocation = false,
    this.onMapGesture,
    this.hazards = const [],
  });
  final RouteOption route;
  final GpsFix? location;

  /// Public hazards near the route; only those on it are marked
  /// (hazardsAlongRoute), so drivers see what's coming along the way.
  final List<PublicHazard> hazards;
  final bool followLocation;
  final VoidCallback? onMapGesture;
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _map = MapController();
  bool _ready = false;
  bool _following = false;

  void _positionCamera() {
    if (!_ready || !mounted) return;
    final fix = widget.location;
    if (widget.followLocation && fix != null) {
      _map.move(
        LatLng(fix.latitude, fix.longitude),
        _following ? _map.camera.zoom : 16,
      );
      _following = true;
    } else if (!widget.followLocation) {
      _following = false;
    }
  }

  @override
  void didUpdateWidget(covariant RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route.id != oldWidget.route.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_ready || !mounted) return;
        final points = widget.route.coordinates
            .map((point) => LatLng(point[1], point[0]))
            .toList();
        if (points.length > 1) {
          _map.fitCamera(
            CameraFit.coordinates(
              coordinates: points,
              padding: const EdgeInsets.all(36),
            ),
          );
        }
      });
    }
    if (widget.location != oldWidget.location ||
        widget.followLocation != oldWidget.followLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _positionCamera());
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.route.coordinates
        .map((p) => LatLng(p[1], p[0]))
        .toList();
    return LiveRoadMap(
      height: double.infinity,
      controller: _map,
      location: widget.location,
      onPositionChanged: (_, gesture) {
        if (gesture) widget.onMapGesture?.call();
      },
      onMapReady: () {
        _ready = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (points.length > 1) {
            _map.fitCamera(
              CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(36),
              ),
            );
          }
          _positionCamera();
        });
      },
      overlays: [
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 5,
              color: RoadColors.blue,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final p
                in points.isEmpty ? <LatLng>[] : [points.first, points.last])
              Marker(
                point: p,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 32,
                ),
              ),
          ],
        ),
        // Hazards on the route, drawn above the start/end pins.
        MarkerLayer(
          markers: [
            for (final h in hazardsAlongRoute(widget.route, widget.hazards))
              publicHazardMarker(
                context,
                _map,
                h,
                key: Key('route-hazard-${h.id}'),
              ),
          ],
        ),
      ],
    );
  }
}

class LiveTripScreen extends ConsumerStatefulWidget {
  const LiveTripScreen({super.key, required this.trip});
  final TripRecord trip;
  @override
  ConsumerState<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends ConsumerState<LiveTripScreen>
    with WidgetsBindingObserver {
  late final MapLocationSession _location;
  late final GoRouter _router;
  bool _foreground = true, _follow = true;
  bool _fetchingHazards = false;
  DateTime? _lastHazardFetch;
  List<PublicHazard> _nearbyHazards = [];
  // Hazards along the whole route, fetched at the start and after a reroute,
  // so the map shows them before the driver gets near.
  List<PublicHazard> _routeHazards = [];

  /// Route hazards plus the latest nearby ones (which may be newer), each
  /// once: drawn on the map and checked for proximity alerts.
  List<PublicHazard> get _knownHazards => {
    for (final h in [..._routeHazards, ..._nearbyHazards]) h.id: h,
  }.values.toList();

  Future<void> _loadRouteHazards() async {
    final route = widget.trip.route;
    final hazards = await fetchRouteHazards(ref.read(roadApiProvider), route);
    // Ignore a reply for a route that has since been replaced by a reroute.
    if (!mounted || ref.read(tripProvider)?.route.id != route.id) return;
    setState(() => _routeHazards = hazards);
    _evaluateHazards();
  }

  final Set<String> _alertedHazardIds = {};
  RouteHazardAlert? _visibleHazard;
  Timer? _hideHazard;
  GpsFix? _previousHazardFix;
  bool _movingAlongRoute = false;

  // --- Turn-by-turn navigation (see navigation_guide.dart) ---
  NavigationProgress?
  _progress; // where we are and what's next; null = no guidance yet
  final OffRouteMonitor _offRoute = OffRouteMonitor();
  GuidanceAnnouncer _announcer = GuidanceAnnouncer();
  bool _rerouting = false;
  DateTime? _lastRerouteAt;
  String? _rerouteMessage; // shown in the banner while/after rerouting
  DateTime?
  _lastHazardSpokenAt; // directions wait a moment after a hazard warning
  bool _showSensorPanel = false;

  /// Recompute navigation for the latest fix: progress, off-route check,
  /// and any spoken direction that is now due.
  void _updateNavigation() {
    final fix = _location.fix;
    final route = widget.trip.route;
    if (fix == null || widget.trip.paused || !_visible || !route.hasGuidance) {
      return;
    }
    final progress = navigationProgress(fix: fix, route: route);
    if (progress == null) return;
    _progress = progress;
    // Clearly off the planned route for several fixes → ask for a new route.
    if (!progress.arrived &&
        _offRoute.update(
          offRouteMeters: progress.offRouteMeters,
          accuracyMeters: fix.accuracyMeters,
        )) {
      unawaited(_reroute(fix));
      return;
    }
    // Directions only make sense while the driver is on the route.
    if (progress.offRouteMeters > 50) return;
    final text = _announcer.next(progress, speedMps: fix.speedMps);
    if (text != null) unawaited(_speakGuidance(text));
  }

  Future<void> _speakGuidance(String text) async {
    if (!ref.read(settingsProvider).voiceEnabled) return;
    final voice = ref.read(voiceServiceProvider);
    if (voice is! NavigationVoiceService) return;
    // Don't talk over a hazard warning: wait until it has finished.
    final lastWarning = _lastHazardSpokenAt;
    if (lastWarning != null) {
      final wait =
          const Duration(seconds: 5) - DateTime.now().difference(lastWarning);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    if (!mounted || !_visible || widget.trip.paused) return;
    try {
      await (voice as NavigationVoiceService).speakGuidance(text);
    } catch (_) {
      // A missing TTS engine must not break the on-screen guidance.
    }
  }

  /// Ask the backend for a new route from here to the same destination.
  Future<void> _reroute(GpsFix fix) async {
    final now = DateTime.now();
    if (_rerouting ||
        (_lastRerouteAt != null &&
            now.difference(_lastRerouteAt!) < const Duration(seconds: 30))) {
      return;
    }
    final api = ref.read(roadApiProvider);
    final route = widget.trip.route;
    if (!api.configured || route.coordinates.isEmpty) return;
    _lastRerouteAt = now;
    setState(() {
      _rerouting = true;
      _rerouteMessage = 'Rerouting…';
    });
    unawaited(_speakGuidance('Rerouting.'));
    try {
      final options = await api.routes(
        [fix.longitude, fix.latitude],
        route.coordinates.last, // same destination
        originLabel: 'Current location',
        destinationLabel: route.destination,
      );
      if (options.isEmpty) throw StateError('No route found.');
      if (!mounted || ref.read(tripProvider)?.id != widget.trip.id) return;
      await ref.read(tripProvider.notifier).reroute(options.first);
      _offRoute.reset();
      _announcer = GuidanceAnnouncer(); // new route, new set of prompts
      _rerouteMessage = null;
    } catch (_) {
      // Keep the old route on screen; try again after the 30-second pause.
      _rerouteMessage =
          'Could not find a new route. Head back to the blue route.';
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  void _evaluateHazards() {
    final fix = _location.fix;
    if (!mounted ||
        !_visible ||
        widget.trip.paused ||
        fix == null ||
        !_movingAlongRoute ||
        _visibleHazard != null) {
      return;
    }
    final match = nearestRouteHazard(
      fix: fix,
      route: widget.trip.route,
      hazards: _knownHazards,
      alreadyAlerted: _alertedHazardIds,
    );
    if (match == null) return;
    _alertedHazardIds.add(match.hazard.id);
    final ownerKey = ref.read(authProvider).asData?.value?.id ?? 'guest';
    final alert = RouteAlertRecord(
      id: '$ownerKey/${widget.trip.id}/${match.hazard.id}',
      tripId: widget.trip.id,
      ownerKey: ownerKey,
      hazardId: match.hazard.id,
      kind: match.hazard.kind,
      severity: match.hazard.severity,
      distanceMeters: match.distanceMeters,
      receivedAt: DateTime.now(),
    );
    unawaited(_rememberAlert(alert));
    unawaited(_speakRouteAlert(match));
    _hideHazard?.cancel();
    setState(() => _visibleHazard = match);
    _hideHazard = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visibleHazard = null);
    });
  }

  Future<void> _speakRouteAlert(RouteHazardAlert alert) async {
    if (!ref.read(settingsProvider).voiceEnabled) return;
    final voice = ref.read(voiceServiceProvider);
    if (voice is! RouteAlertVoiceService) return;
    _lastHazardSpokenAt = DateTime.now();
    try {
      await (voice as RouteAlertVoiceService).speakRouteAlert(
        hazard: alert.hazard.kind.label,
        distanceMeters: alert.distanceMeters,
        // Only say "confirmed" when a road officer verified it.
        confirmedByOfficer: alert.hazard.confirmedByOfficer,
      );
    } catch (_) {
      // An unavailable TTS engine must not suppress the visual route warning.
    }
  }

  void _stopVoice() => unawaited(_stopVoiceSafely());

  Future<void> _stopVoiceSafely() async {
    try {
      await ref.read(voiceServiceProvider).stop();
    } catch (_) {
      // Audio cleanup must not interrupt trip controls or screen transitions.
    }
  }

  Future<void> _rememberAlert(RouteAlertRecord alert) async {
    try {
      await ref.read(localStoreProvider).saveRouteAlert(alert);
      if (mounted) ref.invalidate(routeAlertsProvider(alert.ownerKey));
    } catch (_) {
      // A storage error never blocks the visible warning while driving.
    }
  }

  Future<void> _refreshNearbyHazards() async {
    final fix = _location.fix;
    if (fix == null ||
        !_visible ||
        widget.trip.paused ||
        widget.trip.route.coordinates.length < 2 ||
        _fetchingHazards) {
      return;
    }
    final now = DateTime.now();
    if (_lastHazardFetch != null &&
        now.difference(_lastHazardFetch!) < const Duration(seconds: 15)) {
      return;
    }
    _fetchingHazards = true;
    _lastHazardFetch = now;
    try {
      // A small viewport around the current GPS fix; the server returns only
      // confirmed public hazards. Recheck the route after the response arrives.
      final latitudeDelta = 0.004;
      final longitudeDelta =
          0.004 / math.cos(fix.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
      final hazards = await ref.read(roadApiProvider).hazards({
        'west': (fix.longitude - longitudeDelta)
            .clamp(-180.0, 180.0)
            .toDouble(),
        'east': (fix.longitude + longitudeDelta)
            .clamp(-180.0, 180.0)
            .toDouble(),
        'south': (fix.latitude - latitudeDelta).clamp(-90.0, 90.0).toDouble(),
        'north': (fix.latitude + latitudeDelta).clamp(-90.0, 90.0).toDouble(),
      });
      if (!mounted || !_visible || widget.trip.paused) return;
      _nearbyHazards = hazards;
      _evaluateHazards();
    } catch (_) {
      // No warning is inferred when the hazard service is unavailable.
      _nearbyHazards = [];
    } finally {
      _fetchingHazards = false;
    }
  }

  bool get _visible =>
      _foreground &&
      _router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ==
          TripPaths.active;

  @override
  void initState() {
    super.initState();
    _location = MapLocationSession(ref.read(locationServiceProvider))
      ..addListener(_changed);
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(_routeChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLocation();
      unawaited(_loadRouteHazards());
    });
  }

  void _changed() {
    if (!mounted) return;
    final fix = _location.fix;
    _movingAlongRoute =
        fix != null &&
        _previousHazardFix != null &&
        advancingOnRoute(_previousHazardFix!, fix, widget.trip.route);
    _previousHazardFix = fix;
    _updateNavigation();
    setState(() {});
    _evaluateHazards();
    unawaited(_refreshNearbyHazards());
  }

  void _startLocation() {
    if (!mounted || !_visible || widget.trip.paused) return;
    setState(() => _follow = true);
    unawaited(_location.start());
  }

  void _routeChanged() {
    if (!_visible) {
      _location.stop();
      _stopVoice();
      _hideHazard?.cancel();
      _visibleHazard = null;
      _previousHazardFix = null;
      _movingAlongRoute = false;
      _offRoute.reset();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's permission dialog temporarily makes the app inactive. An actual
    // background transition still cancels the pending permission generation.
    if (state == AppLifecycleState.inactive && _location.requesting) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _location.stop();
      _stopVoice();
      _hideHazard?.cancel();
      _visibleHazard = null;
      _previousHazardFix = null;
      _movingAlongRoute = false;
      _offRoute.reset();
    }
  }

  @override
  void didUpdateWidget(covariant LiveTripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.route.id != widget.trip.route.id) {
      // A new route after rerouting: recompute guidance against it, and
      // mark the hazards along the new route (the old ones may be off it).
      _progress = null;
      _updateNavigation();
      _routeHazards = [];
      unawaited(_loadRouteHazards());
    }
    if (widget.trip.paused) {
      _hideHazard?.cancel();
      _visibleHazard = null;
      _location.stop();
      _stopVoice();
    } else if (oldWidget.trip.paused) {
      _startLocation();
    }
  }

  @override
  void dispose() {
    _hideHazard?.cancel();
    _stopVoice();
    _router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _location.removeListener(_changed);
    _location.dispose();
    super.dispose();
  }

  /// The top banner: the next manoeuvre while navigating ("300 m · Turn left
  /// onto Morogoro Road"), otherwise the destination and trip status.
  Widget _directionBanner(TripRecord trip) {
    const white = TextStyle(color: Colors.white, fontSize: 12);
    final progress = _progress;
    final guiding = !trip.paused && trip.route.hasGuidance && progress != null;

    final IconData icon;
    final String title;
    final String subtitle;
    if (!guiding) {
      icon = Icons.arrow_upward_rounded;
      title = 'Heading to ${trip.route.destinationLabel}';
      subtitle = trip.paused
          ? 'Trip paused · location stopped'
          : trip.route.hasGuidance
          ? 'Waiting for GPS to start turn-by-turn guidance'
          : 'Following route · no turn-by-turn guidance';
    } else if (progress.arrived) {
      icon = Icons.flag_rounded;
      title = 'You have arrived';
      subtitle = trip.route.destinationLabel;
    } else {
      icon = maneuverIcon(progress.nextStep);
      title =
          '${shortDistance(progress.distanceToNextStep)} · ${progress.nextStep.instruction}';
      subtitle =
          _rerouteMessage ??
          (progress.thenStep != null
              ? 'Then ${progress.thenStep!.instruction.toLowerCase()}'
              : 'Towards ${trip.route.destinationLabel}');
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        key: const Key('trip-direction-banner'),
        children: [
          _rerouting
              ? const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final fix = _location.fix;
    final account = ref.watch(authProvider).asData?.value;
    // Live remaining time/distance once guidance is running; the route's
    // planned totals before the first GPS fix (or without guidance data).
    final progress = trip.paused ? null : _progress;
    final remainingMinutes = progress == null
        ? trip.route.minutes
        : (progress.remainingSeconds / 60).ceil();
    final remainingKm = progress == null
        ? trip.route.kilometers.toStringAsFixed(0)
        : (progress.remainingMeters / 1000).toStringAsFixed(
            progress.remainingMeters < 10000 ? 1 : 0,
          );
    final arrival = DateTime.now().add(Duration(minutes: remainingMinutes));
    final arrivalTime = TimeOfDay.fromDateTime(arrival).format(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RouteMap(
              route: trip.route,
              hazards: _knownHazards,
              location: fix,
              followLocation: _follow,
              onMapGesture: () {
                if (_follow) setState(() => _follow = false);
              },
            ),
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Material(
                color: RoadColors.tripBanner,
                borderRadius: BorderRadius.circular(20),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  child: _directionBanner(trip),
                ),
              ),
            ),
            if (_visibleHazard != null)
              Positioned(
                top: 120,
                left: 20,
                right: 20,
                child: Semantics(
                  liveRegion: true,
                  label: _visibleHazard!.hazard.confirmedByOfficer
                      ? 'Confirmed ${_visibleHazard!.hazard.kind.label.toLowerCase()} warning'
                      : '${_visibleHazard!.hazard.kind.label} reported by other drivers',
                  child: Material(
                    key: const Key('trip-live-hazard-alert'),
                    color: const Color(0xFFF5B82E),
                    borderRadius: BorderRadius.circular(18),
                    elevation: 7,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFF173441),
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_visibleHazard!.hazard.kind.label} ahead',
                                  style: const TextStyle(
                                    color: Color(0xFF173441),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'About ${_visibleHazard!.distanceMeters} m · Slow down and drive carefully',
                                  style: const TextStyle(
                                    color: Color(0xFF173441),
                                    fontSize: 12,
                                  ),
                                ),
                                // Who vouches for it: an officer, or other drivers' phones.
                                Text(
                                  _visibleHazard!.hazard.confirmedByOfficer
                                      ? 'Confirmed by road officers'
                                      : 'Reported by ${_visibleHazard!.hazard.deviceCount} drivers · not yet verified',
                                  style: const TextStyle(
                                    color: Color(0xFF173441),
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // My location button + panel in one column at the bottom, so the
            // button always sits just above the panel whatever its height
            // (e.g. with the sensor-sharing controls open) and is never covered.
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 10),
                    child: Material(
                      elevation: 5,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: IconButton(
                        key: const Key('trip-recenter'),
                        tooltip: 'Follow my location',
                        onPressed: trip.paused || _location.requesting
                            ? null
                            : _startLocation,
                        icon: Icon(
                          _follow && fix != null
                              ? Icons.gps_fixed_rounded
                              : Icons.my_location_rounded,
                          color: RoadColors.blue,
                        ),
                      ),
                    ),
                  ),
                  // Never taller than 55 % of the screen (large text on a
                  // small phone would otherwise cover the map and banner).
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .55,
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                      decoration: const BoxDecoration(
                        color: Color(0xFF07131B),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                          bottom: Radius.circular(28),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Optional sensor sharing (signed-in drivers). Kept mounted
                                  // for the whole trip — hiding the panel doesn't stop
                                  // collection; leaving the screen or pausing does.
                                  if (account != null)
                                    Visibility(
                                      visible: _showSensorPanel,
                                      maintainState: true,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight:
                                              MediaQuery.sizeOf(context)
                                                  .height *
                                              .4,
                                        ),
                                        child: SingleChildScrollView(
                                          child: CollectionControls(
                                            key: ValueKey(
                                              '${trip.id}/${account.id}',
                                            ),
                                            trip: trip,
                                            ownerId: account.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Text(
                                    formatTripMinutes(remainingMinutes),
                                    style: const TextStyle(
                                      color: RoadColors.tripEta,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '$remainingKm km · estimated arrival $arrivalTime',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  // Live GPS status: the problem (with a way to fix it) if
                                  // location isn't working, otherwise the current speed.
                                  if (!trip.paused &&
                                      _location.error != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _location.error!,
                                      key: const Key('trip-location-error'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFFFB4AB),
                                      ),
                                    ),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        TextButton(
                                          onPressed: _startLocation,
                                          child: const Text('Retry location'),
                                        ),
                                        TextButton(
                                          onPressed: () => unawaited(
                                            _location.openSettings(),
                                          ),
                                          child: const Text(
                                            'Open location settings',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (!trip.paused &&
                                      fix != null &&
                                      fix.speedMps.isFinite &&
                                      fix.speedMps >= 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${(fix.speedMps * 3.6).round()} km/h',
                                      key: const Key('trip-live-speed'),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                  if (account != null)
                                    TextButton.icon(
                                      key: const Key('trip-sensor-sharing'),
                                      onPressed: () => setState(
                                        () => _showSensorPanel =
                                            !_showSensorPanel,
                                      ),
                                      icon: const Icon(
                                        Icons.sensors_rounded,
                                        color: Colors.white70,
                                      ),
                                      label: Text(
                                        _showSensorPanel
                                            ? 'Hide sensor sharing'
                                            : 'Sensor sharing',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Wrap (not Row): with large text on a narrow phone the
                          // two buttons go onto separate lines instead of overflowing.
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () => runAction(
                                  context,
                                  () => ref
                                      .read(tripProvider.notifier)
                                      .togglePause(),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF203743),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(trip.paused ? 'Resume' : 'Pause'),
                              ),
                              FilledButton(
                                onPressed: () => runAction(context, () async {
                                  await ref.read(tripProvider.notifier).end();
                                  if (context.mounted) {
                                    context.go(TripPaths.history);
                                  }
                                }),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF203743),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Finish trip'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .48,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RouteMap(
                      route: trip.route,
                      location: fix,
                      followLocation: _follow,
                      onMapGesture: () {
                        if (_follow) setState(() => _follow = false);
                      },
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      color: const Color(0xFF102C42),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Heading to ${trip.route.destinationLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    trip.paused ? 'Trip paused' : 'Following route · no turn-by-turn guidance',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_visibleHazard != null)
                    Positioned(
                      top: 90,
                      left: 12,
                      right: 12,
                      child: Semantics(
                        liveRegion: true,
                        child: Material(
                          key: const Key('trip-live-hazard-alert'),
                          elevation: 8,
                          color: const Color(0xFFF5C66D),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 28, color: Color(0xFF8C4D00)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_visibleHazard!.hazard.kind.label} ahead',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Color(0xFF173441),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'About ${_visibleHazard!.distanceMeters} m · Slow down and drive carefully',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5E707A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: _visibleHazard == null ? 42 : 110,
                    child: Material(
                      elevation: 4,
                      shape: const CircleBorder(),
                      color: Theme.of(context).colorScheme.surface,
                      child: IconButton(
                        key: const Key('trip-recenter'),
                        tooltip: 'Follow my location',
                        onPressed: trip.paused || _location.requesting
                            ? null
                            : _startLocation,
                        icon: Icon(
                          _follow && fix != null ? Icons.gps_fixed_rounded : Icons.my_location_rounded,
                          color: const Color(0xFF173441),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              trip.paused
                  ? 'Location paused with your trip.'
                  : _location.error ??
                        (fix == null
                            ? _location.message
                            : '${_follow ? 'Following your location' : 'Live location · tap the target to follow'} · accuracy ±${fix.accuracyMeters.ceil()} m'),
              key: const Key('trip-location-status'),
              style: TextStyle(
                color: _location.error == null ? null : Theme.of(context).colorScheme.error,
              ),
            ),
            if (_location.error != null && !trip.paused)
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: _startLocation,
                    child: const Text('Retry location'),
                  ),
                  TextButton(
                    onPressed: () => _location.openSettings(),
                    child: const Text('Open location settings'),
                  ),
                ],
              ),
            if (fix != null && fix.speedMps.isFinite && fix.speedMps >= 0)
              Text(
                '${(fix.speedMps * 3.6).round()} km/h',
                key: const Key('trip-live-speed'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.route.kilometers.toStringAsFixed(1)} km · estimated ${formatTripMinutes(trip.route.minutes)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: RoadColors.sky,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live route',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: RoadColors.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${trip.route.originLabel} → ${trip.route.destinationLabel}',
              style: const TextStyle(
                color: Color(0xFF5E707A),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            if (account == null)
              const Text(
                'Sign in from Profile to enable optional sensor sharing.',
              )
            else
              CollectionControls(
                key: ValueKey('${trip.id}/${account.id}'),
                trip: trip,
                ownerId: account.id,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
*/

/// The arrow shown in the navigation banner for a manoeuvre.
IconData maneuverIcon(RouteStep step) {
  final modifier = step.modifier;
  final left = modifier.contains('left');
  switch (step.type) {
    case 'arrive':
      return Icons.flag_rounded;
    case 'depart':
      return Icons.navigation_rounded;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
    case 'exit roundabout':
    case 'exit rotary':
      return left ? Icons.roundabout_left : Icons.roundabout_right;
    case 'merge':
      return Icons.merge;
    case 'fork':
      return left ? Icons.fork_left : Icons.fork_right;
    case 'on ramp':
    case 'off ramp':
      return left ? Icons.ramp_left : Icons.ramp_right;
  }
  switch (modifier) {
    case 'uturn':
      return Icons.u_turn_left;
    case 'sharp left':
      return Icons.turn_sharp_left;
    case 'left':
      return Icons.turn_left;
    case 'slight left':
      return Icons.turn_slight_left;
    case 'sharp right':
      return Icons.turn_sharp_right;
    case 'right':
      return Icons.turn_right;
    case 'slight right':
      return Icons.turn_slight_right;
    default:
      return Icons.straight;
  }
}

class CollectionControls extends ConsumerStatefulWidget {
  const CollectionControls({
    super.key,
    required this.trip,
    required this.ownerId,
  });
  final TripRecord trip;
  final String ownerId;
  @override
  ConsumerState<CollectionControls> createState() => _CollectionControlsState();
}

class _CollectionControlsState extends ConsumerState<CollectionControls>
    with WidgetsBindingObserver {
  late final TripCollection _collection;
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _collection = TripCollection(
      auth: ref.read(authServiceProvider),
      store: ref.read(localStoreProvider),
      location: ref.read(locationServiceProvider),
      permissions: ref.read(permissionServiceProvider),
      motion: ForegroundMotionAdapter(),
      ownerId: widget.ownerId,
      tripId: widget.trip.id,
    )..addListener(_changed);
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(_routeChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _routeChanged() {
    if (_router
            .routerDelegate
            .currentConfiguration
            .lastOrNull
            ?.matchedLocation !=
        TripPaths.active) {
      unawaited(_collection.stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_collection.stop());
  }

  @override
  void didUpdateWidget(covariant CollectionControls old) {
    super.didUpdateWidget(old);
    if (widget.trip.paused) unawaited(_collection.stop());
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _collection.removeListener(_changed);
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Optional road sensor sharing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(_collection.message),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _collection.busy || widget.trip.paused
              ? null
              : () async {
                  if (_collection.running) {
                    await _collection.stop();
                    return;
                  }
                  final agreed = await confirmAction(
                    context,
                    title: 'Share road sensor data?',
                    message:
                        'While this trip screen is open, share GPS coordinates, speed, accuracy, timestamps, acceleration including gravity (m/s²) and angular velocity (rad/s) with RoadGuard, linked to your account. Raw observations help develop road analysis; they are not verified hazards. Up to 500 batches of 20 observations may be buffered on this device. Collection stops when you leave this screen, pause, sign out or background the app. Consent lasts at most 24 hours. Use Withdraw all sensor consent to revoke this account’s sessions on every device and remove its pending batches on this device; already received data is not erased. Notice version $collectionNoticeVersion.',
                    confirm: 'Agree and start',
                  );
                  if (agreed &&
                      mounted &&
                      ref.read(tripProvider)?.id == widget.trip.id &&
                      ref.read(tripProvider)?.paused == false &&
                      ref.read(authProvider).asData?.value?.id ==
                          widget.ownerId &&
                      WidgetsBinding.instance.lifecycleState ==
                          AppLifecycleState.resumed) {
                    await _collection.start();
                  }
                },
          child: Text(
            _collection.running
                ? 'Stop collection'
                : _collection.busy
                ? 'Starting…'
                : 'Review consent and start',
          ),
        ),
        TextButton(
          onPressed: _collection.busy ? null : () => _collection.flush(),
          child: const Text('Retry pending uploads'),
        ),
        TextButton(
          onPressed: _collection.busy
              ? null
              : () async {
                  final agreed = await confirmAction(
                    context,
                    title: 'Withdraw all sensor consent?',
                    message: 'Revoke all sensor-sharing sessions for this account, including sessions from other devices. Remove its pending batches on this device. Already received data is not erased.',
                    confirm: 'Withdraw all',
                  );
                  if (agreed && context.mounted) {
                    await runAction(context, () => _collection.withdraw());
                  }
                },
          child: const Text('Withdraw all sensor consent'),
        ),
      ],
    ),
  );
}

/// Destination preview keeps the live map visible until the traveller requests a route.
class DestinationPreview extends ConsumerStatefulWidget {
  const DestinationPreview({super.key, required this.place});
  final PlaceResult place;
  @override
  ConsumerState<DestinationPreview> createState() => _DestinationPreviewState();
}

class _DestinationPreviewState extends ConsumerState<DestinationPreview> {
  bool _starting = false;

  void _openDirections() {
    final router = ref.read(routerProvider);
    Navigator.of(context).pop();
    router.push(PlannerPaths.plan, extra: widget.place);
  }

  Future<void> _startDirect() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final location = ref.read(locationServiceProvider);
      await location.requestAccess();
      if (!mounted) return;
      final fix = await location.watch().first.timeout(
        const Duration(seconds: 12),
      );
      if (fix.isMocked ||
          !fix.latitude.isFinite ||
          !fix.longitude.isFinite ||
          !fix.accuracyMeters.isFinite ||
          fix.accuracyMeters > 100 ||
          DateTime.now().difference(fix.observedAt).abs() >
              const Duration(seconds: 10)) {
        throw StateError('Waiting for an accurate, current GPS location.');
      }
      if (!mounted) return;
      final routes = await ref
          .read(roadApiProvider)
          .routes(
            [fix.longitude, fix.latitude],
            widget.place.coordinates,
            originLabel: 'My location',
            destinationLabel: widget.place.label,
          );
      if (routes.isEmpty) {
        throw StateError('No driving route found. Try Directions.');
      }
      // The first route is the routing service's suggested option.
      await ref.read(tripProvider.notifier).start(routes.first);
      if (mounted) {
        final router = ref.read(routerProvider);
        Navigator.of(context).pop();
        router.go(TripPaths.active);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Could not start the trip. Try Directions.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  final MapController _map = MapController();
  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: LiveRoadMap(
              height: double.infinity,
              fullBleed: true,
              controller: _map,
              onMapReady: () => _map.move(
                LatLng(widget.place.latitude, widget.place.longitude),
                12,
              ),
              overlays: [
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        widget.place.latitude,
                        widget.place.longitude,
                      ),
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_pin,
                        size: 44,
                        color: RoadColors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 5,
              borderRadius: BorderRadius.circular(28),
              child: ListTile(
                title: Text(
                  widget.place.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 340,
            child: FloatingActionButton.small(
              heroTag: 'destination-center',
              onPressed: () => _map.move(
                LatLng(widget.place.latitude, widget.place.longitude),
                12,
              ),
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 318,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    widget.place.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tanzania · selected destination',
                    style: TextStyle(color: Color(0xFF657B87), fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _starting ? null : _openDirections,
                          icon: const Icon(Icons.directions),
                          label: const Text('Directions'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _starting ? null : _startDirect,
                          style: FilledButton.styleFrom(
                            backgroundColor: RoadColors.secondaryBg,
                            foregroundColor: const Color(0xFF173441),
                          ),
                          icon: const Icon(Icons.navigation, size: 16),
                          label: Text(_starting ? 'Starting…' : 'Start'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Directions lets you choose a route. Start uses your current location and the suggested live route.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
