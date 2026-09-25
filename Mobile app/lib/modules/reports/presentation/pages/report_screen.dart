import 'package:roadguard_ai/core/routes/route_paths.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/models/safety_policy.dart';
import 'package:roadguard_ai/core/services/permission_service.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with WidgetsBindingObserver {
  final _notes = TextEditingController();
  // RoadGuard accepts pothole reports only (road cracks are out of scope).
  final HazardKind _kind = HazardKind.pothole;
  Uint8List? _photo;
  bool _gpsRequested = false,
      _busy = false,
      _foreground = true;
  String? _locationError;
  String? _busyMessage;
  DateTime? _requireFixAfter;
  ProviderSubscription<AsyncValue<GpsFix>>? _gpsSubscription;
  AsyncValue<GpsFix>? _gps;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recoverPhoto());
  }

  Future<void> _recoverPhoto() async {
    try {
      final image = await ref.read(photoServiceProvider).recover();
      if (mounted && image != null) {
        setState(() {
          _photo = image;
          _requireFixAfter = DateTime.now();
        });
        _stopGps();
        _startGps();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recovered a camera photo. Recheck GPS before saving.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo recovery: ${readableError(error)}')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _foreground = state == AppLifecycleState.resumed;
        if (_foreground) _requireFixAfter = DateTime.now();
      });
      // Paused apps do not rebuild, so release GPS immediately in the callback.
      _stopGps();
      if (_foreground) _startGps();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsSubscription?.close();
    _notes.dispose();
    super.dispose();
  }

  void _startGps() {
    if (_gpsSubscription != null ||
        !_gpsRequested ||
        !_foreground ||
        _busy) {
      return;
    }
    _gpsSubscription = ref.listenManual(locationStreamProvider, (_, next) {
      if (mounted) setState(() => _gps = next);
    }, fireImmediately: true);
  }

  void _stopGps() {
    final subscription = _gpsSubscription;
    _gpsSubscription = null;
    _gps = null;
    if (subscription != null) {
      subscription.close();
      // Invalidation cancels the native stream now, without waiting for a frame.
      ref.invalidate(locationStreamProvider);
    }
  }

  GpsFix? _reportingFix(GpsFix? deviceFix) {
    if (!_foreground) return null;
    if (deviceFix != null &&
        _requireFixAfter != null &&
        deviceFix.observedAt.isBefore(_requireFixAfter!)) {
      return null;
    }
    return deviceFix;
  }

  GpsFix? _latestFix() => _reportingFix(
    _gpsRequested && _foreground
        ? ref.read(locationStreamProvider).asData?.value
        : null,
  );
  Future<void> _requestGps() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyMessage = 'Checking location…';
      _locationError = null;
      _gpsRequested = false;
    });
    _stopGps();
    try {
      await ref.read(locationServiceProvider).requestAccess();
      if (mounted) {
        setState(() {
          _gpsRequested = true;
          _requireFixAfter = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _locationError = readableError(error));
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _busyMessage = null;
      });
      _startGps();
    }
  }

  Future<void> _capture() async {
    // Never start the camera (or accept its GPS evidence) while the app is in
    // the background, e.g. from a tap that was queued just before pausing.
    if (_busy || !_foreground) return;
    setState(() {
      _busy = true;
      _busyMessage = 'Requesting location permission…';
      _locationError = null;
    });
    var cameraAttempted = false;
    try {
      final location = ref.read(locationServiceProvider);
      if (!_gpsRequested) {
        await location.requestAccess();
        if (!mounted) return;
        setState(() {
          _gpsRequested = true;
          _requireFixAfter = DateTime.now();
          _locationError = null;
        });
        // Begin collecting a current position while the system camera is open.
        _startGps();
      }

      cameraAttempted = true;
      if (mounted) setState(() => _busyMessage = 'Opening camera…');
      final image = await ref.read(photoServiceProvider).capture();
      if (mounted && image != null) setState(() => _photo = image);
    } catch (error) {
      if (mounted) {
        final message = readableError(error);
        if (!cameraAttempted) {
          _locationError = message;
        }
        var blocked = false;
        if (cameraAttempted) {
          try {
            final camera = await ref
                .read(permissionServiceProvider)
                .snapshot();
            blocked = camera.camera == PermissionState.permanentlyDenied;
          } catch (_) {
            // Preserve the original camera failure if the status query also fails.
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: blocked
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () => runAction(
                      context,
                      () =>
                          ref.read(permissionServiceProvider).openAppSettings(),
                    ),
                  )
                : null,
          ),
        );
      }
    }
    if (mounted) {
      // Some camera implementations return without a lifecycle notification.
      // Even cancellation or failure requires new stationary evidence.
      setState(() {
        _busy = false;
        _busyMessage = null;
        if (cameraAttempted) _requireFixAfter = DateTime.now();
      });
      _startGps();
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    if (!ref.read(roadApiProvider).configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Image upload is unavailable. Connect the RoadGuard service and use a real camera photo.',
          ),
        ),
      );
      return;
    }
    final writer = ref.read(reportWriterProvider);
    final uploader = ref.read(reportUploaderProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    // The domain writer re-evaluates the raw fix at save time, not just at form entry.
    setState(() {
      _busy = true;
      _busyMessage = 'Uploading…';
    });
    await runAction(context, () async {
      final agreed = await confirmAction(
        context,
        title: 'Upload this hazard report?',
        message:
            'Send the captured photo, description and recorded GPS location to RoadGuard for review. Account identity and photo metadata are excluded. Avoid people or number plates in the image. If upload fails, the report stays on this device for retry.',
        confirm: 'Upload image',
      );
      if (!agreed || !mounted) return;
      final report = await writer.save(
        kind: _kind,
        notes: _notes.text,
        fix: _latestFix(),
        photo: _photo,
      );
      var message =
          'Report received by RoadGuard. Awaiting administrator review.';
      try {
        await uploader.upload(report.id);
      } catch (error) {
        message =
            'Upload failed: ${readableError(error)}. The report is saved on this device for retry.';
      } finally {
        container.invalidate(reportsProvider);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        context.go(ReportPaths.reportDetail(report.id));
      }
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _busyMessage = null;
      });
      _startGps();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      clockProvider,
    ); // Re-evaluate stale fixes even when no new GPS events arrive.
    final now = DateTime.now();
    final gps = _gps;
    final currentFix = _reportingFix(gps?.asData?.value);
    final locationError =
        _locationError ??
        (gps?.hasError == true ? readableError(gps!.error!) : null);
    final gate = ref
        .watch(safetyPolicyProvider)
        .evaluate(currentFix, now);
    final allowed = gate.allowed && !_busy;
    final scheme = Theme.of(context).colorScheme;
    return DetailScaffold(
      title: 'Report a hazard',
      bottom: FilledButton.icon(
        key: const Key('upload-report'),
        onPressed: allowed && _photo != null ? _upload : null,
        icon: Icon(
          _busy ? Icons.hourglass_top_rounded : Icons.cloud_upload_outlined,
        ),
        label: Text(_busy ? (_busyMessage ?? 'Please wait…') : 'Upload image'),
      ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const SizedBox(height: 8),
          Text('Location', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentFix != null
                            ? 'Device GPS reading'
                            : 'Location not confirmed',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (currentFix case final GpsFix fix) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Current location captured · GPS accuracy ${fix.accuracyMeters.toStringAsFixed(0)} m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: gate.allowed
                  ? scheme.secondaryContainer
                  : scheme.errorContainer.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  gate.allowed
                      ? Icons.verified_user_outlined
                      : Icons.lock_outline_rounded,
                  color: gate.allowed
                      ? scheme.primary
                      : scheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gate.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        gate.detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_gpsRequested || !gate.allowed || locationError != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : _requestGps,
              icon: const Icon(Icons.gps_fixed_rounded),
              label: const Text('Check device location'),
            ),
          if (locationError != null) ...[
            Text(locationError, style: TextStyle(color: scheme.error)),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => runAction(
                      context,
                      () => ref.read(locationServiceProvider).openSettings(),
                    ),
              child: const Text('Open app settings'),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Add photo', style: Theme.of(context).textTheme.titleMedium),
              Text('Required', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          if (_photo == null)
            SurfaceCard(
              onTap: _busy ? null : _capture,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 125),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_camera_outlined,
                        size: 38,
                        color: allowed ? scheme.primary : scheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Take a photo',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Location permission is required before the camera opens. A current, safe GPS fix is required to upload.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _photo!,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                semanticLabel: 'Your hazard confirmation photo',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: allowed ? _capture : null,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retake photo'),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _photo = null),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            key: const Key('report-notes'),
            controller: _notes,
            enabled: allowed,
            maxLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'Add useful context about the road surface…',
            ),
          ),
        ],
      ),
    );
  }
}
