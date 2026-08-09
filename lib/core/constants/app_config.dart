/// Tunable, non-user-facing constants for the whole app.
abstract final class AppConfig {
  static const String appName = 'ROVEROS';
  static const String tagline = 'SMART VEHICLE CONTROL';

  // --- Drive command pacing -------------------------------------------------

  /// Upper bound on drive commands per second. The joystick animates at display
  /// refresh rate but must never emit a packet per frame — a classic BLE
  /// throughput failure that stalls the ESP32's serial buffer.
  static const int driveCommandsPerSecond = 15;

  static Duration get driveCommandInterval =>
      Duration(milliseconds: (1000 / driveCommandsPerSecond).round());

  /// Motor output change (in percent) below which a repeat command is skipped.
  static const int driveCommandEpsilon = 2;

  /// Resent periodically while the stick is held so the firmware watchdog sees
  /// traffic even when the user holds a perfectly steady position.
  static const Duration driveKeepAlive = Duration(milliseconds: 250);

  // --- Safety ---------------------------------------------------------------

  /// Default firmware watchdog window pushed to the ESP32 via `CMD:CONFIG`.
  /// The vehicle cuts motors if no valid drive command arrives inside it.
  static const int defaultCommandTimeoutMs = 750;
  static const int minCommandTimeoutMs = 300;
  static const int maxCommandTimeoutMs = 2000;

  /// A STOP is retried this many times if the transport reports failure.
  static const int stopCommandRetries = 3;

  /// Telemetry older than this is shown as stale rather than as live truth.
  static const Duration telemetryStaleAfter = Duration(seconds: 3);

  // --- Connection -----------------------------------------------------------

  static const Duration scanTimeout = Duration(seconds: 12);
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Exponential backoff for auto-reconnect, capped so we never hammer the
  /// radio. Attempt n waits `min(base * 2^n, max)`.
  static const Duration reconnectBaseDelay = Duration(milliseconds: 800);
  static const Duration reconnectMaxDelay = Duration(seconds: 20);
  static const int maxReconnectAttempts = 6;

  /// Names matching these prefixes float to the top of the scan list.
  static const List<String> knownDeviceNameHints = [
    'ESP32',
    'ROVER',
    'OPTIMUS',
    'CAR',
    'BT',
  ];

  // --- Nordic UART Service (the de-facto standard for ESP32 BLE serial) -----

  static const String nordicUartService =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nordicUartRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nordicUartTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// BLE MTU worth requesting; ROVEROS packets are far smaller but a larger MTU
  /// removes fragmentation on telemetry bursts.
  static const int preferredMtu = 185;

  // --- Signal quality (RSSI, dBm) ------------------------------------------

  static const int rssiExcellent = -60;
  static const int rssiGood = -72;
  static const int rssiFair = -85;

  // --- Battery --------------------------------------------------------------

  /// 2× 18650 in series sag badly under motor load near the bottom of the pack,
  /// so ROVEROS warns earlier than a phone-style battery meter would.
  static const int batteryLowPercent = 30;
  static const int batteryCriticalPercent = 15;

  // --- Sensors --------------------------------------------------------------

  /// HC-SR04 usable range. Readings outside this are treated as no-echo rather
  /// than as a real measurement.
  static const int sensorMinRangeCm = 2;
  static const int sensorMaxRangeCm = 400;

  static const int defaultDangerDistanceCm = 30;
  static const int defaultCautionDistanceCm = 60;
  static const int defaultMinObstacleDistanceCm = 25;

  /// Servo sweep positions reported by the radar.
  static const List<int> radarAngles = [0, 45, 90, 135, 180];

  // --- Mock mode ------------------------------------------------------------

  static const Duration mockTelemetryInterval = Duration(milliseconds: 200);
  static const Duration mockConnectDelay = Duration(milliseconds: 900);
  static const Duration mockScanDeviceInterval = Duration(milliseconds: 600);
}
