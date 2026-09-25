import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/core/theme/app_theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: light ? RoadColors.blueTint : RoadColors.ink,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.route_rounded,
          color: light ? RoadColors.ink : RoadColors.blueTint,
          size: 22,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'RoadGuard',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
          color: light ? Colors.white : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        'AI',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          color: light
              ? RoadColors.blueTint
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    ],
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.text, {
    super.key,
    this.color,
    this.background,
    this.icon,
  });
  final String text;
  final Color? color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background ?? RoadColors.bluePill,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: color ?? RoadColors.bluePillInk,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            color: color ?? RoadColors.bluePillInk,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Reference card: white, 1 px #DFE7E9 border, 18 px radius.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(15),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.radius = 18,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Full-width reference action card: icon, label, chevron.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    margin: EdgeInsets.zero,
    padding: const EdgeInsets.all(15),
    onTap: onTap,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(icon, size: 21, color: RoadColors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: subtitle == null
              ? Text(title, style: Theme.of(context).textTheme.titleMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Reference hero banner: dark navy-blue gradient, uppercase eyebrow, big number.
class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.eyebrow,
    required this.value,
    required this.caption,
    this.children = const [],
  });
  final String eyebrow;
  final String value;
  final String caption;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment(-.85, -.35),
        end: Alignment(.9, .5),
        colors: [RoadColors.heroGradientStart, RoadColors.heroGradientEnd],
      ),
      borderRadius: BorderRadius.circular(25),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              size: 15,
              color: RoadColors.heroSoft,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: RoadColors.heroSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 45,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        ...children,
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: RoadColors.deepBlue,
          ),
        ),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 7),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: RoadColors.blueBright),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      );
      return constraints.hasBoundedHeight
          ? SingleChildScrollView(child: content)
          : content;
    },
  );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (error, stack) => EmptyView(
      icon: Icons.wifi_off_rounded,
      title: 'That didn’t load',
      message: readableError(error),
      action: 'Try again',
      onAction: onRetry,
    ),
  );
}

/// Reference heading bar: white strip, 38 px circular back button, bold title.
/// The router's AppBar styling is replaced everywhere this scaffold is used.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.child,
    this.bottom,
    this.actions,
  });
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 13),
            child: Row(
              children: [
                _BackCircle(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: RoadColors.ink,
                    ),
                  ),
                ),
                ...?actions,
              ],
            ),
          ),
          Expanded(
            child: child,
          ),
          if (bottom != null)
            SafeArea(
              top: false,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: bottom!,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Reference settings row: label + trailing control, #e7eeee divider below.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.isLast = false,
  });
  final String label;
  final IconData? icon;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: RoadColors.blue),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(
              value!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ?trailing,
        ],
      ),
    );
    return Column(
      children: [
        onTap == null
            ? row
            : InkWell(onTap: onTap, child: row),
        if (!isLast) const Divider(height: 1, color: RoadColors.settingDivider),
      ],
    );
  }
}

class _BackCircle extends StatelessWidget {
  const _BackCircle();
  @override
  Widget build(BuildContext context) => Material(
    color: RoadColors.headingCircle,
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: 'Back',
        padding: EdgeInsets.zero,
        iconSize: 21,
        onPressed: () =>
            context.canPop() ? context.pop() : context.go(HomePaths.explore),
        icon: const Icon(Icons.arrow_back_rounded, color: RoadColors.ink),
      ),
    ),
  );
}

String readableError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Bad state: |Invalid argument\(s\): |FormatException: )'),
  '',
);

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(readableError(error))));
    }
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirm),
            ),
          ],
        ),
      ) ??
      false;
}
