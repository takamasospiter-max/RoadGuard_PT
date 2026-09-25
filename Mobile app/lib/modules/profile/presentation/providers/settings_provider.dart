import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/models/models.dart';
import 'package:roadguard_ai/core/injection/service_providers.dart';

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  bool _saving = false;
  @override
  AppSettings build() => ref.read(initialSettingsProvider);
  Future<void> update(AppSettings Function(AppSettings) change) async {
    if (_saving) {
      throw StateError('Please wait for the previous setting to save.');
    }
    _saving = true;
    try {
      final next = change(state);
      await ref.read(settingsStoreProvider).save(next);
      state = next;
    } finally {
      _saving = false;
    }
  }
}
