import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/services/permission_service.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});
  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  late Future<PermissionSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshot = ref.read(permissionServiceProvider).snapshot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh() {
    final snapshot = ref.read(permissionServiceProvider).snapshot();
    setState(() => _snapshot = snapshot);
  }

  Future<void> _requestLocation() async {
    setState(() => _busy = true);
    try {
      final state = await ref.read(permissionServiceProvider).requestLocation();
      if (!mounted) return;
      if (state != PermissionState.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_permissionMessage(state, 'Location'))),
        );
      }
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(readableError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings({bool location = false}) async {
    await runAction(context, () async {
      final permissions = ref.read(permissionServiceProvider);
      if (location) {
        await permissions.openLocationSettings();
      } else {
        await permissions.openAppSettings();
      }
    });
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    await runAction(context, () async {
      await ref
          .read(settingsProvider.notifier)
          .update((value) => value.copyWith(onboardingComplete: true));
      if (mounted) context.go(AuthPaths.signIn);
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: 'Make it yours',
    bottom: FilledButton(
      key: const Key('permissions-continue'),
      onPressed: _busy ? null : _continue,
      child: const Text('Continue'),
    ),
    child: FutureBuilder<PermissionSnapshot>(
      future: _snapshot,
      builder: (context, result) {
        final current = result.data;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'You’re in control.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            const Text(
              'Allow location once so Explore, directions and hazard reports can use it when needed. Location access remains available throughout the app and can be changed in device settings.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 20),
            _AccessCard(
              icon: Icons.location_on_outlined,
              title: 'Location',
              description: 'Shows your live map position, plans routes, tracks an active trip, and attaches GPS evidence to a report. GPS runs only while a location feature is in use.',
              status: current == null
                  ? (result.hasError ? 'Status unavailable' : 'Checking…')
                  : current.locationServicesEnabled
                  ? _permissionLabel(current.location)
                  : 'Location services off',
              actionLabel: current != null && !current.locationServicesEnabled
                  ? 'Open location settings'
                  : current?.location == PermissionState.permanentlyDenied
                  ? 'Open app settings'
                  : current?.location == PermissionState.granted
                  ? null
                  : current?.location == PermissionState.restricted
                  ? null
                  : 'Allow location',
              onAction: current != null && !current.locationServicesEnabled
                  ? () => _openSettings(location: true)
                  : current?.location == PermissionState.permanentlyDenied
                  ? _openSettings
                  : current?.location == PermissionState.granted
                  ? null
                  : current?.location == PermissionState.restricted
                  ? null
                  : _busy
                  ? null
                  : _requestLocation,
              busy: _busy,
            ),
            const SizedBox(height: 12),
            _AccessCard(
              icon: Icons.sensors_outlined,
              title: 'Motion sensors',
              description: 'Accelerometer and gyroscope samples are collected only during an active trip after separate consent. Samples are timestamped, linked to GPS and trip context, buffered on this device (up to 500 batches), and uploaded to RoadGuard when available. They are raw observations, not confirmed hazards.',
              status: current == null
                  ? (result.hasError ? 'Status unavailable' : 'Checking…')
                  : _permissionLabel(current.motion),
              actionLabel: current?.motion == PermissionState.permanentlyDenied
                  ? 'Open app settings'
                  : null,
              onAction: current?.motion == PermissionState.permanentlyDenied
                  ? _openSettings
                  : null,
              footnote: 'Sensor access is checked on this device. Starting collection still requires an active trip, sign-in and your explicit agreement.',
            ),
            const SizedBox(height: 12),
            _AccessCard(
              icon: Icons.camera_alt_outlined,
              title: 'Camera',
              description: 'Takes a photo only when you choose to add evidence to a manual hazard report. Entering the report screen does not open the camera.',
              status: current == null
                  ? (result.hasError ? 'Status unavailable' : 'Checking…')
                  : _permissionLabel(current.camera),
              actionLabel: current?.camera == PermissionState.permanentlyDenied
                  ? 'Open app settings'
                  : 'Requested when taking a photo',
              onAction: current?.camera == PermissionState.permanentlyDenied
                  ? _openSettings
                  : null,
            ),
            const SizedBox(height: 12),
            const _AccessCard(
              icon: Icons.map_outlined,
              title: 'Online maps',
              description: 'OpenStreetMap supplies map images over the internet and receives your IP address and the area you view. Live route search and confirmed hazard data require a RoadGuard connection.',
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    ),
  );
}

String _permissionLabel(PermissionState state) => switch (state) {
  PermissionState.unknown => 'Status unavailable',
  PermissionState.requesting => 'Requesting…',
  PermissionState.granted => 'Allowed',
  PermissionState.denied => 'Not allowed',
  PermissionState.permanentlyDenied => 'Blocked in device settings',
  PermissionState.restricted => 'Restricted',
  PermissionState.unavailable => 'Unavailable on this device',
};

String _permissionMessage(PermissionState state, String name) =>
    switch (state) {
      PermissionState.denied => '$name access was not allowed.',
      PermissionState.permanentlyDenied =>
        '$name access is blocked. Open device settings to allow it.',
      PermissionState.restricted =>
        '$name access is restricted on this device.',
      PermissionState.unavailable => '$name is unavailable on this device.',
      _ => '$name access could not be confirmed.',
    };

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.icon,
    required this.title,
    required this.description,
    this.status,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.footnote,
  });

  final IconData icon;
  final String title, description;
  final String? status, actionLabel, footnote;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(status!),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(height: 1.45)),
        if (footnote != null) ...[
          const SizedBox(height: 8),
          Text(footnote!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy ? null : onAction,
            child: Text(
              busy && onAction != null ? 'Please wait…' : actionLabel!,
            ),
          ),
        ],
      ],
    ),
  );
}
