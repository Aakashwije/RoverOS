import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vehicle.dart';
import '../../services/storage_service.dart';

/// Overridden in `main()` once [StorageService.create] has resolved, so every
/// consumer can read persisted state synchronously.
final storageServiceProvider = Provider<StorageService>(
  (ref) => throw StateError(
    'storageServiceProvider was not overridden. '
    'Wrap the app in a ProviderScope that supplies a StorageService.',
  ),
);

/// Rolling feed of notable events, surfaced on Home and persisted between runs.
class ActivityLog extends Notifier<List<ActivityEntry>> {
  static const int _maxEntries = 20;

  @override
  List<ActivityEntry> build() =>
      ref.read(storageServiceProvider).loadActivity();

  void record(
    String message, {
    String? detail,
    ActivitySeverity severity = ActivitySeverity.info,
  }) {
    final entry = ActivityEntry(
      message: message,
      detail: detail,
      timestamp: DateTime.now(),
      severity: severity,
    );
    state = [entry, ...state].take(_maxEntries).toList(growable: false);
    ref.read(storageServiceProvider).saveActivity(state);
  }

  void clear() {
    state = const [];
    ref.read(storageServiceProvider).clearActivity();
  }
}

final activityLogProvider = NotifierProvider<ActivityLog, List<ActivityEntry>>(
  ActivityLog.new,
);
