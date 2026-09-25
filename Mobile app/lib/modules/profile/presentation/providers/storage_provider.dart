import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';

final telemetryCountProvider = FutureProvider<int>(
  (ref) => ref.watch(localStoreProvider).telemetryCount(),
);
