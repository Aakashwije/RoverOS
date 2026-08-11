import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';

/// Lifecycle of the link to the vehicle.
enum ConnectionStatus {
  idle('IDLE', 'Not connected'),
  permissionRequired('PERMISSION REQUIRED', 'Bluetooth permission is needed'),
  bluetoothOff('BLUETOOTH OFF', 'Turn on Bluetooth to continue'),
  scanning('SCANNING', 'Looking for vehicles'),
  connecting('CONNECTING', 'Establishing link'),
  connected('CONNECTED', 'Vehicle linked'),
  disconnected('DISCONNECTED', 'Link lost'),
  reconnecting('RECONNECTING', 'Trying to restore the link'),
  error('ERROR', 'Connection problem');

  const ConnectionStatus(this.label, this.description);

  final String label;
  final String description;

  bool get isConnected => this == connected;

  bool get isBusy =>
      this == scanning || this == connecting || this == reconnecting;

  /// True when the app cannot currently command the vehicle. The ESP32 watchdog
  /// is the authority that actually stops the motors in these states.
  bool get isOffline => !isConnected;

  StatusLevel get level => switch (this) {
    connected => StatusLevel.good,
    scanning || connecting || reconnecting => StatusLevel.info,
    disconnected || error => StatusLevel.danger,
    permissionRequired || bluetoothOff => StatusLevel.caution,
    idle => StatusLevel.neutral,
  };
}

/// Human-facing bucketing of RSSI.
enum SignalQuality {
  excellent('EXCELLENT', 4),
  good('GOOD', 3),
  fair('FAIR', 2),
  weak('WEAK', 1),
  none('NO SIGNAL', 0);

  const SignalQuality(this.label, this.bars);

  final String label;

  /// 0–4, for the bar-style signal meter.
  final int bars;

  static SignalQuality fromRssi(int? rssi) {
    if (rssi == null || rssi == 0) return none;
    if (rssi >= AppConfig.rssiExcellent) return excellent;
    if (rssi >= AppConfig.rssiGood) return good;
    if (rssi >= AppConfig.rssiFair) return fair;
    return weak;
  }

  /// Percentage used by progress meters and the `SIG` telemetry field.
  int get percent => switch (this) {
    excellent => 100,
    good => 75,
    fair => 50,
    weak => 25,
    none => 0,
  };

  StatusLevel get level => switch (this) {
    excellent || good => StatusLevel.good,
    fair => StatusLevel.caution,
    weak || none => StatusLevel.danger,
  };
}

/// Everything the UI needs to describe the link, in one immutable value.
class LinkState {
  const LinkState({
    this.status = ConnectionStatus.idle,
    this.deviceId,
    this.deviceName,
    this.rssi,
    this.errorMessage,
    this.reconnectAttempt = 0,
    this.nextReconnectAt,
    this.isMock = false,
    this.connectedAt,
    this.scanEndsAt,
  });

  final ConnectionStatus status;
  final String? deviceId;
  final String? deviceName;
  final int? rssi;

  /// Actionable text, never "something went wrong".
  final String? errorMessage;

  final int reconnectAttempt;

  /// When the next backoff-scheduled reconnect fires, for the countdown UI.
  final DateTime? nextReconnectAt;

  final bool isMock;
  final DateTime? connectedAt;

  /// When the running scan will time out, for the progress countdown.
  ///
  /// A scan that just spins forever is indistinguishable from one that has
  /// hung; showing how long it has left turns waiting into a known quantity.
  final DateTime? scanEndsAt;

  SignalQuality get signal =>
      status.isConnected ? SignalQuality.fromRssi(rssi) : SignalQuality.none;

  bool get isConnected => status.isConnected;

  String get displayName => deviceName ?? deviceId ?? 'No vehicle';

  bool get hasRememberedDevice => deviceId != null;

  Duration? get uptime =>
      connectedAt == null ? null : DateTime.now().difference(connectedAt!);

  LinkState copyWith({
    ConnectionStatus? status,
    String? deviceId,
    String? deviceName,
    int? rssi,
    String? errorMessage,
    int? reconnectAttempt,
    DateTime? nextReconnectAt,
    bool? isMock,
    DateTime? connectedAt,
    DateTime? scanEndsAt,
    bool clearError = false,
    bool clearDevice = false,
    bool clearReconnectSchedule = false,
    bool clearScanSchedule = false,
  }) {
    return LinkState(
      status: status ?? this.status,
      deviceId: clearDevice ? null : (deviceId ?? this.deviceId),
      deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
      rssi: clearDevice ? null : (rssi ?? this.rssi),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      nextReconnectAt: clearReconnectSchedule
          ? null
          : (nextReconnectAt ?? this.nextReconnectAt),
      isMock: isMock ?? this.isMock,
      connectedAt: clearDevice ? null : (connectedAt ?? this.connectedAt),
      scanEndsAt: clearScanSchedule ? null : (scanEndsAt ?? this.scanEndsAt),
    );
  }

  @override
  String toString() => 'LinkState(${status.name}, $displayName, rssi: $rssi)';
}
