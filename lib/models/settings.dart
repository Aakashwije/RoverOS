import '../core/constants/app_config.dart';
import '../core/utils/validation.dart';
import 'commands.dart';

enum DistanceUnits {
  metric('METRIC', 'cm'),
  imperial('IMPERIAL', 'in');

  const DistanceUnits(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  /// Convert a centimetre reading into the display unit.
  double fromCm(int cm) => this == metric ? cm.toDouble() : cm / 2.54;

  String format(int? cm) {
    if (cm == null) return '—';
    final value = fromCm(cm);
    return this == metric ? value.round().toString() : value.toStringAsFixed(1);
  }

  static DistanceUnits fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => metric);
}

/// Which side of the landscape drive HUD carries the joystick.
///
/// One-handed driving is common — the other hand is holding the rover, a
/// charger, or nothing at all — and which thumb is free is not something the
/// app can guess. Mirroring the whole HUD is cheaper than asking the user to
/// adapt.
enum JoystickSide {
  left('LEFT', 'Joystick left, sensors right'),
  right('RIGHT', 'Joystick right, sensors left');

  const JoystickSide(this.label, this.description);

  final String label;
  final String description;

  JoystickSide get opposite => this == left ? right : left;

  static JoystickSide fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => left);
}

/// How quickly the ESP32 alternates the headlights in a flash mode.
enum FlashSpeed {
  slow('SLOW', LightMode.flashSlow),
  fast('FAST', LightMode.flashFast);

  const FlashSpeed(this.label, this.lightMode);

  final String label;
  final LightMode lightMode;

  static FlashSpeed fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => slow);
}

/// All persisted user preferences.
///
/// Immutable; the settings controller replaces the whole object on change and
/// writes it back to disk. [normalized] re-clamps every field, so a corrupt or
/// out-of-date stored payload can never push an illegal value into motor math.
class AppSettings {
  const AppSettings({
    // VEHICLE
    this.vehicleName = 'ESP32-CAR',
    this.maxSpeedPercent = 70,
    this.defaultDriveMode = DriveMode.manual,
    // CONTROLS
    this.joystickSensitivity = 1.0,
    this.deadZonePercent = 12,
    this.accelerationRate = 400,
    this.decelerationRate = 700,
    this.hapticsEnabled = true,
    this.joystickSide = JoystickSide.left,
    // MOTORS
    this.invertLeftMotor = false,
    this.invertRightMotor = false,
    this.leftMotorTrim = 0,
    this.rightMotorTrim = 0,
    // SENSORS
    this.minObstacleDistanceCm = AppConfig.defaultMinObstacleDistanceCm,
    this.cautionDistanceCm = AppConfig.defaultCautionDistanceCm,
    this.dangerDistanceCm = AppConfig.defaultDangerDistanceCm,
    this.servoCenter = 90,
    this.servoMinAngle = 0,
    this.servoMaxAngle = 180,
    // LIGHTS
    this.defaultLightMode = LightMode.off,
    this.flashSpeed = FlashSpeed.slow,
    this.lightBrightness = 100,
    // CONNECTION
    this.autoReconnect = true,
    this.commandTimeoutMs = AppConfig.defaultCommandTimeoutMs,
    // APP
    this.soundsEnabled = false,
    this.units = DistanceUnits.metric,
    this.mockMode = true,
  });

  /// Defaults, including mock mode on so a fresh install is explorable with no
  /// hardware present.
  static const AppSettings defaults = AppSettings();

  // VEHICLE
  final String vehicleName;

  /// Ceiling applied to every motor command the app emits.
  final int maxSpeedPercent;
  final DriveMode defaultDriveMode;

  // CONTROLS
  final double joystickSensitivity;

  /// Radius, as a percentage of stick travel, treated as centre.
  final int deadZonePercent;

  /// Ramp rates in percent-per-second.
  final double accelerationRate;
  final double decelerationRate;
  final bool hapticsEnabled;

  /// Which side of the drive HUD the joystick sits on.
  final JoystickSide joystickSide;

  // MOTORS
  final bool invertLeftMotor;
  final bool invertRightMotor;

  /// Per-side trim in percent, to straighten a rover that pulls to one side.
  final int leftMotorTrim;
  final int rightMotorTrim;

  // SENSORS
  final int minObstacleDistanceCm;
  final int cautionDistanceCm;
  final int dangerDistanceCm;
  final int servoCenter;
  final int servoMinAngle;
  final int servoMaxAngle;

  // LIGHTS
  final LightMode defaultLightMode;
  final FlashSpeed flashSpeed;
  final int lightBrightness;

  // CONNECTION
  final bool autoReconnect;
  final int commandTimeoutMs;

  // APP
  final bool soundsEnabled;
  final DistanceUnits units;

  /// Drives the whole app from a simulated rover instead of the radio.
  final bool mockMode;

  /// Dead zone expressed as a 0–1 fraction of stick travel.
  double get deadZoneFraction => deadZonePercent / 100;

  /// Re-clamps every field into its legal range and repairs relationships
  /// between fields (danger < caution, servo min < centre < max).
  AppSettings normalized() {
    var caution = Validators.distanceCm(cautionDistanceCm);
    var danger = Validators.distanceCm(dangerDistanceCm);
    if (danger >= caution) {
      // Preserve the caution band the user set and push danger below it.
      danger = (caution - 5)
          .clamp(SettingsRange.minDistanceCm, caution)
          .toInt();
      if (danger == caution) caution = danger + 5;
    }

    var servoMin = Validators.servoAngle(servoMinAngle);
    var servoMax = Validators.servoAngle(servoMaxAngle);
    if (servoMin >= servoMax) {
      servoMin = SettingsRange.minServoAngle;
      servoMax = SettingsRange.maxServoAngle;
    }
    final center = Validators.servoAngle(
      servoCenter,
    ).clamp(servoMin, servoMax).toInt();

    return AppSettings(
      vehicleName: Validators.sanitizeVehicleName(vehicleName),
      maxSpeedPercent: Validators.speedPercent(maxSpeedPercent),
      defaultDriveMode: defaultDriveMode,
      joystickSensitivity: Validators.sensitivity(joystickSensitivity),
      deadZonePercent: Validators.deadZonePercent(deadZonePercent),
      accelerationRate: Validators.rampRate(accelerationRate),
      decelerationRate: Validators.rampRate(decelerationRate),
      hapticsEnabled: hapticsEnabled,
      joystickSide: joystickSide,
      invertLeftMotor: invertLeftMotor,
      invertRightMotor: invertRightMotor,
      leftMotorTrim: Validators.motorTrim(leftMotorTrim),
      rightMotorTrim: Validators.motorTrim(rightMotorTrim),
      minObstacleDistanceCm: Validators.distanceCm(minObstacleDistanceCm),
      cautionDistanceCm: caution,
      dangerDistanceCm: danger,
      servoCenter: center,
      servoMinAngle: servoMin,
      servoMaxAngle: servoMax,
      defaultLightMode: defaultLightMode,
      flashSpeed: flashSpeed,
      lightBrightness: Validators.brightness(lightBrightness),
      autoReconnect: autoReconnect,
      commandTimeoutMs: Validators.commandTimeoutMs(commandTimeoutMs),
      soundsEnabled: soundsEnabled,
      units: units,
      mockMode: mockMode,
    );
  }

  AppSettings copyWith({
    String? vehicleName,
    int? maxSpeedPercent,
    DriveMode? defaultDriveMode,
    double? joystickSensitivity,
    int? deadZonePercent,
    double? accelerationRate,
    double? decelerationRate,
    bool? hapticsEnabled,
    JoystickSide? joystickSide,
    bool? invertLeftMotor,
    bool? invertRightMotor,
    int? leftMotorTrim,
    int? rightMotorTrim,
    int? minObstacleDistanceCm,
    int? cautionDistanceCm,
    int? dangerDistanceCm,
    int? servoCenter,
    int? servoMinAngle,
    int? servoMaxAngle,
    LightMode? defaultLightMode,
    FlashSpeed? flashSpeed,
    int? lightBrightness,
    bool? autoReconnect,
    int? commandTimeoutMs,
    bool? soundsEnabled,
    DistanceUnits? units,
    bool? mockMode,
  }) {
    return AppSettings(
      vehicleName: vehicleName ?? this.vehicleName,
      maxSpeedPercent: maxSpeedPercent ?? this.maxSpeedPercent,
      defaultDriveMode: defaultDriveMode ?? this.defaultDriveMode,
      joystickSensitivity: joystickSensitivity ?? this.joystickSensitivity,
      deadZonePercent: deadZonePercent ?? this.deadZonePercent,
      accelerationRate: accelerationRate ?? this.accelerationRate,
      decelerationRate: decelerationRate ?? this.decelerationRate,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      joystickSide: joystickSide ?? this.joystickSide,
      invertLeftMotor: invertLeftMotor ?? this.invertLeftMotor,
      invertRightMotor: invertRightMotor ?? this.invertRightMotor,
      leftMotorTrim: leftMotorTrim ?? this.leftMotorTrim,
      rightMotorTrim: rightMotorTrim ?? this.rightMotorTrim,
      minObstacleDistanceCm:
          minObstacleDistanceCm ?? this.minObstacleDistanceCm,
      cautionDistanceCm: cautionDistanceCm ?? this.cautionDistanceCm,
      dangerDistanceCm: dangerDistanceCm ?? this.dangerDistanceCm,
      servoCenter: servoCenter ?? this.servoCenter,
      servoMinAngle: servoMinAngle ?? this.servoMinAngle,
      servoMaxAngle: servoMaxAngle ?? this.servoMaxAngle,
      defaultLightMode: defaultLightMode ?? this.defaultLightMode,
      flashSpeed: flashSpeed ?? this.flashSpeed,
      lightBrightness: lightBrightness ?? this.lightBrightness,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      commandTimeoutMs: commandTimeoutMs ?? this.commandTimeoutMs,
      soundsEnabled: soundsEnabled ?? this.soundsEnabled,
      units: units ?? this.units,
      mockMode: mockMode ?? this.mockMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'vehicleName': vehicleName,
    'maxSpeedPercent': maxSpeedPercent,
    'defaultDriveMode': defaultDriveMode.name,
    'joystickSensitivity': joystickSensitivity,
    'deadZonePercent': deadZonePercent,
    'accelerationRate': accelerationRate,
    'decelerationRate': decelerationRate,
    'hapticsEnabled': hapticsEnabled,
    'joystickSide': joystickSide.name,
    'invertLeftMotor': invertLeftMotor,
    'invertRightMotor': invertRightMotor,
    'leftMotorTrim': leftMotorTrim,
    'rightMotorTrim': rightMotorTrim,
    'minObstacleDistanceCm': minObstacleDistanceCm,
    'cautionDistanceCm': cautionDistanceCm,
    'dangerDistanceCm': dangerDistanceCm,
    'servoCenter': servoCenter,
    'servoMinAngle': servoMinAngle,
    'servoMaxAngle': servoMaxAngle,
    'defaultLightMode': defaultLightMode.name,
    'flashSpeed': flashSpeed.name,
    'lightBrightness': lightBrightness,
    'autoReconnect': autoReconnect,
    'commandTimeoutMs': commandTimeoutMs,
    'soundsEnabled': soundsEnabled,
    'units': units.name,
    'mockMode': mockMode,
  };

  /// Tolerant of missing, extra and wrongly-typed keys — a stored payload from
  /// an older build must never crash startup.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, T fallback) {
      final value = json[key];
      return value is T ? value : fallback;
    }

    double pickDouble(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return fallback;
    }

    int pickInt(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.toInt();
      return fallback;
    }

    const d = AppSettings.defaults;
    return AppSettings(
      vehicleName: pick('vehicleName', d.vehicleName),
      maxSpeedPercent: pickInt('maxSpeedPercent', d.maxSpeedPercent),
      defaultDriveMode: DriveMode.values.firstWhere(
        (m) => m.name == json['defaultDriveMode'],
        orElse: () => d.defaultDriveMode,
      ),
      joystickSensitivity: pickDouble(
        'joystickSensitivity',
        d.joystickSensitivity,
      ),
      deadZonePercent: pickInt('deadZonePercent', d.deadZonePercent),
      accelerationRate: pickDouble('accelerationRate', d.accelerationRate),
      decelerationRate: pickDouble('decelerationRate', d.decelerationRate),
      hapticsEnabled: pick('hapticsEnabled', d.hapticsEnabled),
      joystickSide: JoystickSide.fromName(json['joystickSide'] as String?),
      invertLeftMotor: pick('invertLeftMotor', d.invertLeftMotor),
      invertRightMotor: pick('invertRightMotor', d.invertRightMotor),
      leftMotorTrim: pickInt('leftMotorTrim', d.leftMotorTrim),
      rightMotorTrim: pickInt('rightMotorTrim', d.rightMotorTrim),
      minObstacleDistanceCm: pickInt(
        'minObstacleDistanceCm',
        d.minObstacleDistanceCm,
      ),
      cautionDistanceCm: pickInt('cautionDistanceCm', d.cautionDistanceCm),
      dangerDistanceCm: pickInt('dangerDistanceCm', d.dangerDistanceCm),
      servoCenter: pickInt('servoCenter', d.servoCenter),
      servoMinAngle: pickInt('servoMinAngle', d.servoMinAngle),
      servoMaxAngle: pickInt('servoMaxAngle', d.servoMaxAngle),
      defaultLightMode: LightMode.values.firstWhere(
        (m) => m.name == json['defaultLightMode'],
        orElse: () => d.defaultLightMode,
      ),
      flashSpeed: FlashSpeed.fromName(json['flashSpeed'] as String?),
      lightBrightness: pickInt('lightBrightness', d.lightBrightness),
      autoReconnect: pick('autoReconnect', d.autoReconnect),
      commandTimeoutMs: pickInt('commandTimeoutMs', d.commandTimeoutMs),
      soundsEnabled: pick('soundsEnabled', d.soundsEnabled),
      units: DistanceUnits.fromName(json['units'] as String?),
      mockMode: pick('mockMode', d.mockMode),
    ).normalized();
  }
}
