import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/command_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/vehicle.dart';
import '../../models/vehicle_kind.dart';
import '../../services/car_protocol.dart';
import '../../services/transport/bluetooth_transport.dart';
import '../../services/transport/mock_transport.dart';
import '../../services/transport/transport.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';

/// The active transport, chosen by the mock-mode setting and the active
/// [VehicleKind].
///
/// Flipping mock mode — or switching vehicle kind — disposes the old
/// transport and rebuilds this provider, so nothing can keep sending on a
/// stale link or against the wrong BLE profile.
final transportProvider = Provider<Transport>((ref) {
  final useMock = ref.watch(settingsProvider.select((s) => s.mockMode));
  final kind = ref.watch(settingsProvider.select((s) => s.vehicleKind));
  final Transport transport = useMock
      ? MockTransport(kind: kind)
      : BluetoothTransport(profile: kind.bleProfile);

  ref.onDispose(transport.dispose);
  return transport;
});

/// Devices seen during the current scan.
final scanResultsProvider =
    NotifierProvider<ScanResults, List<DiscoveredVehicle>>(ScanResults.new);

class ScanResults extends Notifier<List<DiscoveredVehicle>> {
  @override
  List<DiscoveredVehicle> build() => const [];

  void replace(List<DiscoveredVehicle> devices) {
    final hints = ref.read(settingsProvider).vehicleKind.nameHints;
    // Likely vehicles of the active kind first, then by signal strength.
    final sorted = [...devices]
      ..sort((a, b) {
        final aLikely = a.looksLike(hints);
        final bLikely = b.looksLike(hints);
        if (aLikely != bLikely) return aLikely ? -1 : 1;
        return (b.rssi ?? -999).compareTo(a.rssi ?? -999);
      });
    state = List.unmodifiable(sorted);
  }

  void clear() => state = const [];
}

/// The most recent vehicle-reported error, or `null` once acknowledged.
final vehicleErrorProvider =
    NotifierProvider<VehicleErrorController, RoverError?>(
      VehicleErrorController.new,
    );

class VehicleErrorController extends Notifier<RoverError?> {
  @override
  RoverError? build() => null;

  void report(RoverError error) => state = error;

  void dismiss() => state = null;
}

/// The verb of the last acknowledged command, for the telemetry dashboard.
final lastAckProvider = NotifierProvider<LastAckController, CommandAck?>(
  LastAckController.new,
);

class LastAckController extends Notifier<CommandAck?> {
  @override
  CommandAck? build() => null;

  void report(CommandAck ack) => state = ack;
}

/// Owns the link to the vehicle: scanning, connecting, reconnecting, and
/// routing inbound frames to the telemetry, ACK and error providers.
///
/// It never decides anything about driving — it only moves frames.
class ConnectionController extends Notifier<LinkState> {
  StreamSubscription<String>? _inboundSubscription;
  StreamSubscription<TransportStatus>? _statusSubscription;
  StreamSubscription<List<DiscoveredVehicle>>? _scanSubscription;
  Timer? _rssiTimer;
  Timer? _reconnectTimer;

  /// Set while a user-initiated disconnect is in flight, so the resulting
  /// transport event is not mistaken for a dropout worth reconnecting to.
  bool _intentionalDisconnect = false;

  @override
  LinkState build() {
    final isMock = ref.watch(settingsProvider.select((s) => s.mockMode));
    // Watched (not read): switching vehicle kind must rebuild this controller
    // against the newly-active transport and its own remembered device,
    // exactly as switching mock mode already does.
    final kind = ref.watch(settingsProvider.select((s) => s.vehicleKind));
    final remembered = ref.read(storageServiceProvider).loadVehicle(kind);

    _attachTransport();
    ref.onDispose(_teardown);

    if (remembered == null) return LinkState(isMock: isMock);
    return LinkState(
      deviceId: remembered.id,
      deviceName: remembered.name,
      isMock: isMock,
    );
  }

  Transport get _transport => ref.read(transportProvider);

  void _teardown() {
    _inboundSubscription?.cancel();
    _statusSubscription?.cancel();
    _scanSubscription?.cancel();
    _rssiTimer?.cancel();
    _reconnectTimer?.cancel();
  }

  void _attachTransport() {
    final transport = _transport;

    _inboundSubscription?.cancel();
    _inboundSubscription = transport.subscribe().listen(_handleFrame);

    _statusSubscription?.cancel();
    _statusSubscription = transport.status.listen(_handleTransportStatus);
  }

  // --- Inbound frames -------------------------------------------------------

  void _handleFrame(String raw) {
    final frame = CarProtocol.parseFrame(raw);
    switch (frame) {
      case TelemetryFrame(:final telemetry):
        ref.read(telemetryProvider.notifier).apply(telemetry);
      case AckFrame(:final ack):
        ref.read(lastAckProvider.notifier).report(ack);
      case ErrorFrame(:final error):
        _handleVehicleError(error);
      case UnknownFrame(:final reason, :final raw):
        // Kept visible during bring-up; a firmware mismatch should not be silent.
        debugPrint('ROVEROS: dropped frame ($reason): $raw');
    }
  }

  void _handleVehicleError(RoverError error) {
    ref.read(vehicleErrorProvider.notifier).report(error);
    ref
        .read(activityLogProvider.notifier)
        .record(
          error.code == RoverErrorCode.watchdogStop
              ? 'Vehicle stopped by safety timeout'
              : 'Vehicle error: ${error.message}',
          detail: error.message,
          severity: error.isFailSafe
              ? ActivitySeverity.error
              : ActivitySeverity.warning,
        );
  }

  void _handleTransportStatus(TransportStatus status) {
    switch (status) {
      case TransportStatus.connected:
        _onConnected();
      case TransportStatus.disconnected:
        _onDisconnected();
      case TransportStatus.failed:
        state = state.copyWith(
          status: ConnectionStatus.error,
          errorMessage: TransportFailure.connectionFailed.message,
        );
      case TransportStatus.idle:
      case TransportStatus.scanning:
      case TransportStatus.connecting:
        break;
    }
  }

  // --- Connection lifecycle -------------------------------------------------

  Future<void> startScan() async {
    if (state.status == ConnectionStatus.scanning) return;

    ref.read(scanResultsProvider.notifier).clear();
    state = state.copyWith(
      status: ConnectionStatus.scanning,
      // Published so the UI can run a countdown against the same deadline the
      // transport is using, rather than guessing at one of its own.
      scanEndsAt: DateTime.now().add(AppConfig.scanTimeout),
      clearError: true,
    );

    try {
      _scanSubscription?.cancel();
      _scanSubscription = _transport.scan().listen(
        ref.read(scanResultsProvider.notifier).replace,
        onDone: () {
          if (state.status != ConnectionStatus.scanning) return;
          state = state.copyWith(
            status: ConnectionStatus.idle,
            clearScanSchedule: true,
          );
        },
        onError: (Object error) => _reportTransportError(error),
      );
    } on TransportException catch (error) {
      _reportTransportError(error);
    }
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _transport.stopScan();
    if (state.status == ConnectionStatus.scanning) {
      state = state.copyWith(
        status: ConnectionStatus.idle,
        clearScanSchedule: true,
      );
    }
  }

  Future<void> connectTo(DiscoveredVehicle vehicle) =>
      _connect(deviceId: vehicle.id, deviceName: vehicle.name);

  /// Reconnects to the saved vehicle of the active kind. No-op when nothing
  /// is remembered.
  Future<void> reconnectSaved() async {
    final kind = ref.read(settingsProvider).vehicleKind;
    final remembered = ref.read(storageServiceProvider).loadVehicle(kind);
    if (remembered == null) return;
    await _connect(deviceId: remembered.id, deviceName: remembered.name);
  }

  Future<void> _connect({
    required String deviceId,
    required String deviceName,
  }) async {
    _reconnectTimer?.cancel();
    await stopScan();

    state = state.copyWith(
      status: ConnectionStatus.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
      clearReconnectSchedule: true,
    );

    try {
      await _transport.connect(deviceId: deviceId);
      await ref
          .read(storageServiceProvider)
          .saveVehicle(
            RememberedVehicle(
              id: deviceId,
              name: deviceName,
              kind: ref.read(settingsProvider).vehicleKind,
              lastConnected: DateTime.now(),
            ),
          );
    } on TransportException catch (error) {
      _reportTransportError(error);
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    await _transport.disconnect();
    ref
        .read(activityLogProvider.notifier)
        .record(
          'Disconnected from ${state.displayName}',
          severity: ActivitySeverity.info,
        );
  }

  void _onConnected() {
    _intentionalDisconnect = false;
    _reconnectTimer?.cancel();

    state = state.copyWith(
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      reconnectAttempt: 0,
      clearError: true,
      clearReconnectSchedule: true,
    );

    _startRssiPolling();
    _pushWatchdogConfig();

    ref
        .read(activityLogProvider.notifier)
        .record(
          'Connected to ${state.displayName}',
          detail: state.isMock ? 'Mock vehicle' : 'Bluetooth link established',
          severity: ActivitySeverity.success,
        );
  }

  void _onDisconnected() {
    _rssiTimer?.cancel();
    // Telemetry from a dead link must not linger on screen as current truth.
    ref.read(telemetryProvider.notifier).reset();

    if (_intentionalDisconnect) {
      _intentionalDisconnect = false;
      state = state.copyWith(status: ConnectionStatus.idle, rssi: null);
      return;
    }

    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      errorMessage: TransportFailure.disconnected.message,
      rssi: null,
    );

    ref
        .read(activityLogProvider.notifier)
        .record(
          'Link lost',
          detail: 'The vehicle safety timeout will stop the motors',
          severity: ActivitySeverity.error,
        );

    if (ref.read(settingsProvider).autoReconnect) _scheduleReconnect();
  }

  /// Exponential backoff, capped and attempt-limited so a rover that is simply
  /// switched off does not get hammered by the radio.
  void _scheduleReconnect() {
    final attempt = state.reconnectAttempt;
    if (attempt >= AppConfig.maxReconnectAttempts) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage:
            'Could not reach ${state.displayName} after '
            '${AppConfig.maxReconnectAttempts} attempts. Check that it is powered on.',
        clearReconnectSchedule: true,
      );
      return;
    }

    final delayMs =
        AppConfig.reconnectBaseDelay.inMilliseconds * (1 << attempt);
    final delay = Duration(
      milliseconds: delayMs.clamp(
        AppConfig.reconnectBaseDelay.inMilliseconds,
        AppConfig.reconnectMaxDelay.inMilliseconds,
      ),
    );

    state = state.copyWith(
      status: ConnectionStatus.reconnecting,
      reconnectAttempt: attempt + 1,
      nextReconnectAt: DateTime.now().add(delay),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (state.status != ConnectionStatus.reconnecting) return;
      final deviceId = state.deviceId;
      if (deviceId == null) return;
      try {
        await _transport.connect(deviceId: deviceId);
      } on TransportException {
        _scheduleReconnect();
      }
    });
  }

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    state = state.copyWith(
      status: ConnectionStatus.idle,
      reconnectAttempt: 0,
      clearReconnectSchedule: true,
    );
  }

  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!state.isConnected) return;
      final rssi = await _transport.readRssi();
      if (rssi == null || !state.isConnected) return;
      state = state.copyWith(rssi: rssi);
    });
  }

  /// Tells the firmware how long it may go without a drive command before it
  /// cuts the motors. The vehicle, not the phone, enforces this.
  void _pushWatchdogConfig() {
    final timeout = ref.read(settingsProvider).commandTimeoutMs;
    final command = CarProtocol.buildConfigCommand(timeoutMs: timeout);
    _transport.send(command.frame).ignore();
  }

  void _reportTransportError(Object error) {
    final failure = error is TransportException
        ? error.failure
        : TransportFailure.connectionFailed;

    state = state.copyWith(
      status: switch (failure) {
        TransportFailure.permissionDenied =>
          ConnectionStatus.permissionRequired,
        TransportFailure.adapterOff => ConnectionStatus.bluetoothOff,
        _ => ConnectionStatus.error,
      },
      errorMessage: failure.message,
      clearScanSchedule: true,
    );

    ref
        .read(activityLogProvider.notifier)
        .record(
          failure.title,
          detail: failure.message,
          severity: ActivitySeverity.error,
        );
  }

  // --- Device memory --------------------------------------------------------

  Future<void> forgetDevice() async {
    if (state.isConnected) await disconnect();
    await ref
        .read(storageServiceProvider)
        .forgetVehicle(ref.read(settingsProvider).vehicleKind);
    state = LinkState(isMock: state.isMock);
    ref
        .read(activityLogProvider.notifier)
        .record(
          'Vehicle forgotten',
          detail: 'Saved device removed from this phone',
        );
  }
}

final connectionProvider = NotifierProvider<ConnectionController, LinkState>(
  ConnectionController.new,
);
