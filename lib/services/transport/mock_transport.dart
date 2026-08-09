import 'dart:async';
import 'dart:math' as math;

import '../../core/constants/app_config.dart';
import '../../core/constants/command_constants.dart';
import '../../core/utils/clamp.dart';
import '../../models/commands.dart';
import '../../models/vehicle.dart';
import 'transport.dart';

/// Faults a developer or demo can inject into the simulated rover.
enum MockFault { none, sensorFailure, motorFault, lowBattery, dropout }

/// A simulated ESP32 rover behind the real [Transport] interface.
///
/// This is what lets the whole app — including the safety behaviour — be built
/// and demonstrated with no hardware attached. It deliberately models the parts
/// that matter for correctness rather than physics: the command watchdog,
/// telemetry cadence, ACKs, battery drain under load and error frames.
class MockTransport implements Transport {
  MockTransport({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  final _statusController = StreamController<TransportStatus>.broadcast();
  final _inboundController = StreamController<String>.broadcast();

  Timer? _telemetryTimer;
  Timer? _scanTimer;
  StreamController<List<DiscoveredVehicle>>? _scanController;

  TransportStatus _status = TransportStatus.idle;
  String? _deviceId;

  // --- Simulated vehicle state ---------------------------------------------

  double _battery = 92;
  int _leftMotor = 0;
  int _rightMotor = 0;
  int _speedCeiling = 70;
  int _servoAngle = 90;
  double _distanceCm = 140;
  LightMode _lightMode = LightMode.off;
  DriveMode _driveMode = DriveMode.manual;
  ScanMode _scanMode = ScanMode.off;
  VehicleState _vehicleState = VehicleState.idle;
  String? _decision;

  MockFault _fault = MockFault.none;

  /// Firmware watchdog window, updated by `CMD:CONFIG`.
  Duration _commandTimeout = Duration(
    milliseconds: AppConfig.defaultCommandTimeoutMs,
  );

  DateTime _lastDriveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Direction the simulated servo sweep is travelling during an auto scan.
  int _sweepDirection = 1;

  @override
  TransportKind get kind => TransportKind.mock;

  @override
  Stream<TransportStatus> get status => _statusController.stream;

  @override
  TransportStatus get currentStatus => _status;

  @override
  String? get connectedDeviceId => _deviceId;

  /// Injects a fault so error handling can be exercised without hardware.
  void injectFault(MockFault fault) {
    _fault = fault;
    switch (fault) {
      case MockFault.lowBattery:
        _battery = 12;
      case MockFault.dropout:
        _dropLink();
      case MockFault.sensorFailure:
        _emit(
          '${Wire.prefixError}${Wire.fieldSeparator}'
          '${Wire.keyErrorCode}${Wire.keyValueSeparator}${RoverErrorCode.sensorFail.code}'
          '${Wire.fieldSeparator}${Wire.keyErrorMessage}${Wire.keyValueSeparator}SENSOR_FAIL',
        );
      case MockFault.motorFault:
        _emit(
          '${Wire.prefixError}${Wire.fieldSeparator}'
          '${Wire.keyErrorCode}${Wire.keyValueSeparator}${RoverErrorCode.motorFault.code}'
          '${Wire.fieldSeparator}${Wire.keyErrorMessage}${Wire.keyValueSeparator}MOTOR_FAULT',
        );
      case MockFault.none:
        break;
    }
  }

  void clearFaults() {
    _fault = MockFault.none;
    _battery = math.max(_battery, 55);
  }

  // --- Transport ------------------------------------------------------------

  @override
  Stream<List<DiscoveredVehicle>> scan({Duration? timeout}) {
    _scanController?.close();
    final controller = StreamController<List<DiscoveredVehicle>>();
    _scanController = controller;
    _setStatus(TransportStatus.scanning);

    final found = <DiscoveredVehicle>[];
    // A realistic scan trickles devices in rather than returning a full list,
    // so the UI's progressive-discovery path is what gets exercised.
    const catalogue = [
      ('MOCK-ESP32-CAR', 'mock-rover-01', -48),
      ('BT-Speaker', 'mock-other-01', -76),
      ('ESP32-CAR-B', 'mock-rover-02', -81),
    ];

    var index = 0;
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(AppConfig.mockScanDeviceInterval, (timer) {
      if (index >= catalogue.length) {
        timer.cancel();
        return;
      }
      final (name, id, rssi) = catalogue[index++];
      found.add(
        DiscoveredVehicle(
          id: id,
          name: name,
          rssi: rssi + _random.nextInt(6) - 3,
          lastSeen: DateTime.now(),
        ),
      );
      if (!controller.isClosed) controller.add(List.unmodifiable(found));
    });

    controller.onCancel = stopScan;

    final limit = timeout ?? AppConfig.scanTimeout;
    Timer(limit, () {
      if (identical(_scanController, controller)) stopScan();
    });

    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    final controller = _scanController;
    _scanController = null;
    if (controller != null && !controller.isClosed) await controller.close();
    if (_status == TransportStatus.scanning) {
      _setStatus(
        _deviceId == null ? TransportStatus.idle : TransportStatus.connected,
      );
    }
  }

  @override
  Future<void> connect({String? deviceId}) async {
    _setStatus(TransportStatus.connecting);
    await Future<void>.delayed(AppConfig.mockConnectDelay);

    if (_fault == MockFault.dropout) {
      _setStatus(TransportStatus.failed);
      throw const TransportException(TransportFailure.connectionFailed);
    }

    _deviceId = deviceId ?? 'mock-rover-01';
    _vehicleState = VehicleState.idle;
    _setStatus(TransportStatus.connected);
    _startTelemetry();
  }

  @override
  Future<void> disconnect() async {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _leftMotor = 0;
    _rightMotor = 0;
    _deviceId = null;
    _vehicleState = VehicleState.idle;
    _setStatus(TransportStatus.disconnected);
  }

  @override
  Future<void> send(String command) async {
    if (_status != TransportStatus.connected) {
      throw const TransportException(TransportFailure.writeFailed);
    }
    // Radio latency, so throttling and ACK handling are exercised realistically.
    await Future<void>.delayed(const Duration(milliseconds: 8));
    _handleCommand(command.trim());
  }

  @override
  Stream<String> subscribe() => _inboundController.stream;

  @override
  Future<int?> readRssi() async {
    if (_status != TransportStatus.connected) return null;
    return -52 + _random.nextInt(14);
  }

  @override
  Future<void> dispose() async {
    _telemetryTimer?.cancel();
    _scanTimer?.cancel();
    await _scanController?.close();
    await _statusController.close();
    await _inboundController.close();
  }

  // --- Simulation internals -------------------------------------------------

  void _setStatus(TransportStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _emit(String frame) {
    if (!_inboundController.isClosed) _inboundController.add(frame);
  }

  void _ack(String verb) =>
      _emit('${Wire.prefixAck}${Wire.keyValueSeparator}$verb');

  void _dropLink() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _deviceId = null;
    _leftMotor = 0;
    _rightMotor = 0;
    _setStatus(TransportStatus.disconnected);
  }

  void _handleCommand(String frame) {
    final parts = frame.split(Wire.fieldSeparator);
    final head = parts.first.split(Wire.keyValueSeparator);
    if (head.length != 2 || head[0] != Wire.prefixCommand) return;

    final verb = head[1];
    final fields = <String, String>{};
    for (final segment in parts.skip(1)) {
      final index = segment.indexOf(Wire.keyValueSeparator);
      if (index <= 0) continue;
      fields[segment.substring(0, index)] = segment.substring(index + 1);
    }

    switch (verb) {
      case Wire.verbDrive:
        final left = int.tryParse(fields[Wire.keyLeft] ?? '') ?? 0;
        final right = int.tryParse(fields[Wire.keyRight] ?? '') ?? 0;
        if (_fault == MockFault.motorFault) {
          _emit(
            '${Wire.prefixError}${Wire.fieldSeparator}'
            '${Wire.keyErrorCode}${Wire.keyValueSeparator}${RoverErrorCode.motorFault.code}',
          );
          return;
        }
        _leftMotor = clampMotor(left);
        _rightMotor = clampMotor(right);
        _lastDriveAt = DateTime.now();
        _vehicleState = (_leftMotor == 0 && _rightMotor == 0)
            ? VehicleState.stopped
            : VehicleState.driving;
        _ack(Wire.verbDrive);

      case Wire.verbStop:
        _leftMotor = 0;
        _rightMotor = 0;
        _vehicleState = VehicleState.stopped;
        _decision = null;
        _ack(Wire.verbStop);

      case Wire.verbSpeed:
        _speedCeiling = clampPercent(
          int.tryParse(fields[Wire.keyValue] ?? '') ?? 70,
        );
        _ack(Wire.verbSpeed);

      case Wire.verbLight:
        _lightMode = LightMode.tryParse(fields[Wire.keyMode]) ?? _lightMode;
        _ack(Wire.verbLight);

      case Wire.verbServo:
        _servoAngle = clampInt(
          int.tryParse(fields[Wire.keyAngle] ?? '') ?? 90,
          0,
          180,
        );
        _ack(Wire.verbServo);

      case Wire.verbMode:
        _driveMode =
            DriveMode.tryParse(fields[Wire.keyModeValue]) ?? _driveMode;
        _vehicleState = _driveMode.isAutonomous
            ? VehicleState.avoiding
            : VehicleState.idle;
        if (!_driveMode.isAutonomous) {
          _leftMotor = 0;
          _rightMotor = 0;
          _decision = null;
        }
        _ack(Wire.verbMode);

      case Wire.verbScan:
        _scanMode = ScanMode.tryParse(fields[Wire.keyMode]) ?? ScanMode.off;
        if (_scanMode != ScanMode.off) _vehicleState = VehicleState.scanning;
        _ack(Wire.verbScan);

      case Wire.verbConfig:
        final timeout = int.tryParse(fields[Wire.keyTimeout] ?? '');
        if (timeout != null) _commandTimeout = Duration(milliseconds: timeout);
        _ack(Wire.verbConfig);

      case Wire.verbTestMotor:
        final percent = int.tryParse(fields[Wire.keyValue] ?? '') ?? 40;
        final target = fields[Wire.keyTarget];
        _leftMotor = target == Wire.targetRight ? 0 : clampPercent(percent);
        _rightMotor = target == Wire.targetLeft ? 0 : clampPercent(percent);
        _lastDriveAt = DateTime.now();
        _vehicleState = VehicleState.driving;
        _ack(Wire.verbTestMotor);

      case Wire.verbCalibrate:
        _ack(Wire.verbCalibrate);

      case Wire.verbPing:
        _ack(Wire.verbPing);
    }
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(
      AppConfig.mockTelemetryInterval,
      (_) => _tick(),
    );
  }

  void _tick() {
    if (_status != TransportStatus.connected) return;
    _applyWatchdog();
    _advanceSimulation();
    _emit(_buildTelemetryFrame());
  }

  /// Mirrors the ESP32 watchdog: motors cut if drive commands stop arriving.
  /// This is what makes "let go of the joystick and the car stops" verifiable
  /// in mock mode.
  void _applyWatchdog() {
    if (_leftMotor == 0 && _rightMotor == 0) return;
    if (_driveMode.isAutonomous) return;
    if (DateTime.now().difference(_lastDriveAt) <= _commandTimeout) return;

    _leftMotor = 0;
    _rightMotor = 0;
    _vehicleState = VehicleState.stopped;
    _emit(
      '${Wire.prefixError}${Wire.fieldSeparator}'
      '${Wire.keyErrorCode}${Wire.keyValueSeparator}${RoverErrorCode.watchdogStop.code}',
    );
  }

  void _advanceSimulation() {
    final effort = (_leftMotor.abs() + _rightMotor.abs()) / 200;

    // Idle draw plus a load term, so the pack visibly sags while driving.
    _battery = math.max(0, _battery - (0.004 + effort * 0.05));

    if (_driveMode.isAutonomous) {
      _runAutonomousStep();
    } else if (_scanMode != ScanMode.off) {
      _runScanStep();
    }

    // Forward motion closes on an obstacle; reversing and turning open it up.
    final forward = (_leftMotor + _rightMotor) / 2;
    _distanceCm = clampDouble(
      _distanceCm - forward * 0.06 + (_random.nextDouble() - 0.45) * 2,
      6,
      320,
    );
  }

  void _runScanStep() {
    _servoAngle = clampInt(_servoAngle + 6 * _sweepDirection, 0, 180);
    if (_servoAngle <= 0 || _servoAngle >= 180) {
      _sweepDirection = -_sweepDirection;
      if (_scanMode == ScanMode.once && _servoAngle >= 180) {
        _scanMode = ScanMode.off;
        _vehicleState = VehicleState.idle;
      }
    }
  }

  void _runAutonomousStep() {
    _runScanStep();

    if (_distanceCm < AppConfig.defaultDangerDistanceCm) {
      // Firmware-side decision: back off and turn toward the open side.
      _decision = _servoAngle < 90 ? 'TURN RIGHT' : 'TURN LEFT';
      _leftMotor = _servoAngle < 90 ? 55 : -55;
      _rightMotor = _servoAngle < 90 ? -55 : 55;
      _vehicleState = VehicleState.avoiding;
      _distanceCm += 4;
    } else {
      _decision = 'PATH CLEAR';
      final cruise = (_speedCeiling * 0.7).round();
      _leftMotor = cruise;
      _rightMotor = cruise;
      _vehicleState = VehicleState.driving;
    }
    _lastDriveAt = DateTime.now();
  }

  String _buildTelemetryFrame() {
    final speed = ((_leftMotor.abs() + _rightMotor.abs()) / 2).round();
    final buffer = StringBuffer(Wire.prefixData);

    void field(String key, Object value) => buffer
      ..write(Wire.fieldSeparator)
      ..write(key)
      ..write(Wire.keyValueSeparator)
      ..write(value);

    field(Wire.keyBattery, _battery.round());
    // A failed sensor reports an out-of-range value, exactly as a real HC-SR04
    // does when it never hears an echo.
    field(
      Wire.keyDistance,
      _fault == MockFault.sensorFailure ? 0 : _distanceCm.round(),
    );
    field(Wire.keyServo, _servoAngle);
    field(Wire.keySpeed, speed);
    field(Wire.keyLeft, _leftMotor);
    field(Wire.keyRight, _rightMotor);
    field(Wire.keyMode, _driveMode.wire);
    field(Wire.keyLight, _lightMode.wire);
    field(Wire.keyState, _vehicleState.wire);
    field(Wire.keySignal, 88 + _random.nextInt(10));
    if (_decision != null) field(Wire.keyDecision, _decision!);

    return buffer.toString();
  }
}
