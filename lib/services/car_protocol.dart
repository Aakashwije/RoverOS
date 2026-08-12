import '../core/constants/app_config.dart';
import '../core/constants/command_constants.dart';
import '../core/utils/clamp.dart';
import '../models/commands.dart';
import '../models/telemetry.dart';

/// Result of parsing one inbound frame.
sealed class RoverFrame {
  const RoverFrame(this.raw);

  final String raw;
}

class TelemetryFrame extends RoverFrame {
  const TelemetryFrame(super.raw, this.telemetry);

  final Telemetry telemetry;
}

class AckFrame extends RoverFrame {
  const AckFrame(super.raw, this.ack);

  final CommandAck ack;
}

class ErrorFrame extends RoverFrame {
  const ErrorFrame(super.raw, this.error);

  final RoverError error;
}

/// A frame that did not match the grammar. Surfaced rather than swallowed so a
/// firmware mismatch is visible during bring-up instead of silently ignored.
class UnknownFrame extends RoverFrame {
  const UnknownFrame(super.raw, this.reason);

  final String reason;
}

/// Serialises outgoing commands and parses inbound frames.
///
/// This is the only place in the app that builds or interprets protocol text.
/// Widgets call the `build*` helpers and receive a validated [CarCommand].
abstract final class CarProtocol {
  // --- Outgoing -------------------------------------------------------------

  /// `CMD:DRIVE;L:<left>;R:<right>` with both outputs clamped to ±100.
  static CarCommand buildDriveCommand({required int left, required int right}) {
    return _command(Wire.verbDrive, {
      Wire.keyLeft: clampMotor(left),
      Wire.keyRight: clampMotor(right),
    });
  }

  /// `CMD:STOP` — marked critical so throttling and retry logic never drop it.
  static CarCommand buildStopCommand() =>
      _command(Wire.verbStop, const {}, isCritical: true);

  /// `CMD:SPEED;V:<percent>` — the ceiling the firmware applies to drive output.
  static CarCommand buildSpeedCommand(int percent) =>
      _command(Wire.verbSpeed, {Wire.keyValue: clampPercent(percent)});

  /// `CMD:LIGHT;MODE:<mode>`.
  ///
  /// Flash timing lives on the ESP32; the app names a mode exactly once and
  /// never toggles the LED itself.
  static CarCommand buildLightCommand(LightMode mode, {int? brightness}) {
    return _command(Wire.verbLight, {
      Wire.keyMode: mode.wire,
      if (brightness != null) Wire.keyBrightness: clampPercent(brightness),
    });
  }

  /// `CMD:SIGNAL;MODE:<mode>`.
  ///
  /// The OP0148 has side-based signal outputs: left means both front-left and
  /// rear-left lamps, right means both front-right and rear-right lamps.
  static CarCommand buildSignalCommand(SignalMode mode) {
    return _command(Wire.verbSignal, {Wire.keyMode: mode.wire});
  }

  /// `CMD:SERVO;ANGLE:<0-180>`.
  static CarCommand buildServoCommand(int angle) =>
      _command(Wire.verbServo, {Wire.keyAngle: clampInt(angle, 0, 180)});

  /// `CMD:MODE;VALUE:<mode>` — hands control to firmware behaviour, or back.
  static CarCommand buildModeCommand(DriveMode mode) =>
      _command(Wire.verbMode, {Wire.keyModeValue: mode.wire}, isCritical: true);

  /// `CMD:SCAN;MODE:<mode>` — the ESP32 owns sweep timing and sensor reads.
  static CarCommand buildScanCommand(ScanMode mode) =>
      _command(Wire.verbScan, {Wire.keyMode: mode.wire});

  /// `CMD:CONFIG;TIMEOUT:<ms>` — sets the firmware watchdog window.
  static CarCommand buildConfigCommand({required int timeoutMs}) {
    return _command(Wire.verbConfig, {
      Wire.keyTimeout: clampInt(
        timeoutMs,
        AppConfig.minCommandTimeoutMs,
        AppConfig.maxCommandTimeoutMs,
      ),
    });
  }

  /// `CMD:TESTMOTOR;TARGET:<L|R|BOTH>;V:<percent>` for bench calibration.
  static CarCommand buildMotorTestCommand(
    MotorTarget target, {
    int percent = 40,
  }) {
    return _command(Wire.verbTestMotor, {
      Wire.keyTarget: target.wire,
      Wire.keyValue: clampPercent(percent),
    });
  }

  /// `CMD:CAL;...` — pushes motor and servo calibration to the vehicle.
  static CarCommand buildCalibrationCommand({
    required bool invertLeft,
    required bool invertRight,
    required int trimLeft,
    required int trimRight,
    required int servoCenter,
    required int servoMin,
    required int servoMax,
  }) {
    return _command(Wire.verbCalibrate, {
      Wire.keyInvertLeft: invertLeft ? 1 : 0,
      Wire.keyInvertRight: invertRight ? 1 : 0,
      Wire.keyTrimLeft: clampInt(trimLeft, -100, 100),
      Wire.keyTrimRight: clampInt(trimRight, -100, 100),
      Wire.keyServoCenter: clampInt(servoCenter, 0, 180),
      Wire.keyServoMin: clampInt(servoMin, 0, 180),
      Wire.keyServoMax: clampInt(servoMax, 0, 180),
    });
  }

  /// `CMD:PING` — liveness probe used to measure the link when idle.
  static CarCommand buildPingCommand() => _command(Wire.verbPing, const {});

  static CarCommand _command(
    String verb,
    Map<String, Object> fields, {
    bool isCritical = false,
  }) {
    final buffer = StringBuffer()
      ..write(Wire.prefixCommand)
      ..write(Wire.keyValueSeparator)
      ..write(verb);

    fields.forEach((key, value) {
      buffer
        ..write(Wire.fieldSeparator)
        ..write(key)
        ..write(Wire.keyValueSeparator)
        ..write(value);
    });

    buffer.write(Wire.terminator);
    return CarCommand(
      verb: verb,
      frame: buffer.toString(),
      isCritical: isCritical,
    );
  }

  /// Structural check on an outgoing frame.
  ///
  /// Runs before every send so a malformed frame is caught here rather than
  /// being interpreted as something unintended by the firmware.
  static bool validateCommand(String frame) {
    final body = frame.trim();
    if (body.isEmpty || body.length > Wire.maxFrameLength) return false;

    final parts = body.split(Wire.fieldSeparator);
    final head = parts.first.split(Wire.keyValueSeparator);
    if (head.length != 2) return false;
    if (head[0] != Wire.prefixCommand) return false;
    if (!Wire.knownVerbs.contains(head[1])) return false;

    for (final field in parts.skip(1)) {
      final pair = field.split(Wire.keyValueSeparator);
      if (pair.length != 2) return false;
      if (pair[0].isEmpty || pair[1].isEmpty) return false;
    }
    return true;
  }

  // --- Incoming -------------------------------------------------------------

  /// Classifies one inbound frame.
  static RoverFrame parseFrame(String raw, {DateTime? now}) {
    final body = raw.trim();
    if (body.isEmpty) return UnknownFrame(raw, 'Empty frame');

    if (body.startsWith('${Wire.prefixData}${Wire.fieldSeparator}') ||
        body == Wire.prefixData) {
      final telemetry = parseTelemetry(body, now: now);
      return telemetry == null
          ? UnknownFrame(raw, 'No readable telemetry fields')
          : TelemetryFrame(raw, telemetry);
    }

    if (body.startsWith('${Wire.prefixAck}${Wire.keyValueSeparator}')) {
      final ack = parseAck(body, now: now);
      return ack == null
          ? UnknownFrame(raw, 'Malformed ACK')
          : AckFrame(raw, ack);
    }

    if (body.startsWith(Wire.prefixError)) {
      final error = parseError(body, now: now);
      return error == null
          ? UnknownFrame(raw, 'Malformed ERROR')
          : ErrorFrame(raw, error);
    }

    return UnknownFrame(raw, 'Unrecognised frame prefix');
  }

  /// Parses `DATA;BAT:82;DIST:64;...`.
  ///
  /// Unreadable or out-of-range fields are dropped individually — one bad value
  /// must not discard an otherwise good frame, and a nonsense reading must
  /// never reach the dashboard as fact. Returns `null` if nothing survived.
  static Telemetry? parseTelemetry(String raw, {DateTime? now}) {
    final body = raw.trim();
    if (!body.startsWith(Wire.prefixData)) return null;

    final fields = _fields(body.split(Wire.fieldSeparator).skip(1));
    if (fields.isEmpty) return null;

    final timestamp = now ?? DateTime.now();
    var recognised = false;

    int? readClamped(String key, int min, int max) {
      final value = int.tryParse(fields[key] ?? '');
      if (value == null) return null;
      recognised = true;
      return clampInt(value, min, max);
    }

    /// Out-of-range distances mean "no echo", not a clamped measurement.
    int? readDistance(String key) {
      final value = int.tryParse(fields[key] ?? '');
      if (value == null) return null;
      recognised = true;
      if (value < AppConfig.sensorMinRangeCm ||
          value > AppConfig.sensorMaxRangeCm) {
        return null;
      }
      return value;
    }

    final battery = readClamped(Wire.keyBattery, 0, 100);
    final distance = readDistance(Wire.keyDistance);
    final servo = readClamped(Wire.keyServo, 0, 180);
    final speed = readClamped(Wire.keySpeed, 0, 100);
    final left = readClamped(Wire.keyLeft, -100, 100);
    final right = readClamped(Wire.keyRight, -100, 100);
    final signal = readClamped(Wire.keySignal, 0, 100);

    final driveMode = DriveMode.tryParse(fields[Wire.keyMode]);
    final lightMode = LightMode.tryParse(fields[Wire.keyLight]);
    final signalMode = SignalMode.tryParse(fields[Wire.keySignalMode]);
    final vehicleState = VehicleState.tryParse(fields[Wire.keyState]);
    final brakeLight = _parseBool(fields[Wire.keyBrake]);
    final decision = fields[Wire.keyDecision];
    if (driveMode != null ||
        lightMode != null ||
        signalMode != null ||
        vehicleState != null ||
        brakeLight != null ||
        decision != null) {
      recognised = true;
    }

    final samples = <int, RadarSample>{};

    /// A distance reported alongside a servo angle is a radar sample at that
    /// angle, which is how the sweep populates the radar view.
    if (servo != null && fields.containsKey(Wire.keyDistance)) {
      samples[servo] = RadarSample(
        angle: servo,
        distanceCm: distance,
        takenAt: timestamp,
      );
    }

    for (final entry in const {
      Wire.keyDistanceLeft: 0,
      Wire.keyDistanceCenter: 90,
      Wire.keyDistanceRight: 180,
    }.entries) {
      if (!fields.containsKey(entry.key)) continue;
      samples[entry.value] = RadarSample(
        angle: entry.value,
        distanceCm: readDistance(entry.key),
        takenAt: timestamp,
      );
    }

    if (!recognised) return null;

    return Telemetry(
      batteryPercent: battery,
      distanceCm: distance,
      servoAngle: servo,
      speedPercent: speed,
      leftMotor: left,
      rightMotor: right,
      driveMode: driveMode,
      lightMode: lightMode,
      signalMode: signalMode,
      brakeLightOn: brakeLight,
      vehicleState: vehicleState,
      signalPercent: signal,
      radarSamples: samples,
      decision: decision,
      updatedAt: timestamp,
    );
  }

  /// Parses `ACK:DRIVE`.
  static CommandAck? parseAck(String raw, {DateTime? now}) {
    final body = raw.trim();
    final parts = body.split(Wire.keyValueSeparator);
    if (parts.length != 2 || parts[0] != Wire.prefixAck) return null;

    final verb = parts[1].trim().toUpperCase();
    if (verb.isEmpty || !Wire.knownVerbs.contains(verb)) return null;

    return CommandAck(verb: verb, receivedAt: now ?? DateTime.now());
  }

  /// Parses `ERROR;CODE:03;MSG:SENSOR_FAIL`.
  ///
  /// A missing or unreadable code degrades to [RoverErrorCode.unknown] rather
  /// than dropping the frame — an error the app cannot classify still needs to
  /// reach the user.
  static RoverError? parseError(String raw, {DateTime? now}) {
    final body = raw.trim();
    if (!body.startsWith(Wire.prefixError)) return null;

    final fields = _fields(body.split(Wire.fieldSeparator).skip(1));
    final code = RoverErrorCode.fromCode(
      int.tryParse(fields[Wire.keyErrorCode] ?? '') ?? -1,
    );

    final rawMessage = fields[Wire.keyErrorMessage];
    final message = (rawMessage == null || rawMessage.isEmpty)
        ? code.message
        : _humanize(rawMessage);

    return RoverError(
      code: code,
      message: message,
      receivedAt: now ?? DateTime.now(),
    );
  }

  /// Splits `KEY:VALUE` segments into a map, ignoring malformed segments.
  static Map<String, String> _fields(Iterable<String> segments) {
    final fields = <String, String>{};
    for (final segment in segments) {
      final index = segment.indexOf(Wire.keyValueSeparator);
      if (index <= 0) continue;
      final key = segment.substring(0, index).trim().toUpperCase();
      final value = segment.substring(index + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields[key] = value;
    }
    return fields;
  }

  static bool? _parseBool(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    if (normalized == '1' || normalized == 'ON' || normalized == 'TRUE') {
      return true;
    }
    if (normalized == '0' || normalized == 'OFF' || normalized == 'FALSE') {
      return false;
    }
    return null;
  }

  /// `SENSOR_FAIL` → `Sensor fail`, so firmware tokens read as sentences.
  static String _humanize(String token) {
    final words = token.replaceAll('_', ' ').trim().toLowerCase();
    if (words.isEmpty) return token;
    return words[0].toUpperCase() + words.substring(1);
  }
}
