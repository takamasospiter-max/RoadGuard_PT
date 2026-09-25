import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/modules/home/presentation/providers/route_alerts_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _showInfo(
    BuildContext context, {
    required String title,
    required String message,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    if (ref.read(tripProvider) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish your active trip preview before clearing local data.',
          ),
        ),
      );
      return;
    }
    if (!await confirmAction(
      context,
      title: 'Clear data on this device?',
      message: 'Delete local reports, their photos, trips, received route alerts and telemetry records. Your preferences and map image cache stay. This is not a server account-erasure request.',
      confirm: 'Clear local data',
    )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () async {
      await ref.read(localStoreProvider).clearUserData();
      ref.invalidate(reportsProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(routeAlertTripsProvider);
      ref.invalidate(
        routeAlertsProvider(
          ref.read(authProvider).asData?.value?.id ?? 'guest',
        ),
      );
      ref.invalidate(telemetryCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local reports, trips and route alerts cleared.'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final account = ref.watch(authProvider);
    final traveler = account.asData?.value;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Row(
            children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: scheme.primary,
                  size: 38,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.isLoading
                          ? 'Loading profile…'
                          : traveler?.name ?? 'Guest',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.isLoading
                          ? 'Checking account'
                          : traveler?.email ?? 'Explore at your pace',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      traveler == null ? 'GUEST' : 'TRAVELER',
                      color: scheme.primary,
                      background: scheme.primaryContainer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (traveler != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('profile-sign-out'),
            onPressed: () => runAction(
              context,
              () => ref.read(authProvider.notifier).signOut(),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
        ],
        const SizedBox(height: 20),
        _ProfileAction(
          icon: Icons.route_outlined,
          title: 'My Routes',
          onTap: () => context.go(TripPaths.history),
        ),
        _ProfileAction(
          icon: Icons.report_outlined,
          title: 'Reported Incidents',
          onTap: () => context.go(ReportPaths.reports),
        ),
        _ProfileAction(
          icon: Icons.notifications_none_rounded,
          title: 'Route alert history',
          onTap: () => context.go(HomePaths.alerts),
        ),
        _ProfileAction(
          icon: Icons.help_outline_rounded,
          title: 'Help & Support',
          onTap: () => _showInfo(
            context,
            title: 'Help & Support',
            message: 'Explore shows the online OpenStreetMap map. Choose My location to show your position with permission; map browsing works without GPS. Live place search, routes and confirmed hazard data require the RoadGuard service. My Routes keeps trip history, and Route alert history lists confirmed warnings shown during an active trip. Reports are saved locally first and can be uploaded anonymously when the service is connected.\n\nStop safely before reporting. A fresh stationary GPS reading and a camera photo are required. A server receipt means the report was received for review, not that it was confirmed.\n\nFor technical support, connect the RoadGuard service or contact your RoadGuard administrator.',
          ),
        ),
        _ProfileAction(
          icon: Icons.info_outline_rounded,
          title: 'About RoadGuard AI',
          onTap: () => _showInfo(
            context,
            title: 'About RoadGuard AI',
            message: 'Safer Roads. Smarter Journeys.\n\nRoadGuard AI is a road-condition monitoring and traveler-safety app. Browse an online OpenStreetMap map, search destinations, plan trips, receive confirmed route warnings and submit hazard reports for review. Trips, received alerts and reports are stored on this device.\n\nA configured RoadGuard service provides traveler accounts, routes, confirmed hazards, anonymous report uploads and optional foreground sensor sharing. The app does not provide turn-by-turn voice navigation or remote push notifications.\n\nTraveler app · Version 0.1.0',
          ),
        ),
        const SizedBox(height: 10),
        if (account.isLoading) const LinearProgressIndicator(),
        if (account.hasError) ...[
          Text(
            'Could not restore your session. Check your connection.',
            style: TextStyle(color: scheme.error),
          ),
          TextButton(
            onPressed: () => ref.invalidate(authProvider),
            child: const Text('Retry connection'),
          ),
        ],
        const SizedBox(height: 28),
        const SectionTitle('Your experience'),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Voice warnings'),
                subtitle: const Text('Read confirmed route warnings aloud during a live trip.'),
                value: settings.voiceEnabled,
                onChanged: (value) => runAction(context, () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .update(
                        (settings) => settings.copyWith(voiceEnabled: value),
                      );
                  if (!value) await ref.read(voiceServiceProvider).stop();
                }),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: Text(
                  '${settings.appearance[0].toUpperCase()}${settings.appearance.substring(1)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final choice = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (context) => SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final mode in ['system', 'light', 'dark'])
                              ListTile(
                                title: Text(
                                  '${mode[0].toUpperCase()}${mode.substring(1)}',
                                ),
                                trailing: settings.appearance == mode
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                onTap: () => Navigator.pop(context, mode),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                  if (choice != null && context.mounted) {
                    await runAction(
                      context,
                      () => ref
                          .read(settingsProvider.notifier)
                          .update(
                            (settings) => settings.copyWith(appearance: choice),
                          ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const SectionTitle('Privacy & permissions'),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Device permissions'),
                subtitle: const Text('Location and camera are your choice.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(BoardingPaths.permissions),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.sensors_off_outlined),
                title: Text('Road-sensor contribution'),
                subtitle: Text(
                  'Off on this screen. Start a live trip and review optional sensor-sharing consent to contribute. Signing in alone does not enable sensing.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Road-sensor contribution'),
                    content: const Text(
                      'Sensor sharing is optional. It becomes available during an active trip after signing in and giving explicit consent. Pausing or leaving the trip stops collection.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Privacy & data'),
                subtitle: const Text('Understand what stays on this device.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(ProfilePaths.privacy),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Storage & integration'),
                subtitle: const Text('Local records and connection status.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(ProfilePaths.storage),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _clear(context, ref),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Clear local data'),
        ),
        const SizedBox(height: 26),
        if (!ref.watch(roadApiProvider).configured)
          const SurfaceCard(
            child: Text(
              'Road services are not connected. Live search, routes, confirmed hazards and report upload need the RoadGuard service.',
            ),
          ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            'ROADGUARD AI  ·  0.1.0\nTraveler app · ${ref.watch(roadApiProvider).configured ? 'Road services configured' : 'Road services not connected'}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SurfaceCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    ),
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: 'Privacy & data',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading(
          'Clear choices.\nNo hidden collection.',
          'What this build does, and what is not connected yet.',
        ),
        const SizedBox(height: 26),
        for (final entry in const [
          (
            'Account',
            'An account is required to use the app. Registration sends your name, email and password to the configured RoadGuard server. Passwords are hashed on the server. Your session token is kept in secure device storage; your password is never saved on this device. Email verification and password recovery are not available yet.',
          ),
          (
            'Location',
            'Location is read only when you use a location feature: live map position, current-location search, route planning, an active trip, or manual hazard reporting. Map GPS stops when its screen closes or the app backgrounds. Trip sensor sharing links timestamped GPS coordinates, speed and accuracy to raw motion samples only after separate consent. A saved report stores the hazard coordinates, accuracy, timestamp and stationary-speed evidence.',
          ),
          (
            'Online map & provider',
            'OpenStreetMap supplies map images over HTTPS. Requests reveal your IP address and viewed map area to that provider; centering on your position reveals that area. Your reports, photos and account form details are not sent with map requests. When you request a driving route, the selected endpoints are sent through RoadGuard to the configured OSRM service. The public demo has no uptime guarantee. Displayed confirmed hazards come from RoadGuard moderation, not the tile provider.',
          ),
          (
            'Map image cache',
            'Viewed map images can remain in the device cache and reveal areas you viewed. They are separate from reports and the telemetry outbox. Clear local data does not clear this cache. Android users can remove it with Clear cache in the system app settings. Cached maps are not guaranteed to be available offline.',
          ),
          (
            'Camera photos',
            'The camera opens only after you choose Take a photo in a manual hazard report. The selected image is re-encoded before it is saved locally, which removes embedded file metadata. If you submit a connected report, the photo is sent to RoadGuard for review; otherwise it stays on this device. Faces, number plates and text in the image are not automatically blurred.',
          ),
          (
            'Local storage',
            'Android and iOS store report, photo, trip, route-alert and telemetry contents in SQLite using AES-GCM encryption. The per-install encryption key is kept in Android Keystore or iOS Keychain. Authentication credentials use secure storage. Real reports are uploaded only when you submit them; sensor batches upload only after trip consent. The browser preview uses temporary memory. Keep your device protected because account identifiers and record timing metadata are still used locally.',
          ),
          (
            'Motion data & road sensing',
            'Accelerometer and gyroscope samples are collected only during an active trip after sign-in and your separate consent. Each observation has a timestamp and is associated with GPS and trip context. Samples are buffered in a bounded on-device queue (up to 500 batches) and uploaded to RoadGuard while the collection session is active and the service is reachable. Pausing, leaving the trip screen, backgrounding the app, or a sensor/location error stops collection. Raw samples are not confirmed hazards: RoadGuard must process them before any road event can be confirmed. Background collection and automatic hazard classification are not enabled. Withdrawing consent stops future collection and removes this device’s pending batches; already received data is not erased.',
          ),
          (
            'Deleting data',
            'Clear local data removes local reports, photos, trips, received route alerts and outbox rows. Preferences and cached map images remain. It does not send a server-erasure request or claim to erase OS backups. The SRS’s validated account-erasure workflow still requires backend integration.',
          ),
          (
            'Notifications',
            'The Alerts tab lists confirmed route warnings that were shown during a trip and saved on this device. These are in-app records, not remote push notifications. Remote notifications, automatic hazard scoring and automatic voice delivery are not enabled.',
          ),
        ]) ...[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.$1, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(entry.$2),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    ),
  );
}

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailScaffold(
    title: 'Storage & integration',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading(
          'Everything, accounted for.',
          'Actual local counts. No simulated synchronization.',
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.watch(roadApiProvider).configured
                          ? 'Road services configured'
                          : 'Report sync not connected',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      ref.watch(roadApiProvider).configured
                          ? 'When available, road services provide OSRM routes, confirmed hazards and anonymous report uploads. Route warnings shown during trips are saved locally. Sensor sharing requires sign-in, an active live trip and explicit consent.'
                          : 'Configure ROADGUARD_API_URL to connect road services. Live routes and confirmed hazards will then be available; reports stay local until successfully uploaded.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AsyncPanel(
          value: ref.watch(reportsProvider),
          onRetry: () => ref.invalidate(reportsProvider),
          builder: (reports) => _CountRow(
            label: 'Local reports',
            value: '${reports.length}',
            icon: Icons.description_outlined,
          ),
        ),
        const SizedBox(height: 12),
        AsyncPanel(
          value: ref.watch(historyProvider),
          onRetry: () => ref.invalidate(historyProvider),
          builder: (trips) => _CountRow(
            label: 'Completed trips',
            value: '${trips.length}',
            icon: Icons.route_outlined,
          ),
        ),
        const SizedBox(height: 12),
        AsyncPanel(
          value: ref.watch(
            routeAlertsProvider(
              ref.watch(authProvider).asData?.value?.id ?? 'guest',
            ),
          ),
          onRetry: () => ref.invalidate(
            routeAlertsProvider(
              ref.read(authProvider).asData?.value?.id ?? 'guest',
            ),
          ),
          builder: (alerts) => _CountRow(
            label: 'Received route alerts',
            value: '${alerts.length}',
            icon: Icons.notifications_active_outlined,
          ),
        ),
        const SizedBox(height: 12),
        AsyncPanel(
          value: ref.watch(telemetryCountProvider),
          onRetry: () => ref.invalidate(telemetryCountProvider),
          builder: (count) => _CountRow(
            label: 'Telemetry buffer',
            value: '$count / 500',
            icon: Icons.storage_outlined,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'No sensor collection is running. The outbox rejects new records at capacity rather than silently deleting unsent data.',
        ),
      ],
    ),
  );
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
          ],
        ),
        const SizedBox(height: 12),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}
