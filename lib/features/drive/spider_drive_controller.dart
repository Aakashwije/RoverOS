import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../models/commands.dart';
import '../../models/vehicle.dart';
import '../../services/car_protocol.dart';
import '../../services/spider_commands.dart';
import '../../services/transport/transport.dart';
import '../connection/connection_controller.dart';
import 'drive_controller.dart' show DriveArmState;

/// What the app is currently commanding the spiderbot to do.
///
/// A held direction button, not a stick position: a fixed-gait quadruped
/// steps in one of a small number of shapes, so there is nothing to ramp the
/// way [MotorOutput][../../core/utils/motor_math.dart] is for the car.
class SpiderDriveState {
  const SpiderDriveState({
    this.direction,
    this.speedPercent = 60,
    this.isEmergencyStopped = false,
  });

  /// Non-null while a direction button is held.
  final WalkDirection? direction;

  /// Commanded gait speed, 0-100.
  final int speedPercent;

  /// Latched by the emergency stop; cleared only by an explicit reset.
  final bool isEmergencyStopped;

  bool get isMoving => direction != null;

  DriveArmState get armState {
    if (isEmergencyStopped) return DriveArmState.stopped;
    if (isMoving) return DriveArmState.armed;
    return DriveArmState.ready;
  }

  /// `clearDirection: true` sets [direction] to null — a plain `direction:
  /// null` argument would be indistinguishable from "leave it unchanged".
  SpiderDriveState copyWith({
    WalkDirection? direction,
    bool clearDirection = false,
    int? speedPercent,
    bool? isEmergencyStopped,
  }) {
    return SpiderDriveState(
      direction: clearDirection ? null : (direction ?? this.direction),
      speedPercent: speedPercent ?? this.speedPercent,
      isEmergencyStopped: isEmergencyStopped ?? this.isEmergencyStopped,
    );
  }
}

/// Turns direction-pad input into `CMD:WALK`/`CMD:STOP` frames.
///
/// Deliberately smaller than [DriveController][drive_controller.dart]: there
/// is no ramping or differential math, just "is a direction held" paced onto
/// the wire at the same cadence the car uses, so the firmware watchdog sees
/// regular traffic for as long as a button stays down.
class SpiderDriveController extends Notifier<SpiderDriveState> {
  Timer? _ticker;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  SpiderDriveState build() {
    // A dropped link must not leave a stale WALK command believed to be in
    // effect.
    ref.listen(connectionProvider, (previous, next) {
      if (previous?.isConnected == true && !next.isConnected) _onLinkLost();
    });

    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
    });

    return const SpiderDriveState();
  }

  Transport get _transport => ref.read(transportProvider);

  bool get _isConnected => ref.read(connectionProvider).isConnected;

  /// A direction button was pressed (or an already-held one changed).
  void press(WalkDirection direction) {
    if (state.isEmergencyStopped) return;

    state = state.copyWith(direction: direction);
    _sendWalk();
    _ticker ??= Timer.periodic(AppConfig.driveCommandInterval, (_) => _tick());
  }

  /// The direction button was released: stop immediately rather than waiting
  /// for the next tick, the same release-to-stop safety path the car uses.
  void release() {
    _ticker?.cancel();
    _ticker = null;
    if (state.direction == null) return;

    state = state.copyWith(clearDirection: true);
    _sendStop(reason: 'Direction released');
  }

  /// Unconditional stop, regardless of whether a direction is currently held
  /// — used on screen exit and app backgrounding, where "was anything held"
  /// is not a safe thing to trust. Preserves the emergency latch: a plain
  /// stop must never be what quietly clears it.
  Future<void> stop({String reason = 'Stop requested'}) async {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(clearDirection: true);
    await _sendStop(reason: reason);
  }

  void setSpeed(int percent) {
    final clamped = percent.clamp(0, 100);
    if (clamped == state.speedPercent) return;

    state = state.copyWith(speedPercent: clamped);
    // A held direction should feel the new speed without waiting for the
    // next tick.
    if (state.direction != null) _sendWalk();
  }

  /// Emergency stop. Latches the UI until [clearEmergencyStop] is called.
  Future<void> emergencyStop() async {
    _ticker?.cancel();
    _ticker = null;

    state = state.copyWith(clearDirection: true, isEmergencyStopped: true);

    await _sendStop(
      reason: 'Emergency stop',
      retries: AppConfig.stopCommandRetries,
    );

    ref
        .read(activityLogProvider.notifier)
        .record(
          'Emergency stop',
          detail: 'Spiderbot commanded to halt',
          severity: ActivitySeverity.warning,
        );
  }

  void clearEmergencyStop() {
    if (!state.isEmergencyStopped) return;
    state = state.copyWith(isEmergencyStopped: false);
  }

  void _tick() {
    if (!_isConnected || state.direction == null) return;
    if (DateTime.now().difference(_lastSentAt) < AppConfig.driveKeepAlive) {
      return;
    }
    _sendWalk();
  }

  void _sendWalk() {
    final direction = state.direction;
    if (direction == null) return;
    _send(
      SpiderCommands.buildWalkCommand(
        direction: direction,
        speedPercent: state.speedPercent,
      ),
    );
  }

  /// Sends STOP, retrying on transport failure — the same policy
  /// [DriveController][drive_controller.dart] applies, and the same reason:
  /// the vehicle's own watchdog is the real backstop, but the app should
  /// still try hard.
  Future<void> _sendStop({required String reason, int retries = 1}) async {
    _lastSentAt = DateTime.now();
    if (!_isConnected) return;

    final command = CarProtocol.buildStopCommand();
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        await _transport.send(command.frame);
        return;
      } on TransportException catch (error) {
        debugPrint(
          'ROVEROS: spider STOP attempt ${attempt + 1} failed ($reason): $error',
        );
      }
    }
  }

  void _onLinkLost() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(clearDirection: true);
  }

  void _send(CarCommand command) {
    if (!_isConnected) return;

    if (!CarProtocol.validateCommand(command.frame)) {
      debugPrint('ROVEROS: refused invalid frame ${command.readable}');
      return;
    }

    _lastSentAt = DateTime.now();
    _transport.send(command.frame).catchError((Object error) {
      debugPrint('ROVEROS: send failed for ${command.readable}: $error');
    });
  }
}

final spiderDriveProvider =
    NotifierProvider<SpiderDriveController, SpiderDriveState>(
      SpiderDriveController.new,
    );
