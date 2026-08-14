import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/command_constants.dart';
import '../../models/vehicle.dart';
import '../../models/vehicle_kind.dart';
import 'transport.dart';

/// Bluetooth Low Energy link to a vehicle, speaking whichever [BleProfile]
/// [profile] describes — the Nordic UART Service for the car, an HM-10/AT-09
/// style single-characteristic profile for the spiderbot's add-on BLE module.
///
/// Responsibilities stop at moving bytes: this class discovers the service,
/// keeps a subscription open, reassembles frames and reports failures in terms
/// the UI can act on. It never interprets a command.
class BluetoothTransport implements Transport {
  BluetoothTransport({required BleProfile profile})
    : _serviceUuid = Guid(profile.serviceUuid),
      _rxUuid = Guid(profile.writeCharUuid),
      _txUuid = Guid(profile.notifyCharUuid);

  /// May be identical to [_txUuid] — some BLE-serial modules use one
  /// characteristic for both write and notify. [_bindUartService] handles
  /// that case with no special casing: both lookups simply resolve to the
  /// same characteristic.
  final Guid _serviceUuid;
  final Guid _rxUuid;
  final Guid _txUuid;

  final _statusController = StreamController<TransportStatus>.broadcast();
  final _inboundController = StreamController<String>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamController<List<DiscoveredVehicle>>? _scanResultsController;

  BluetoothDevice? _device;

  /// Characteristic the phone writes commands to.
  BluetoothCharacteristic? _writeCharacteristic;

  TransportStatus _status = TransportStatus.idle;

  /// Partial frame carried between notifications. BLE delivers arbitrary
  /// chunks, so a frame can straddle two packets.
  final StringBuffer _rxBuffer = StringBuffer();

  @override
  TransportKind get kind => TransportKind.bluetooth;

  @override
  Stream<TransportStatus> get status => _statusController.stream;

  @override
  TransportStatus get currentStatus => _status;

  @override
  String? get connectedDeviceId => _device?.remoteId.str;

  // --- Scanning -------------------------------------------------------------

  @override
  Stream<List<DiscoveredVehicle>> scan({Duration? timeout}) {
    _scanResultsController?.close();
    final controller = StreamController<List<DiscoveredVehicle>>();
    _scanResultsController = controller;

    unawaited(_runScan(controller, timeout ?? AppConfig.scanTimeout));
    controller.onCancel = stopScan;
    return controller.stream;
  }

  Future<void> _runScan(
    StreamController<List<DiscoveredVehicle>> controller,
    Duration timeout,
  ) async {
    try {
      await _ensureAdapterReady();
      _setStatus(TransportStatus.scanning);

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          if (controller.isClosed) return;
          controller.add([
            for (final result in results) _toDiscoveredVehicle(result),
          ]);
        },
        onError: (Object error) {
          if (!controller.isClosed) controller.addError(_mapError(error));
        },
      );

      // No service filter: many ESP32 sketches advertise a name only and
      // expose the UART service after connecting, so filtering here would hide
      // otherwise perfectly good rovers.
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      // startScan completes when the timeout elapses.
      await stopScan();
      if (!controller.isClosed) await controller.close();
    } on Object catch (error) {
      if (!controller.isClosed) {
        controller.addError(_mapError(error));
        await controller.close();
      }
      _setStatus(TransportStatus.failed);
    }
  }

  DiscoveredVehicle _toDiscoveredVehicle(ScanResult result) {
    final advertised = result.advertisementData.advName;
    final platformName = result.device.platformName;
    return DiscoveredVehicle(
      id: result.device.remoteId.str,
      name: advertised.isNotEmpty ? advertised : platformName,
      rssi: result.rssi,
      isConnectable: result.advertisementData.connectable,
      lastSeen: DateTime.now(),
    );
  }

  @override
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();

    final controller = _scanResultsController;
    _scanResultsController = null;
    if (controller != null && !controller.isClosed) await controller.close();

    if (_status == TransportStatus.scanning) {
      _setStatus(
        _device == null ? TransportStatus.idle : TransportStatus.connected,
      );
    }
  }

  // --- Connection -----------------------------------------------------------

  @override
  Future<void> connect({String? deviceId}) async {
    final targetId = deviceId ?? connectedDeviceId;
    if (targetId == null) {
      throw const TransportException(TransportFailure.deviceNotFound);
    }

    await stopScan();
    _setStatus(TransportStatus.connecting);

    try {
      await _ensureAdapterReady();

      final device = BluetoothDevice.fromId(targetId);
      _device = device;

      // autoConnect is deliberately off: ROVEROS owns reconnect scheduling so
      // backoff stays visible to the user instead of the OS retrying silently.
      //
      // flutter_blue_plus 2.x requires the caller to declare a licence tier.
      // License.nonprofit covers personal, educational and nonprofit use; a
      // commercial release of this app would need License.commercial.
      await device.connect(
        license: License.nonprofit,
        timeout: AppConfig.connectTimeout,
        autoConnect: false,
        mtu: AppConfig.preferredMtu,
      );

      _watchConnectionState(device);
      await _bindUartService(device);

      _setStatus(TransportStatus.connected);
    } on TransportException {
      await _cleanupDevice();
      _setStatus(TransportStatus.failed);
      rethrow;
    } on Object catch (error) {
      await _cleanupDevice();
      _setStatus(TransportStatus.failed);
      throw _mapError(error);
    }
  }

  void _watchConnectionState(BluetoothDevice device) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state != BluetoothConnectionState.disconnected) return;
      _rxBuffer.clear();
      _writeCharacteristic = null;
      _setStatus(TransportStatus.disconnected);
    });
  }

  Future<void> _bindUartService(BluetoothDevice device) async {
    final services = await device.discoverServices();

    final uart = services.where((s) => s.uuid == _serviceUuid).firstOrNull;
    if (uart == null) {
      throw const TransportException(TransportFailure.serviceNotFound);
    }

    _writeCharacteristic = uart.characteristics
        .where((c) => c.uuid == _rxUuid)
        .firstOrNull;
    final notify = uart.characteristics
        .where((c) => c.uuid == _txUuid)
        .firstOrNull;

    if (_writeCharacteristic == null || notify == null) {
      throw const TransportException(TransportFailure.serviceNotFound);
    }

    await notify.setNotifyValue(true);
    _notifySubscription?.cancel();
    _notifySubscription = notify.onValueReceived.listen(_ingest);
  }

  /// Reassembles frames from BLE packets, which arrive without regard for
  /// frame boundaries.
  void _ingest(List<int> chunk) {
    _rxBuffer.write(utf8.decode(chunk, allowMalformed: true));
    var buffered = _rxBuffer.toString();

    // A device that never sends a terminator must not grow this without bound.
    if (buffered.length > Wire.maxFrameLength * 4) {
      final lastTerminator = buffered.lastIndexOf(Wire.terminator);
      buffered = lastTerminator < 0
          ? ''
          : buffered.substring(lastTerminator + 1);
    }

    final segments = buffered.split(Wire.terminator);
    // The trailing segment is an incomplete frame; hold it for the next packet.
    final remainder = segments.removeLast();

    for (final segment in segments) {
      final frame = segment.trim();
      if (frame.isEmpty) continue;
      if (!_inboundController.isClosed) _inboundController.add(frame);
    }

    _rxBuffer
      ..clear()
      ..write(remainder);
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    await _cleanupDevice();
    if (device != null) {
      try {
        await device.disconnect();
      } on Object catch (error) {
        debugPrint('ROVEROS: disconnect reported $error');
      }
    }
    _setStatus(TransportStatus.disconnected);
  }

  @override
  Future<void> send(String command) async {
    final characteristic = _writeCharacteristic;
    if (characteristic == null || _status != TransportStatus.connected) {
      throw const TransportException(TransportFailure.writeFailed);
    }

    try {
      // Write-without-response keeps drive commands cheap; the firmware
      // watchdog, not an acknowledged write, is what guarantees safety.
      await characteristic.write(
        utf8.encode(command),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );
    } on Object catch (error) {
      throw TransportException(TransportFailure.writeFailed, cause: error);
    }
  }

  @override
  Stream<String> subscribe() => _inboundController.stream;

  @override
  Future<int?> readRssi() async {
    final device = _device;
    if (device == null || _status != TransportStatus.connected) return null;
    try {
      return await device.readRssi();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _cleanupDevice();
    await _scanSubscription?.cancel();
    await _scanResultsController?.close();
    await _statusController.close();
    await _inboundController.close();
  }

  // --- Internals ------------------------------------------------------------

  Future<void> _cleanupDevice() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _writeCharacteristic = null;
    _rxBuffer.clear();
  }

  void _setStatus(TransportStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  /// Confirms BLE is supported and switched on before any radio operation, so
  /// the user gets "turn on Bluetooth" rather than an opaque platform error.
  Future<void> _ensureAdapterReady() async {
    if (!await FlutterBluePlus.isSupported) {
      throw const TransportException(TransportFailure.unsupported);
    }

    final state = await FlutterBluePlus.adapterState.first;
    switch (state) {
      case BluetoothAdapterState.on:
        return;
      case BluetoothAdapterState.unauthorized:
        throw const TransportException(TransportFailure.permissionDenied);
      case BluetoothAdapterState.unavailable:
        throw const TransportException(TransportFailure.unsupported);
      case BluetoothAdapterState.off:
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.turningOff:
      case BluetoothAdapterState.unknown:
        throw const TransportException(TransportFailure.adapterOff);
    }
  }

  /// Maps plugin errors onto the app's actionable failure vocabulary.
  TransportException _mapError(Object error) {
    if (error is TransportException) return error;

    if (error is FlutterBluePlusException) {
      final description = (error.description ?? '').toLowerCase();
      if (description.contains('permission') ||
          description.contains('denied')) {
        return TransportException(
          TransportFailure.permissionDenied,
          cause: error,
        );
      }
      if (description.contains('adapter') ||
          description.contains('bluetooth must be turned on')) {
        return TransportException(TransportFailure.adapterOff, cause: error);
      }
      if (description.contains('timeout') ||
          description.contains('not found')) {
        return TransportException(
          TransportFailure.deviceNotFound,
          cause: error,
        );
      }
      return TransportException(
        TransportFailure.connectionFailed,
        cause: error,
      );
    }

    if (error is TimeoutException) {
      return TransportException(TransportFailure.deviceNotFound, cause: error);
    }

    return TransportException(TransportFailure.connectionFailed, cause: error);
  }
}
