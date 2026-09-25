import 'package:flutter/material.dart';

import 'app.dart';
import 'core/injection/injection_container.dart';
import 'shared/widgets/storage_failure_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
}

Future<void> bootstrap() async {
  AppDependencies? dependencies;
  try {
    dependencies = await AppDependencies.load();
    runApp(dependencies.scope(child: const RoadGuardApp()));
  } catch (_) {
    await dependencies?.localStore.close();
    // No automatic wipe or silent fallback if native persistence fails.
    runApp(StorageFailureApp(onRetry: bootstrap));
  }
}
