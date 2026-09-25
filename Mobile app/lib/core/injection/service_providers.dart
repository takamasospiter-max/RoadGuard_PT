import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../models/safety_policy.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';
import '../services/photo_service.dart';
import '../services/voice_service.dart';
import '../storage/local_store.dart';
import '../storage/settings_store.dart';

// Infrastructure enters through ProviderScope overrides at bootstrap and in tests.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('LocalStore was not initialized.'),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw StateError('SettingsStore was not initialized.'),
);
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);
final initialTripProvider = Provider<TripRecord?>((ref) => null);
final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const DevicePermissionService(),
);
final locationServiceProvider = Provider<LocationService>(
  (ref) =>
      DeviceLocationService(permissions: ref.watch(permissionServiceProvider)),
);
final photoServiceProvider = Provider<PhotoService>(
  (ref) =>
      DevicePhotoService(permissions: ref.watch(permissionServiceProvider)),
);
final voiceServiceProvider = Provider<VoiceService>(
  (ref) => DeviceVoiceService(),
);
final safetyPolicyProvider = Provider<SafetyPolicy>(
  (ref) => const SafetyPolicy(),
);
