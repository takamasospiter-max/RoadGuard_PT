import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/shared/providers_list.dart';
import 'package:roadguard_ai/core/routes/app_router.dart';

class RoadGuardApp extends ConsumerStatefulWidget {
  const RoadGuardApp({super.key});
  @override
  ConsumerState<RoadGuardApp> createState() => _RoadGuardAppState();
}

class _RoadGuardAppState extends ConsumerState<RoadGuardApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Speech must not keep talking when the user leaves the preview app.
      unawaited(
        ref.read(voiceServiceProvider).stop().catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'RoadGuard AI',
      debugShowCheckedModeBanner: false,
      theme: roadTheme(Brightness.light),
      darkTheme: roadTheme(Brightness.dark),
      themeMode: switch (settings.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: child!,
          ),
        ),
      ),
    );
  }
}
