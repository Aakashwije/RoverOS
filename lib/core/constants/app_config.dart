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

  // --- Perception -----------------------------------------------------------
  //
  // Tunables for `core/perception/`, which turns raw HC-SR04 frames into a
  // filtered estimate, a proximity call and a picture of the space ahead. None
  // of it commands the vehicle: the ESP32 still owns every stop and every
  // autonomous decision. These values only decide what the app *believes* and
  // what it shows.

  /// HC-SR04 one-sigma error, as a fixed floor plus a fraction of the range.
  /// Timing jitter dominates up close; beam spread and temperature drift grow
  /// with distance, so a single constant under- or over-states one end.
  static const double sensorNoiseCm = 1.5;
  static const double sensorNoiseFraction = 0.03;

  /// Half-angle of the sensor cone. A single reading is evidence about this
  /// whole spread of bearings, not just the one the servo is pointed at.
  static const double sensorBeamHalfWidthDegrees = 7.5;

  /// One-sigma acceleration the filter should tolerate without lagging, in
  /// cm/s². Sized for a rover that can go from stationary to full tilt in
  /// roughly a third of a second.
  static const double perceptionManoeuvreNoiseCmPerSecondSquared = 200;

  /// Starting velocity uncertainty, one sigma in cm/s. Wide on purpose: the
  /// first frame says nothing about whether the rover is moving.
  static const double perceptionInitialVelocitySigma = 120;

  /// Physical ceiling on estimated closing speed, cm/s. Stops a burst of bad
  /// frames from producing a velocity the vehicle could not achieve.
  static const double perceptionMaxSpeedCmPerSecond = 300;

  /// A reading further than this many sigmas from the prediction is treated as
  /// an echo artefact and withheld from the update.
  static const double perceptionOutlierSigma = 3;

  /// Consecutive rejections after which the filter concedes that the world
  /// changed rather than the sensor lying, and re-seeds on the new reading.
  /// Without this a genuine step change — the rover turning to face a wall —
  /// would be rejected forever.
  static const int perceptionMaxConsecutiveRejects = 3;

  /// Depth of the rolling residual/echo record behind the confidence score.
  static const int perceptionWindowSamples = 12;

  /// Updates needed before the filter reports full maturity.
  static const int perceptionMaturitySamples = 5;

  /// An estimate at a bearing the servo has left behind decays to worthless
  /// over this window, and the filter re-seeds rather than resuming.
  static const Duration perceptionBearingStaleAfter = Duration(seconds: 2);

  /// Confidence below which the app declines to make a proximity call at all.
  static const double perceptionMinConfidence = 0.25;

  /// Closing speeds under this are treated as noise, not approach.
  static const double perceptionMinClosingCmPerSecond = 3;

  /// Time-to-contact is meaningless beyond this horizon; nothing is reported.
  static const Duration perceptionMaxTimeToContact = Duration(seconds: 20);

  /// Time-to-contact thresholds. These escalate the proximity call regardless
  /// of absolute distance: 30cm at a crawl is fine, 30cm at full tilt is not.
  static const Duration perceptionContactCritical = Duration(
    milliseconds: 1200,
  );
  static const Duration perceptionContactWarning = Duration(milliseconds: 2500);

  /// Extra clearance required before the proximity call is allowed to *relax*
  /// a level. Escalation is never delayed; only recovery is damped, so the
  /// badge stops flickering when a reading sits on a threshold.
  static const int perceptionHysteresisCm = 6;

  // --- Perception: the space ahead -----------------------------------------

  /// Chassis width. Sets how far a return has to be enlarged before the gap
  /// finder will call a bearing traversable.
  static const int roverWidthCm = 18;

  /// Angular resolution of the gap histogram.
  static const int perceptionSectorDegrees = 2;

  /// A gap wider than this is steered into near its edge rather than its
  /// centre, so the rover hugs the opening it is aiming for instead of
  /// wandering to the middle of a wide-open room.
  static const int perceptionWideGapDegrees = 40;

  /// How much a degree of extra width is worth against a degree of deviation
  /// from dead ahead when ranking gaps.
  static const double perceptionGapWidthWeight = 0.25;

  /// Floor on gap width, so a sliver between two enlarged returns is never
  /// offered as a route.
  static const int perceptionMinGapDegrees = 10;

  /// Radar samples older than this are dropped from the field analysis. A
  /// sweep takes a couple of seconds; anything older describes where the rover
  /// used to be.
  static const Duration perceptionSampleTtl = Duration(seconds: 4);

  /// Max perpendicular deviation, as a floor plus a fraction of mean range,
  /// for a run of returns to still read as one flat surface.
  static const double perceptionStraightnessCm = 6;
  static const double perceptionStraightnessFraction = 0.06;

  /// Angle between two adjacent flat runs for them to read as a corner rather
  /// than as one wall or two unrelated surfaces.
  static const double perceptionCornerMinDegrees = 25;

  /// Cartesian extent under which a one- or two-point return reads as a
  /// discrete object rather than part of a surface.
  static const double perceptionObjectMaxWidthCm = 30;

  /// Worst incidence angle assumed when deciding whether a depth step between
  /// neighbouring returns is a real discontinuity. The test only works while
  /// the sweep is finer than this, which the stock five-angle sweep is not.
  static const double perceptionWorstIncidenceDegrees = 40;

  /// Angular spacing above which returns are too far apart to be assumed to
  /// share a surface, so discontinuity splitting is skipped.
  static const double perceptionFineSweepMaxSpacingDegrees = 12;

  // --- Mock mode ------------------------------------------------------------

  static const Duration mockTelemetryInterval = Duration(milliseconds: 200);
  static const Duration mockConnectDelay = Duration(milliseconds: 900);
  static const Duration mockScanDeviceInterval = Duration(milliseconds: 600);
}
