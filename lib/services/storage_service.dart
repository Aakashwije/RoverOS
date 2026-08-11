import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';
import '../models/vehicle.dart';

/// Local persistence for settings, the remembered vehicle and recent activity.
///
/// Nothing sensitive is stored — only a device identifier the user explicitly
/// paired with, plus their own preferences.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const String _keySettings = 'roveros.settings.v1';
  static const String _keyVehicle = 'roveros.vehicle.v1';
  static const String _keyActivity = 'roveros.activity.v1';
  static const String _keyOnboarded = 'roveros.onboarded.v1';

  /// Recent-activity feed length. Older entries are discarded.
  static const int _maxActivityEntries = 20;

  static Future<StorageService> create() async =>
      StorageService(await SharedPreferences.getInstance());

  // --- Settings -------------------------------------------------------------

  /// Returns validated settings, falling back to defaults if the stored payload
  /// is missing or unreadable. Corrupt preferences must not block startup.
  AppSettings loadSettings() {
    final raw = _prefs.getString(_keySettings);
    if (raw == null) return AppSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return AppSettings.defaults;
      return AppSettings.fromJson(decoded);
    } on FormatException catch (error) {
      debugPrint('ROVEROS: discarding unreadable settings ($error)');
      return AppSettings.defaults;
    }
  }

  Future<bool> saveSettings(AppSettings settings) => _prefs.setString(
    _keySettings,
    jsonEncode(settings.normalized().toJson()),
  );

  // --- Remembered vehicle ---------------------------------------------------

  RememberedVehicle? loadVehicle() {
    final raw = _prefs.getString(_keyVehicle);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return RememberedVehicle.fromJson(decoded);
    } on FormatException catch (error) {
      debugPrint('ROVEROS: discarding unreadable vehicle record ($error)');
      return null;
    }
  }

  Future<bool> saveVehicle(RememberedVehicle vehicle) =>
      _prefs.setString(_keyVehicle, jsonEncode(vehicle.toJson()));

  Future<bool> forgetVehicle() => _prefs.remove(_keyVehicle);

  // --- First run ------------------------------------------------------------

  /// Whether the setup guide has been completed at least once.
  ///
  /// Kept out of [AppSettings] deliberately: it is a fact about this install,
  /// not a preference, and "reset all settings" must not resurrect the guide
  /// for someone who has already been driving for a month.
  bool loadOnboardingComplete() => _prefs.getBool(_keyOnboarded) ?? false;

  Future<bool> setOnboardingComplete({bool complete = true}) =>
      _prefs.setBool(_keyOnboarded, complete);

  // --- Activity feed --------------------------------------------------------

  List<ActivityEntry> loadActivity() {
    final raw = _prefs.getStringList(_keyActivity);
    if (raw == null) return const [];
    final entries = <ActivityEntry>[];
    for (final line in raw) {
      final entry = _decodeActivity(line);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  Future<bool> saveActivity(List<ActivityEntry> entries) {
    final trimmed = entries
        .take(_maxActivityEntries)
        .map(_encodeActivity)
        .toList();
    return _prefs.setStringList(_keyActivity, trimmed);
  }

  Future<bool> clearActivity() => _prefs.remove(_keyActivity);

  String _encodeActivity(ActivityEntry entry) => jsonEncode({
    'message': entry.message,
    'detail': entry.detail,
    'timestamp': entry.timestamp.toIso8601String(),
    'severity': entry.severity.name,
  });

  ActivityEntry? _decodeActivity(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return null;
      final message = decoded['message'];
      if (message is! String) return null;
      return ActivityEntry(
        message: message,
        detail: decoded['detail'] as String?,
        timestamp:
            DateTime.tryParse(decoded['timestamp'] as String? ?? '') ??
            DateTime.now(),
        severity: ActivitySeverity.values.firstWhere(
          (s) => s.name == decoded['severity'],
          orElse: () => ActivitySeverity.info,
        ),
      );
    } on FormatException {
      return null;
    }
  }

  /// Wipes every ROVEROS key, including the first-run flag — this is a full
  /// factory reset, not the settings-only one offered in the UI.
  Future<void> clearAll() async {
    await Future.wait([
      _prefs.remove(_keySettings),
      _prefs.remove(_keyVehicle),
      _prefs.remove(_keyActivity),
      _prefs.remove(_keyOnboarded),
    ]);
  }
}
