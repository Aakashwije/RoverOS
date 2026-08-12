import '../core/constants/command_constants.dart';

/// Headlight behaviour. Flash *timing* is owned by the ESP32 — the app only
/// ever names a mode, never toggles the LED itself.
enum LightMode {
  off(Wire.lightOff, 'OFF'),
  on(Wire.lightOn, 'ON'),
  flashSlow(Wire.lightFlashSlow, 'SLOW FLASH'),
  flashFast(Wire.lightFlashFast, 'FAST FLASH'),
  hazard(Wire.lightHazard, 'HAZARD');

  const LightMode(this.wire, this.label);

  final String wire;
  final String label;

  bool get isFlashing =>
      this == flashSlow || this == flashFast || this == hazard;

  bool get isEmitting => this != off;

  static LightMode? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    for (final mode in values) {
      if (mode.wire == normalized) return mode;
    }
    return null;
  }
}

/// Turn-signal behaviour. The OP0148 board exposes one signal output per side:
/// left drives both front-left and rear-left lamps, right drives both
/// front-right and rear-right lamps.
enum SignalMode {
  off(Wire.signalOff, 'OFF'),
  left(Wire.signalLeft, 'LEFT'),
  right(Wire.signalRight, 'RIGHT'),
  hazard(Wire.signalHazard, 'HAZARD');

  const SignalMode(this.wire, this.label);

  final String wire;
  final String label;

  bool get isEmitting => this != off;

  static SignalMode? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    for (final mode in values) {
      if (mode.wire == normalized) return mode;
    }
    return null;
  }
}

/// Who is driving: the operator, or the vehicle's own logic.
///
/// Autonomous decisions are made on the ESP32. These values only select which
/// behaviour the firmware runs and let the UI describe it.
enum DriveMode {
  manual(Wire.modeManual, 'MANUAL', 'You are driving'),
  obstacleAvoidance(
    Wire.modeAvoid,
    'OBSTACLE AVOIDANCE',
    'Vehicle avoids obstacles on its own',
  ),
  autoScan(
    Wire.modeScan,
    'AUTO SCAN',
    'Vehicle sweeps the servo and maps distances',
  );

  const DriveMode(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  bool get isAutonomous => this != manual;

  static DriveMode? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    if (normalized == Wire.modeAutoLegacy) return obstacleAvoidance;
    for (final mode in values) {
      if (mode.wire == normalized) return mode;
    }
    return null;
  }
}

/// Servo sweep behaviour requested from the firmware.
enum ScanMode {
  off(Wire.scanOff, 'OFF'),
  once(Wire.scanOnce, 'SINGLE SWEEP'),
  auto(Wire.scanAuto, 'CONTINUOUS');

  const ScanMode(this.wire, this.label);

  final String wire;
  final String label;

  static ScanMode? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    for (final mode in values) {
      if (mode.wire == normalized) return mode;
    }
    return null;
  }
}

/// What the vehicle reports it is currently doing.
enum VehicleState {
  idle(Wire.stateIdle, 'IDLE'),
  driving(Wire.stateDriving, 'DRIVING'),
  stopped(Wire.stateStopped, 'STOPPED'),
  avoiding(Wire.stateAvoiding, 'AVOIDING'),
  scanning(Wire.stateScanning, 'SCANNING'),
  fault(Wire.stateFault, 'FAULT');

  const VehicleState(this.wire, this.label);

  final String wire;
  final String label;

  static VehicleState? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    for (final state in values) {
      if (state.wire == normalized) return state;
    }
    return null;
  }
}

/// Which motor a bench test or calibration applies to.
enum MotorTarget {
  left(Wire.targetLeft, 'LEFT MOTOR'),
  right(Wire.targetRight, 'RIGHT MOTOR'),
  both(Wire.targetBoth, 'BOTH MOTORS');

  const MotorTarget(this.wire, this.label);

  final String wire;
  final String label;
}

/// Speed ceiling presets offered on the drive HUD.
enum SpeedPreset {
  eco('ECO', 40),
  normal('NORMAL', 70),
  sport('SPORT', 100),
  custom('CUSTOM', -1);

  const SpeedPreset(this.label, this.percent);

  final String label;

  /// `-1` for [custom], whose value comes from the slider instead.
  final int percent;

  static SpeedPreset forPercent(int value) {
    for (final preset in values) {
      if (preset != custom && preset.percent == value) return preset;
    }
    return custom;
  }

  static List<SpeedPreset> get selectable => const [eco, normal, sport];
}

/// A serialised, validated frame ready to hand to a transport.
///
/// Commands are built through `services/car_protocol.dart` so a widget can
/// never hand a hand-rolled string to the radio.
class CarCommand {
  const CarCommand({
    required this.verb,
    required this.frame,
    this.isCritical = false,
  });

  /// The verb this frame carries, e.g. `DRIVE`. Used for ACK matching.
  final String verb;

  /// The full wire frame including its terminator.
  final String frame;

  /// Critical frames (STOP) are retried and are never dropped by throttling.
  final bool isCritical;

  /// Frame without the trailing terminator — for logs and tests.
  String get readable => frame.trim();

  @override
  String toString() => 'CarCommand($readable)';

  @override
  bool operator ==(Object other) =>
      other is CarCommand && other.frame == frame && other.verb == verb;

  @override
  int get hashCode => Object.hash(verb, frame);
}

/// An `ACK:<VERB>` frame from the vehicle.
class CommandAck {
  const CommandAck({required this.verb, required this.receivedAt});

  final String verb;
  final DateTime receivedAt;

  @override
  String toString() => 'ACK:$verb';
}

/// An `ERROR;CODE:..;MSG:..` frame from the vehicle.
class RoverError {
  const RoverError({
    required this.code,
    required this.message,
    required this.receivedAt,
  });

  final RoverErrorCode code;

  /// Firmware-supplied text when present, otherwise [RoverErrorCode.message].
  final String message;

  final DateTime receivedAt;

  /// Errors that must stop autonomous operation rather than merely warn.
  bool get isFailSafe =>
      code == RoverErrorCode.sensorFail ||
      code == RoverErrorCode.servoFail ||
      code == RoverErrorCode.motorFault ||
      code == RoverErrorCode.overCurrent;

  @override
  String toString() => 'RoverError(${code.name}: $message)';
}
