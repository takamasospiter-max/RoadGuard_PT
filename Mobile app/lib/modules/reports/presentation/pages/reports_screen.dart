import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/shared/widgets/common.dart';
import 'package:roadguard_ai/modules/trips/presentation/pages/trips_screen.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(reportsProvider);
      await ref.read(reportsProvider.future);
    },
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading(
          'Your contributions.',
          'A place for the things you notice along the way.',
        ),
        const SizedBox(height: 22),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.watch(roadApiProvider).configured
                          ? 'Choose what to share.'
                          : 'Saved here. Not submitted.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kIsWeb
                          ? 'Browser preview: reports stay in memory and reset on reload.'
                          : ref.watch(roadApiProvider).configured
                          ? 'Open a report to upload it anonymously. Submission does not mean verification.'
                          : 'Reports and photos stay on this device. Server submission is not available yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AsyncPanel(
          value: ref.watch(reportsProvider),
          onRetry: () => ref.invalidate(reportsProvider),
          builder: (reports) {
            if (reports.isEmpty) {
              return EmptyView(
                icon: Icons.add_location_alt_outlined,
                title: 'Notice something on the road?',
                message: 'When you’re safely stopped, capture a pothole. Your first report will appear here.',
                action: 'Report a hazard',
                onAction: () => context.push(ReportPaths.create),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  '${reports.length} local ${reports.length == 1 ? 'report' : 'reports'}',
                  action: 'Add new',
                  onTap: () => context.push(ReportPaths.create),
                ),
                const SizedBox(height: 12),
                for (final report in reports)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SurfaceCard(
                      onTap: () =>
                          context.push(ReportPaths.reportDetail(report.id)),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              report.photo,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  report.kind.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  formatDate(report.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                StatusPill(deliveryLabel(report)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.id});
  final String id;
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await confirmAction(
      context,
      title: 'Delete this local report?',
      message: 'Its photo and location will be removed from this device. This action does not contact a server.',
      confirm: 'Delete report',
    )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () async {
      await ref.read(reportWriterProvider).delete(id);
      if (context.mounted) context.go(ReportPaths.reports);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailScaffold(
    title: 'Your report',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AsyncPanel(
          value: ref.watch(reportsProvider),
          onRetry: () => ref.invalidate(reportsProvider),
          builder: (reports) {
            final report = reports.where((item) => item.id == id).firstOrNull;
            if (report == null) {
              return const EmptyView(
                icon: Icons.search_off_rounded,
                title: 'Report not found',
                message: 'It may have been deleted from this device.',
              );
            }
            return _ReportBody(
              report: report,
              onDelete: () => _delete(context, ref),
              onUpload:
                  ref.watch(roadApiProvider).configured &&
                      report.delivery != DeliveryState.submitted
                  ? () async {
                      if (!await confirmAction(
                        context,
                        title: 'Upload anonymously?',
                        message: 'Send this photo, description and recorded GPS location to RoadGuard. Account identity and photo metadata are excluded, but people or plates visible in the image remain.',
                        confirm: 'Upload report',
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      final uploader = ref.read(reportUploaderProvider);
                      final container = ProviderScope.containerOf(
                        context,
                        listen: false,
                      );
                      await runAction(context, () async {
                        try {
                          await uploader.upload(id);
                        } finally {
                          container.invalidate(reportsProvider);
                        }
                      });
                    }
                  : null,
            );
          },
        ),
      ],
    ),
  );
}

class _ReportBody extends StatefulWidget {
  const _ReportBody({
    required this.report,
    required this.onDelete,
    this.onUpload,
  });
  final LocalReport report;
  final VoidCallback onDelete;
  final Future<void> Function()? onUpload;
  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  bool _busy = false;
  LocalReport get report => widget.report;
  Future<void> Function()? get onUpload => widget.onUpload;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.memory(
          report.photo,
          height: 230,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(height: 22),
      StatusPill(deliveryLabel(report)),
      const SizedBox(height: 16),
      PageHeading(report.kind.label, formatDate(report.createdAt)),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report location',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Location saved with this report'),
            const SizedBox(height: 6),
            Text(
              'GPS accuracy: ${report.fix.accuracyMeters.toStringAsFixed(0)} m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('Description', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(report.notes.isEmpty ? 'No description added.' : report.notes),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delivery status',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 10),
            Text(
              report.delivery == DeliveryState.submitted
                  ? 'Server received · ${report.serverStatus?.label}'
                  : onUpload != null
                  ? 'Saved locally → Ready for anonymous upload'
                  : 'Saved locally → Server submission not connected',
            ),
            SizedBox(height: 8),
            Text(
              report.serverId != null
                  ? 'Server ID: ${report.serverId}\nStatus received ${report.receivedAt?.toLocal()}. Submission is not verification; this receipt is not a live status subscription.'
                  : 'This report has no server lifecycle status. “New”, “Under Verification” and “Confirmed” may only be shown after a real server response.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      if (onUpload != null) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('upload-report'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await onUpload?.call();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(
            _busy
                ? 'Uploading…'
                : report.delivery == DeliveryState.queued
                ? 'Retry anonymous upload'
                : 'Upload anonymously',
          ),
        ),
      ],
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : widget.onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete local report'),
        ),
      ),
    ],
  );
}

String deliveryLabel(LocalReport report) => switch (report.delivery) {
  DeliveryState.localOnly => 'LOCAL ONLY',
  DeliveryState.queued => 'AWAITING UPLOAD',
  DeliveryState.submitted =>
    'SERVER RECEIVED · ${report.serverStatus?.label ?? 'Pending'}',
};
