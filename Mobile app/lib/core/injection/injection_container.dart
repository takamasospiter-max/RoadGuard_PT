import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../storage/local_store.dart';
import '../storage/settings_store.dart';
import 'service_providers.dart';

/// Loads persisted state before the application's providers are created.
class AppDependencies {
  const AppDependencies._({
    required this.localStore,
    required this.settingsStore,
    required this.settings,
    required this.activeTrip,
  });

  final LocalStore localStore;
  final SettingsStore settingsStore;
  final AppSettings settings;
  final TripRecord? activeTrip;

  static Future<AppDependencies> load({
    SettingsStore? settingsStore,
    Future<LocalStore> Function()? openStore,
  }) async {
    final preferences = settingsStore ?? DeviceSettingsStore();
    final settings = await preferences.load();
    final store = await (openStore ?? openLocalStore)();
    try {
      final activeTrip = (await store.trips())
          .where((trip) => trip.isActive)
          .firstOrNull;
      return AppDependencies._(
        localStore: store,
        settingsStore: preferences,
        settings: settings,
        activeTrip: activeTrip,
      );
    } catch (_) {
      // Release the failed connection so retry can reopen existing data.
      // Never erase data or silently replace native storage on failure.
      await store.close();
      rethrow;
    }
  }

  ProviderScope scope({required Widget child}) => ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(localStore),
      settingsStoreProvider.overrideWithValue(settingsStore),
      initialSettingsProvider.overrideWithValue(settings),
      initialTripProvider.overrideWithValue(activeTrip),
    ],
    child: child,
  );
}
