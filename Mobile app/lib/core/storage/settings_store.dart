import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class DeviceSettingsStore implements SettingsStore {
  DeviceSettingsStore({this.key = 'roadguard.settings.v1'});

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final String key;
  @override
  Future<AppSettings> load() async {
    final value = await _preferences.getString(key);
    if (value == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> save(AppSettings settings) =>
      _preferences.setString(key, jsonEncode(settings.toJson()));
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.value = const AppSettings()]);
  AppSettings value;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}
