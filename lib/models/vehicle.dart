import '../core/constants/app_config.dart';
import 'connection_state.dart';

/// A vehicle discovered during a scan, or remembered from a previous session.
///
/// Device identifiers always come from a live scan or from storage — ROVEROS
/// never hardcodes a MAC or BLE id.
class DiscoveredVehicle {
  const DiscoveredVehicle({
    required this.id,
    required this.name,
    this.rssi,
    this.isConnectable = true,
    this.lastSeen,
  });

  /// Platform device identifier (Android MAC, iOS CoreBluetooth UUID).
  final String id;

  final String name;
  final int? rssi;
  final bool isConnectable;
  final DateTime? lastSeen;

  SignalQuality get signal => SignalQuality.fromRssi(rssi);

  bool get hasName => name.trim().isNotEmpty;

  String get displayName => hasName ? name : 'Unnamed device';

  /// True when the advertised name looks like a rover controller. Used to sort
  /// likely vehicles above unrelated peripherals in the scan list.
  bool get looksLikeRover {
    final upper = name.toUpperCase();
    return AppConfig.knownDeviceNameHints.any(upper.contains);
  }

  DiscoveredVehicle copyWith({
    int? rssi,
    DateTime? lastSeen,
    bool? isConnectable,
  }) {
    return DiscoveredVehicle(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      isConnectable: isConnectable ?? this.isConnectable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveredVehicle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DiscoveredVehicle($displayName, $id, rssi: $rssi)';
}

/// A vehicle the user has paired with before.
class RememberedVehicle {
  const RememberedVehicle({
    required this.id,
    required this.name,
    required this.lastConnected,
  });

  final String id;
  final String name;
  final DateTime lastConnected;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastConnected': lastConnected.toIso8601String(),
  };

  static RememberedVehicle? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    return RememberedVehicle(
      id: id,
      name: name,
      lastConnected:
          DateTime.tryParse(json['lastConnected'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  String toString() => 'RememberedVehicle($name, $id)';
}

/// A single line in the Home screen's recent-activity feed.
class ActivityEntry {
  const ActivityEntry({
    required this.message,
    required this.timestamp,
    this.detail,
    this.severity = ActivitySeverity.info,
  });

  final String message;
  final String? detail;
  final DateTime timestamp;
  final ActivitySeverity severity;

  @override
  String toString() => 'ActivityEntry($message)';
}

enum ActivitySeverity { info, success, warning, error }
