/// Every wire token used by the ROVEROS ↔ ESP32 protocol.
///
/// Nothing outside this file (and `services/car_protocol.dart`, which composes
/// these) may contain a raw protocol string. If a token changes in firmware it
/// changes here exactly once.
///
/// Frame grammar:
/// ```text
///   <PREFIX>[:<VERB>][;<KEY>:<VALUE>]*\n
///   CMD:DRIVE;L:70;R:-40
///   DATA;BAT:82;DIST:64;SERVO:90
///   ACK:STOP
///   ERROR;CODE:03;MSG:SENSOR_FAIL
/// ```
abstract final class Wire {
  // --- Frame structure ------------------------------------------------------

  static const String prefixCommand = 'CMD';
  static const String prefixData = 'DATA';
  static const String prefixAck = 'ACK';
  static const String prefixError = 'ERROR';

  static const String fieldSeparator = ';';
  static const String keyValueSeparator = ':';
  static const String terminator = '\n';

  /// Longest legal frame. Guards against a malformed stream being buffered
  /// without bound if the device never emits a terminator.
  static const int maxFrameLength = 256;

  // --- Command verbs --------------------------------------------------------

  static const String verbDrive = 'DRIVE';
  static const String verbStop = 'STOP';
  static const String verbSpeed = 'SPEED';
  static const String verbLight = 'LIGHT';
  static const String verbSignal = 'SIGNAL';
  static const String verbServo = 'SERVO';
  static const String verbMode = 'MODE';
  static const String verbScan = 'SCAN';
  static const String verbConfig = 'CONFIG';
  static const String verbPing = 'PING';
  static const String verbTestMotor = 'TESTMOTOR';
  static const String verbCalibrate = 'CAL';

  /// Spiderbot gait command — the only verb outside the OP0148 car's
  /// vocabulary. See `lib/services/spider_commands.dart`.
  static const String verbWalk = 'WALK';

  static const Set<String> knownVerbs = {
    verbDrive,
    verbStop,
    verbSpeed,
    verbLight,
    verbSignal,
    verbServo,
    verbMode,
    verbScan,
    verbConfig,
    verbPing,
    verbTestMotor,
    verbCalibrate,
    verbWalk,
  };

  // --- Command keys ---------------------------------------------------------

  static const String keyLeft = 'L';
  static const String keyRight = 'R';
  static const String keyValue = 'V';
  static const String keyMode = 'MODE';
  static const String keyAngle = 'ANGLE';
  static const String keyModeValue = 'VALUE';
  static const String keyTimeout = 'TIMEOUT';
  static const String keyTarget = 'TARGET';
  static const String keyBrightness = 'BRIGHT';
  static const String keyInvertLeft = 'INVL';
  static const String keyInvertRight = 'INVR';
  static const String keyTrimLeft = 'TRIML';
  static const String keyTrimRight = 'TRIMR';
  static const String keyServoCenter = 'SCENTER';
  static const String keyServoMin = 'SMIN';
  static const String keyServoMax = 'SMAX';
  static const String keyDirection = 'DIR';

  // --- Telemetry keys -------------------------------------------------------

  static const String keyBattery = 'BAT';
  static const String keyDistance = 'DIST';
  static const String keyServo = 'SERVO';
  static const String keySpeed = 'SPD';
  static const String keyLight = 'LIGHT';
  static const String keySignalMode = 'SIGNAL';
  static const String keyBrake = 'BRAKE';
  static const String keySignal = 'SIG';
  static const String keyDistanceLeft = 'DL';
  static const String keyDistanceCenter = 'DC';
  static const String keyDistanceRight = 'DR';
  static const String keyDecision = 'DEC';
  static const String keyState = 'STATE';

  // --- Error frame keys -----------------------------------------------------

  static const String keyErrorCode = 'CODE';
  static const String keyErrorMessage = 'MSG';

  // --- Enum values ----------------------------------------------------------

  static const String lightOff = 'OFF';
  static const String lightOn = 'ON';
  static const String lightFlashSlow = 'FLASH_SLOW';
  static const String lightFlashFast = 'FLASH_FAST';
  static const String lightHazard = 'HAZARD';

  static const String signalOff = 'OFF';
  static const String signalLeft = 'LEFT';
  static const String signalRight = 'RIGHT';
  static const String signalHazard = 'HAZARD';

  static const String modeManual = 'MANUAL';
  static const String modeAvoid = 'AVOID';
  static const String modeScan = 'SCAN';

  /// Firmware built before the mode split reports a single `AUTO`; treated as
  /// obstacle avoidance so older boards still drive the UI correctly.
  static const String modeAutoLegacy = 'AUTO';

  static const String scanAuto = 'AUTO';
  static const String scanOnce = 'ONCE';
  static const String scanOff = 'OFF';

  static const String targetLeft = 'L';
  static const String targetRight = 'R';
  static const String targetBoth = 'BOTH';

  static const String stateIdle = 'IDLE';
  static const String stateDriving = 'DRIVING';
  static const String stateStopped = 'STOPPED';
  static const String stateAvoiding = 'AVOIDING';
  static const String stateScanning = 'SCANNING';
  static const String stateFault = 'FAULT';

  // --- Spiderbot: CMD:WALK direction values ----------------------------------

  static const String dirForward = 'FWD';
  static const String dirBack = 'BACK';
  static const String dirLeft = 'LEFT';
  static const String dirRight = 'RIGHT';
  static const String dirRotateLeft = 'ROTL';
  static const String dirRotateRight = 'ROTR';
}

/// Error codes reported by the ESP32 in `ERROR;CODE:nn;MSG:...` frames.
enum RoverErrorCode {
  unknown(0, 'Unknown vehicle error'),
  badCommand(1, 'Vehicle rejected the command'),
  motorFault(2, 'Unable to confirm motor response'),
  sensorFail(3, 'HC-SR04 is not responding'),
  servoFail(4, 'Servo is not responding'),
  lowBattery(5, 'Battery level is below the recommended level'),
  overCurrent(6, 'Motor over-current protection tripped'),
  watchdogStop(7, 'Vehicle stopped: no commands received'),
  calibrationFail(8, 'Calibration could not be applied');

  const RoverErrorCode(this.code, this.message);

  final int code;

  /// Human-readable default. Firmware may override it with its own `MSG`.
  final String message;

  static RoverErrorCode fromCode(int code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => RoverErrorCode.unknown,
  );
}
