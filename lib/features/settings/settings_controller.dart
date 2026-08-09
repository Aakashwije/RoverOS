import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/settings.dart';

/// Owns [AppSettings] and writes every change straight through to storage.
///
/// All mutations funnel through [update] so nothing can bypass [
/// AppSettings.normalized] and persist an out-of-range value.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(storageServiceProvider).loadSettings();

  void update(AppSettings Function(AppSettings current) transform) {
    final next = transform(state).normalized();
    // AppSettings has no structural equality; comparing the serialised form
    // keeps a dragged slider from writing to disk on every frame.
    if (jsonEncode(next.toJson()) == jsonEncode(state.toJson())) return;
    state = next;
    ref.read(storageServiceProvider).saveSettings(next);
  }

  void resetToDefaults() {
    state = AppSettings.defaults;
    ref.read(storageServiceProvider).saveSettings(state);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
