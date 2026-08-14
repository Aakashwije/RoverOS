import '../core/constants/command_constants.dart';
import '../core/utils/clamp.dart';
import '../models/commands.dart';

/// Which way the spiderbot's gait should carry it.
///
/// Discrete directions, not an analog stick: a fixed quadruped gait steps in
/// one of a small number of shapes at a time, so there is no "70% left" the
/// way there is for a differential-drive car.
enum WalkDirection {
  forward(Wire.dirForward, 'FORWARD'),
  back(Wire.dirBack, 'BACK'),
  left(Wire.dirLeft, 'LEFT'),
  right(Wire.dirRight, 'RIGHT'),
  rotateLeft(Wire.dirRotateLeft, 'ROTATE LEFT'),
  rotateRight(Wire.dirRotateRight, 'ROTATE RIGHT');

  const WalkDirection(this.wire, this.label);

  final String wire;
  final String label;
}

/// Builds the one outbound verb the spiderbot adds to the shared wire
/// protocol. Everything else it needs — `CMD:STOP`, `CMD:PING`,
/// `CMD:CONFIG` — is already generic and comes straight from
/// [CarProtocol][../services/car_protocol.dart], unchanged.
abstract final class SpiderCommands {
  /// `CMD:WALK;DIR:<direction>;V:<percent>`.
  static CarCommand buildWalkCommand({
    required WalkDirection direction,
    int speedPercent = 60,
  }) {
    final buffer = StringBuffer()
      ..write(Wire.prefixCommand)
      ..write(Wire.keyValueSeparator)
      ..write(Wire.verbWalk)
      ..write(Wire.fieldSeparator)
      ..write(Wire.keyDirection)
      ..write(Wire.keyValueSeparator)
      ..write(direction.wire)
      ..write(Wire.fieldSeparator)
      ..write(Wire.keyValue)
      ..write(Wire.keyValueSeparator)
      ..write(clampPercent(speedPercent))
      ..write(Wire.terminator);

    return CarCommand(verb: Wire.verbWalk, frame: buffer.toString());
  }
}
