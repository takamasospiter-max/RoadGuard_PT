import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';

/// Each map creates a provider; its TileLayer disposes it when the map closes.
/// Tests replace this factory with an in-memory tile source explicitly.
final mapTileProviderFactoryProvider = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(
        headers: {'User-Agent': 'RoadGuardAI/0.1 (com.example.roadguard_ai)'},
        attemptDecodeOfHttpErrorResponses: false,
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 100_000_000,
        ),
      ),
);

/// Geographic map tiles (OpenStreetMap), independent of the route and hazard layers drawn on top.
///
/// [location] must come from the caller's current, permission-gated GPS state.
/// The caller owns expiry, lifecycle, and permission handling. This map never
/// requests location or treats the default camera centre as the user's position.
class LiveRoadMap extends ConsumerStatefulWidget {
  const LiveRoadMap({
    super.key,
    this.height = 290,
    this.fullBleed = false,
    this.controller,
    this.location,
    this.onMapReady,
    this.interactive = true,
    this.showAttribution = true,
    this.overlays = const [],
    this.onTap,
    this.onPositionChanged,
  });

  static const initialCenter = LatLng(-6.7924, 39.2083);

  /// Closest zoom: one step past OSM's last tile level (19), enough for ±30 m.
  static const double maxZoom = 20;
  final double height;
  final bool fullBleed;
  final MapController? controller;
  final GpsFix? location;
  final VoidCallback? onMapReady;
  final bool interactive;
  final bool showAttribution;
  final List<Widget> overlays;
  final void Function(TapPosition, LatLng)? onTap;
  final void Function(MapCamera, bool)? onPositionChanged;

  @override
  ConsumerState<LiveRoadMap> createState() => _LiveRoadMapState();
}

enum _TileLoad { waiting, decoded, failed }

class _LiveRoadMapState extends ConsumerState<LiveRoadMap> {
  late final TileProvider _tileProvider;
  final _resetTiles = StreamController<void>.broadcast();
  // TileImage equality compares coordinates; a retry creates new images at the
  // same coordinates, so ownership must be tracked by object identity.
  final _tiles = Map<TileImage, _TileLoad>.identity();
  Timer? _loadingDeadline;
  var _generation = 0;
  var _refreshScheduled = false;
  var _slow = false;

  @override
  void initState() {
    super.initState();
    _tileProvider = ref.read(mapTileProviderFactoryProvider)();
    _startDeadline();
  }

  void _startDeadline() {
    _loadingDeadline?.cancel();
    _loadingDeadline = Timer(const Duration(seconds: 15), () {
      if (!mounted ||
          (_tiles.isNotEmpty && !_tiles.values.contains(_TileLoad.waiting))) {
        return;
      }
      setState(() => _slow = true);
    });
  }

  void _tileChanged(TileImage tile, _TileLoad? status, int generation) {
    if (!mounted || generation != _generation) return;
    if (status == null) {
      _tiles.remove(tile);
    } else {
      _tiles[tile] = status;
    }
    if (status == _TileLoad.waiting &&
        _loadingDeadline?.isActive != true &&
        !_slow) {
      _startDeadline();
    }
    // Image decoding and tile creation may notify while Flutter is building.
    // Batch status changes after layout instead of calling setState mid-build.
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      if (!_tiles.values.contains(_TileLoad.waiting)) {
        _loadingDeadline?.cancel();
        _slow = false;
      }
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _retry() {
    setState(() {
      _generation++;
      _tiles.clear();
      _slow = false;
    });
    _startDeadline();
    // Reload visible tile images, retaining HTTP-compliant disk caching.
    _resetTiles.add(null);
  }

  @override
  void dispose() {
    _loadingDeadline?.cancel();
    unawaited(_resetTiles.close());
    // TileLayer owns _tileProvider.dispose(), including its HTTP client.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _tiles.values.contains(_TileLoad.failed);
    final loading = _tiles.isEmpty || _tiles.values.contains(_TileLoad.waiting);
    final fix = widget.location;
    final showLocation =
        fix != null &&
        !fix.isMocked &&
        fix.latitude.isFinite &&
        fix.longitude.isFinite &&
        fix.latitude.abs() <= 90 &&
        fix.longitude.abs() <= 180;
    final generation = _generation;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.fullBleed ? 0 : 16),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    key: const Key('live-map'),
                    mapController: widget.controller,
                    options: MapOptions(
                      initialCenter: LiveRoadMap.initialCenter,
                      initialZoom: 13,
                      minZoom: 2,
                      maxZoom: LiveRoadMap.maxZoom,
                      backgroundColor: RoadColors.canvas,
                      interactionOptions: InteractionOptions(
                        flags: widget.interactive
                            ? InteractiveFlag.all & ~InteractiveFlag.rotate
                            : InteractiveFlag.none,
                      ),
                      onMapReady: widget.onMapReady,
                      onTap: widget.onTap,
                      onPositionChanged: widget.onPositionChanged,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.roadguard_ai',
                        tileProvider: _tileProvider,
                        panBuffer: 0,
                        // OSM has images down to zoom 19; zoom 20 enlarges
                        // them, so a hazard can be shown at about ±30 m.
                        maxNativeZoom: 19,
                        maxZoom: LiveRoadMap.maxZoom,
                        tileDisplay: const TileDisplay.instantaneous(),
                        reset: _resetTiles.stream,
                        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                        tileBuilder: (context, child, tile) => _ObservedTile(
                          key: ObjectKey(tile),
                          tile: tile,
                          generation: generation,
                          onChanged: _tileChanged,
                          child: child,
                        ),
                      ),
                      ...widget.overlays,
                      if (showLocation)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(fix.latitude, fix.longitude),
                              width: 40,
                              height: 40,
                              child: Semantics(
                                label: 'Your current location',
                                child: Container(
                                  key: const Key('live-location-marker'),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: RoadColors.blue.withValues(
                                      alpha: .2,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: RoadColors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (hasError || _slow)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: SingleChildScrollView(
                            child: Material(
                              key: const Key('live-map-error'),
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              elevation: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      hasError
                                          ? 'Some map tiles could not load. '
                                                'Check your connection and retry.'
                                          : 'Map tiles are taking longer to '
                                                'load. Check your connection.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    TextButton.icon(
                                      key: const Key('live-map-retry'),
                                      onPressed: _retry,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry map'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (loading)
                    // A status label only: IgnorePointer lets drags and taps
                    // that start on it still reach the map underneath.
                    const IgnorePointer(
                      child: Center(
                        child: Card(
                          key: Key('live-map-loading'),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text('Loading map tiles…'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showAttribution) const MapAttribution(),
          ],
        ),
      ),
    );
  }
}

/// Attribution stays outside the map canvas so in-map layers cannot cover it.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key, this.compact = false});

  final bool compact;

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // A missing browser or unavailable platform handler is recoverable.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Unable to open OpenStreetMap attribution.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      width: compact ? 132 : double.infinity,
      child: TextButton(
        key: const Key('map-attribution'),
        style: TextButton.styleFrom(
          minimumSize: compact ? const Size(0, 0) : const Size(48, 48),
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const RoundedRectangleBorder(),
          textStyle: TextStyle(fontSize: compact ? 9 : 12),
        ),
        onPressed: () => _open(context),
        child: Text(
          compact
              ? 'OpenStreetMap illustration'
              : '© OpenStreetMap contributors',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class _ObservedTile extends StatefulWidget {
  const _ObservedTile({
    super.key,
    required this.tile,
    required this.generation,
    required this.onChanged,
    required this.child,
  });

  final TileImage tile;
  final int generation;
  final void Function(TileImage, _TileLoad?, int) onChanged;
  final Widget child;

  @override
  State<_ObservedTile> createState() => _ObservedTileState();
}

class _ObservedTileState extends State<_ObservedTile> {
  _TileLoad? _lastStatus;

  @override
  void initState() {
    super.initState();
    widget.tile.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant _ObservedTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tile != widget.tile) {
      oldWidget.tile.removeListener(_changed);
      oldWidget.onChanged(oldWidget.tile, null, oldWidget.generation);
      widget.tile.addListener(_changed);
      _lastStatus = null;
    }
    if (oldWidget.generation != widget.generation) _lastStatus = null;
    _changed();
  }

  void _changed() {
    final tile = widget.tile;
    final status = tile.loadError
        ? _TileLoad.failed
        : tile.imageInfo != null
        ? _TileLoad.decoded
        : _TileLoad.waiting;
    if (status == _lastStatus) return;
    _lastStatus = status;
    widget.onChanged(tile, status, widget.generation);
  }

  @override
  void dispose() {
    widget.tile.removeListener(_changed);
    widget.onChanged(widget.tile, null, widget.generation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Moves [controller]'s map to about ±[radiusMeters] around [point]
/// (default 30 m), e.g. when a hazard marker is tapped on a zoomed-out map.
///
/// The box is [radiusMeters] north/south/east/west of the point; one degree
/// of latitude is ~111,320 m, and a degree of longitude shrinks with cos(lat).
void focusMapOn(
  MapController controller,
  LatLng point, {
  double radiusMeters = 30,
}) {
  const metresPerDegree = 111320.0;
  final dLat = radiusMeters / metresPerDegree;
  final dLng = radiusMeters / (metresPerDegree * math.cos(point.latitudeInRad));
  controller.fitCamera(
    CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(point.latitude - dLat, point.longitude - dLng),
        LatLng(point.latitude + dLat, point.longitude + dLng),
      ),
      padding: const EdgeInsets.all(16),
      maxZoom: LiveRoadMap.maxZoom,
    ),
  );
}
