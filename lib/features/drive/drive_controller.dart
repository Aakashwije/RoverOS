import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/motor_math.dart';
import '../../models/commands.dart';
import '../../models/vehicle.dart';
import '../../services/car_protocol.dart';
import '../../services/transport/transport.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';

/// What the app is currently commanding.
///
/// Kept separate from [Telemetry], which is what the vehicle *reports*. Holding
/// them apart is what stops the UI showing an intended state as if it were a
/// confirmed one.
class DriveState {
  const DriveState({
    this.output = MotorOutput.stopped,
    this.speedPercent = 70,
    this.lightMode = LightMode.off,
    this.driveMode = DriveMode.manual,
    this.scanMode = ScanMode.off,
    this.isEmergencyStopped = false,
    this.isEngaged = false,
    this.lastCommandAt,
  });

  final MotorOutput output;

  /// Commanded speed ceiling, 0–100.
  final int speedPercent;

  final LightMode lightMode;
  final DriveMode driveMode;
  final ScanMode scanMode;

  /// Latched by the emergency stop; cleared only by an explicit reset.
  final bool isEmergencyStopped;

  /// True while the user is actually touching the joystick.
  final bool isEngaged;

  final DateTime? lastCommandAt;

  DriveDirection get direction => MotorMath.directionOf(output);

  bool get isMoving => !output.isStopped;

  /// Whether drive input should be accepted at all.
  bool get acceptsInput => !isEmergencyStopped && !driveMode.isAutonomous;

  DriveState copyWith({
    MotorOutput? output,
    int? speedPercent,
    LightMode? lightMode,
    DriveMode? driveMode,
    ScanMode? scanMode,
    bool? isEmergencyStopped,
    bool? isEngaged,
    DateTime? lastCommandAt,
  }) {
    return DriveState(
      output: output ?? this.output,
      speedPercent: speedPercent ?? this.speedPercent,
      lightMode: lightMode ?? this.lightMode,
      driveMode: driveMode ?? this.driveMode,
      scanMode: scanMode ?? this.scanMode,
      isEmergencyStopped: isEmergencyStopped ?? this.isEmergencyStopped,
      isEngaged: isEngaged ?? this.isEngaged,
      lastCommandAt: lastCommandAt ?? this.lastCommandAt,
    );
  }
}

/// Turns user intent into vehicle commands.
///
/// Every outgoing frame in the app passes through here, which is what makes the
/// safety rules enforceable in one place:
///
/// * drive commands are paced, never sent per animation frame;
/// * STOP bypasses pacing, retries on failure, and is idempotent;
/// * a disconnected link cannot leave a stale non-zero output latched;
/// * the phone never decides anything autonomous — it only selects a mode.
class DriveController extends Notifier<DriveState> {
  Timer? _driveTicker;

  /// Last output actually transmitted, for change detection.
  MotorOutput _lastSent = MotorOutput.stopped;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Target set by the joystick, read by the ticker.
  MotorOutput _target = MotorOutput.stopped;

  /// Actual commanded output, ramping toward [_target] one tick at a time.
  /// Kept as doubles so a slow ramp rate doesn't get truncated to zero change
  /// by premature rounding.
  double _rampedLeft = 0;
  double _rampedRight = 0;
  DateTime _lastTickAt = DateTime.now();

  /// Raw stick position behind [_target], kept so a mid-drive speed-cap change
  /// can re-derive the target without waiting for the next stick movement.
  double _lastStickX = 0;
  double _lastStickY = 0;

  @override
  DriveState build() {
    final settings = ref.read(settingsProvider);

    // A dropped link must not leave a stale command latched in the UI.
    ref.listen(connectionProvider, (previous, next) {
      if (previous?.isConnected == true && !next.isConnected) _onLinkLost();
    });

    ref.onDispose(() {
      _driveTicker?.cancel();
      _driveTicker = null;
    });

    return DriveState(
      speedPercent: settings.maxSpeedPercent,
      driveMode: settings.defaultDriveMode,
      lightMode: settings.defaultLightMode,
    );
  }

  Transport get _transport => ref.read(transportProvider);

  bool get _isConnected => ref.read(connectionProvider).isConnected;

  // --- Joystick input -------------------------------------------------------

  /// Accepts a normalised stick position. Cheap enough to call every frame: it
  /// only updates the target. The ticker owns [DriveState.output], ramping it
  /// toward this target at the configured accel/decel rate and deciding what
  /// actually gets transmitted.
  void updateJoystick({required double x, required double y}) {
    if (!state.acceptsInput) return;

    _lastStickX = x;
    _lastStickY = y;

    final settings = ref.read(settingsProvider);
    _target = MotorMath.fromJoystick(x: x, y: y, settings: settings);

    if (!state.isEngaged) state = state.copyWith(isEngaged: true);
    _ensureTicker();
  }

  /// Re-derives [_target] from the last known stick position under the
  /// current settings, so a mid-drive speed-cap change takes effect without
  /// waiting for the next touch event.
  void _recomputeTargetFromLastStick() {
    if (!state.isEngaged) return;
    final settings = ref.read(settingsProvider);
    _target = MotorMath.fromJoystick(
      x: _lastStickX,
      y: _lastStickY,
      settings: settings,
    );
  }

  /// Stick released: command a stop straight away rather than waiting for the
  /// next tick or relying on the firmware watchdog. This bypasses the ramp
  /// deliberately — release-to-stop is a safety path, not a driving feel.
  void releaseJoystick() {
    _target = MotorOutput.stopped;
    _resetRamp();
    state = state.copyWith(output: MotorOutput.stopped, isEngaged: false);
    _sendStop(reason: 'Joystick released');
  }

  void _resetRamp() {
    _rampedLeft = 0;
    _rampedRight = 0;
  }

  void _ensureTicker() {
    _lastTickAt = DateTime.now();
    _driveTicker ??= Timer.periodic(
      AppConfig.driveCommandInterval,
      (_) => _tick(),
    );
  }

  /// Paced transmit loop.
  ///
  /// Each tick moves the actually-commanded output toward [_target] at the
  /// configured accel/decel rate, then sends only when that ramped value has
  /// meaningfully changed or the keep-alive window has elapsed, so a held
  /// position still feeds the firmware watchdog.
  void _tick() {
    if (!_isConnected) return;

    final now = DateTime.now();
    final elapsedSeconds = now.difference(_lastTickAt).inMicroseconds / 1e6;
    _lastTickAt = now;

    final settings = ref.read(settingsProvider);
    _rampedLeft = MotorMath.rampToward(
      current: _rampedLeft,
      target: _target.left.toDouble(),
      elapsedSeconds: elapsedSeconds,
      settings: settings,
    );
    _rampedRight = MotorMath.rampToward(
      current: _rampedRight,
      target: _target.right.toDouble(),
      elapsedSeconds: elapsedSeconds,
      settings: settings,
    );

    final ramped = MotorOutput(_rampedLeft.round(), _rampedRight.round());
    if (state.output != ramped) state = state.copyWith(output: ramped);

    final stillRamping =
        _rampedLeft != _target.left || _rampedRight != _target.right;
    if (_target.isStopped && ramped.isStopped && !stillRamping) {
      // Nothing left to hold: let the ticker idle rather than emitting zeroes.
      _driveTicker?.cancel();
      _driveTicker = null;
      return;
    }

    final sinceLastSend = now.difference(_lastSentAt);
    final changed = !MotorMath.isWithinEpsilon(
      ramped,
      _lastSent,
      AppConfig.driveCommandEpsilon,
    );

    if (!changed && sinceLastSend < AppConfig.driveKeepAlive) return;

    _send(
      CarProtocol.buildDriveCommand(left: ramped.left, right: ramped.right),
    );
    _lastSent = ramped;
    _lastSentAt = now;
  }

  // --- Stop paths -----------------------------------------------------------

  /// Ordinary stop: zero the output and tell the vehicle immediately.
  Future<void> stop({String reason = 'Stop requested'}) async {
    _target = MotorOutput.stopped;
    _resetRamp();
    state = state.copyWith(output: MotorOutput.stopped, isEngaged: false);
    await _sendStop(reason: reason);
  }

  /// Emergency stop.
  ///
  /// Latches the UI into a stopped state that survives until the user clears
  /// it, so a twitching thumb cannot immediately re-engage the motors.
  Future<void> emergencyStop() async {
    _target = MotorOutput.stopped;
    _resetRamp();
    _driveTicker?.cancel();
    _driveTicker = null;

    state = state.copyWith(
      output: MotorOutput.stopped,
      isEngaged: false,
      isEmergencyStopped: true,
    );

    await _sendStop(
      reason: 'Emergency stop',
      retries: AppConfig.stopCommandRetries,
    );

    ref
        .read(activityLogProvider.notifier)
        .record(
          'Emergency stop',
          detail: 'Motors commanded to zero',
          severity: ActivitySeverity.warning,
        );
  }

  /// Clears the emergency latch. Requires the user to act deliberately.
  void clearEmergencyStop() {
    if (!state.isEmergencyStopped) return;
    state = state.copyWith(isEmergencyStopped: false);
  }

  /// Sends STOP, retrying on transport failure.
  ///
  /// A failed STOP is not fatal on its own — the ESP32 watchdog cuts the motors
  /// when commands stop arriving — but the app should still try hard.
  Future<void> _sendStop({required String reason, int retries = 1}) async {
    _lastSent = MotorOutput.stopped;
    _lastSentAt = DateTime.now();

    if (!_isConnected) return;

    final command = CarProtocol.buildStopCommand();
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        await _transport.send(command.frame);
        return;
      } on TransportException catch (error) {
        debugPrint(
          'ROVEROS: STOP attempt ${attempt + 1} failed ($reason): $error',
        );
      }
    }
  }

  void _onLinkLost() {
    _driveTicker?.cancel();
    _driveTicker = null;
    _target = MotorOutput.stopped;
    _lastSent = MotorOutput.stopped;
    _resetRamp();
    state = state.copyWith(output: MotorOutput.stopped, isEngaged: false);
  }

  // --- Vehicle configuration -----------------------------------------------

  /// Sets the speed ceiling. Also re-derives the current output so an active
  /// stick immediately respects the new limit.
  void setSpeed(int percent) {
    final clamped = percent.clamp(0, 100);
    if (clamped == state.speedPercent) return;

    state = state.copyWith(speedPercent: clamped);
    _recomputeTargetFromLastStick();
    _send(CarProtocol.buildSpeedCommand(clamped));
  }

  void setLightMode(LightMode mode) {
    if (mode == state.lightMode) return;
    state = state.copyWith(lightMode: mode);
    // One frame names the mode; the ESP32 owns all flash timing from here.
    _send(CarProtocol.buildLightCommand(mode));
  }

  void setServoAngle(int angle) => _send(CarProtocol.buildServoCommand(angle));

  void setScanMode(ScanMode mode) {
    if (mode == state.scanMode) return;
    state = state.copyWith(scanMode: mode);
    _send(CarProtocol.buildScanCommand(mode));
  }

  /// Hands control to firmware behaviour, or takes it back.
  ///
  /// Entering an autonomous mode always stops first, so the vehicle never
  /// carries a manual output into autonomous control.
  Future<void> setDriveMode(DriveMode mode) async {
    if (mode == state.driveMode) return;

    await stop(reason: 'Mode change');
    state = state.copyWith(driveMode: mode, scanMode: ScanMode.off);
    _send(CarProtocol.buildModeCommand(mode));

    ref
        .read(activityLogProvider.notifier)
        .record('Mode set to ${mode.label}', detail: mode.description);
  }

  void testMotor(MotorTarget target, {int percent = 40}) =>
      _send(CarProtocol.buildMotorTestCommand(target, percent: percent));

  /// Pushes motor and servo calibration to the vehicle.
  void pushCalibration() {
    final settings = ref.read(settingsProvider);
    _send(
      CarProtocol.buildCalibrationCommand(
        invertLeft: settings.invertLeftMotor,
        invertRight: settings.invertRightMotor,
        trimLeft: settings.leftMotorTrim,
        trimRight: settings.rightMotorTrim,
        servoCenter: settings.servoCenter,
        servoMin: settings.servoMinAngle,
        servoMax: settings.servoMaxAngle,
      ),
    );
  }

  /// Single send path. Validates before transmitting so a malformed frame is
  /// caught here rather than being misread by the firmware.
  void _send(CarCommand command) {
    if (!_isConnected) return;

    if (!CarProtocol.validateCommand(command.frame)) {
      debugPrint('ROVEROS: refused invalid frame ${command.readable}');
      return;
    }

    state = state.copyWith(lastCommandAt: DateTime.now());
    _transport.send(command.frame).catchError((Object error) {
      debugPrint('ROVEROS: send failed for ${command.readable}: $error');
    });
  }
}

final driveProvider = NotifierProvider<DriveController, DriveState>(
  DriveController.new,
);
