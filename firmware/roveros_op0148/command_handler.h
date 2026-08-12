// Ties the wire protocol to the hardware: one function to handle an inbound
// CMD frame, one to build the outbound DATA frame, one to police the drive
// watchdog. This is the only file that knows both "what a frame means" and
// "which subsystem owns that behaviour".
#pragma once

#include <Arduino.h>

#include "autonomy.h"
#include "ble_link.h"
#include "calibration.h"
#include "lights.h"
#include "motors.h"
#include "sensors.h"
#include "wire_protocol.h"

enum class DriveModeWire { kManual, kAvoid, kScan };
enum class ScanModeWire { kOff, kOnce, kAuto };

// Everything the command handler and the main loop share.
struct Vehicle {
  CalibrationStore cal;
  Lights lights;
  RadarSweep radar;
  ObstacleAvoider avoider;
  BleLink ble;

  DriveModeWire driveMode = DriveModeWire::kManual;
  ScanModeWire scanMode = ScanModeWire::kOff;
  int speedPercent = 70;

  int lastLeft = 0;
  int lastRight = 0;
  int lastServoAngle = 90;
  int lastDistanceCm = 0;
  String lastDecision;

  // Refreshed by DRIVE/STOP/TESTMOTOR — the watchdog only polices MANUAL
  // driving, since autonomous modes drive the motors every loop iteration
  // regardless of whether the phone has sent anything recently.
  unsigned long lastDriveCommandAt = 0;
  bool watchdogTripped = false;
};

inline void applyModeChange(Vehicle& v, DriveModeWire mode) {
  if (mode == v.driveMode) return;

  // "Entering an autonomous mode always stops first" (drive_controller.dart)
  // — and leaving one cleans up whatever it was doing to the servo/radar.
  Motors::stop();
  v.lights.setBrake(true);
  v.lastLeft = 0;
  v.lastRight = 0;
  v.radar.stop(v.cal.get());
  v.scanMode = ScanModeWire::kOff;

  v.driveMode = mode;
  if (mode == DriveModeWire::kAvoid) {
    v.avoider.start(v.cal.get());
  } else if (mode == DriveModeWire::kScan) {
    v.radar.start(/*loop=*/true, v.cal.get());
    v.scanMode = ScanModeWire::kAuto;
  }
  v.watchdogTripped = false;
  v.lastDriveCommandAt = millis();
}

inline void applyScanChange(Vehicle& v, ScanModeWire mode) {
  v.scanMode = mode;
  switch (mode) {
    case ScanModeWire::kAuto:
      v.radar.start(/*loop=*/true, v.cal.get());
      break;
    case ScanModeWire::kOnce:
      v.radar.start(/*loop=*/false, v.cal.get());
      break;
    case ScanModeWire::kOff:
      v.radar.stop(v.cal.get());
      break;
  }
}

// Handles one fully-received line (terminator already stripped). Sends the
// resulting ACK/ERROR straight back over `v.ble`.
inline void handleCommand(Vehicle& v, const String& line) {
  ParsedCommand cmd = parseWireCommand(line);
  if (!cmd.valid) {
    v.ble.send(buildErrorFrame(Proto::kErrBadCommand, "BAD_COMMAND"));
    return;
  }

  const Calibration& cal = v.cal.get();

  if (cmd.verb == Proto::kVerbDrive) {
    long left = 0, right = 0;
    cmd.getInt(Proto::kKeyLeft, &left);
    cmd.getInt(Proto::kKeyRight, &right);
    left = constrain(left, -100, 100);
    right = constrain(right, -100, 100);
    Motors::driveRaw(left, right);
    v.lights.setBrake(left == 0 && right == 0);
    v.lastLeft = left;
    v.lastRight = right;
    v.lastDriveCommandAt = millis();
    v.watchdogTripped = false;

  } else if (cmd.verb == Proto::kVerbStop) {
    Motors::stop();
    v.lights.setBrake(true);
    v.lastLeft = 0;
    v.lastRight = 0;
    v.lastDriveCommandAt = millis();
    v.watchdogTripped = false;

  } else if (cmd.verb == Proto::kVerbSpeed) {
    long value = v.speedPercent;
    cmd.getInt(Proto::kKeyValue, &value);
    v.speedPercent = constrain(value, 0, 100);

  } else if (cmd.verb == Proto::kVerbLight) {
    String mode = cmd.getString(Proto::kKeyMode, Proto::kLightOff);
    long brightness = 100;
    cmd.getInt(Proto::kKeyBrightness, &brightness);
    v.lights.setMode(Lights::fromWire(mode), constrain(brightness, 0, 100));

  } else if (cmd.verb == Proto::kVerbSignal) {
    String mode = cmd.getString(Proto::kKeyMode, Proto::kSignalOff);
    v.lights.setSignal(Lights::signalFromWire(mode));

  } else if (cmd.verb == Proto::kVerbServo) {
    long angle = v.lastServoAngle;
    cmd.getInt(Proto::kKeyAngle, &angle);
    angle = constrain(angle, 0, 180);
    Sensors::moveServo(angle, cal);
    v.lastServoAngle = angle;

  } else if (cmd.verb == Proto::kVerbMode) {
    String value = cmd.getString(Proto::kKeyModeValue, Proto::kModeManual);
    if (value == Proto::kModeAvoid || value == "AUTO") {
      applyModeChange(v, DriveModeWire::kAvoid);
    } else if (value == Proto::kModeScan) {
      applyModeChange(v, DriveModeWire::kScan);
    } else {
      applyModeChange(v, DriveModeWire::kManual);
    }

  } else if (cmd.verb == Proto::kVerbScan) {
    String value = cmd.getString(Proto::kKeyMode, Proto::kScanOff);
    if (value == Proto::kScanAuto) {
      applyScanChange(v, ScanModeWire::kAuto);
    } else if (value == Proto::kScanOnce) {
      applyScanChange(v, ScanModeWire::kOnce);
    } else {
      applyScanChange(v, ScanModeWire::kOff);
    }

  } else if (cmd.verb == Proto::kVerbConfig) {
    long timeout = cal.commandTimeoutMs;
    cmd.getInt(Proto::kKeyTimeout, &timeout);
    v.cal.setCommandTimeout(constrain(timeout, 300, 2000));

  } else if (cmd.verb == Proto::kVerbTestMotor) {
    String target = cmd.getString(Proto::kKeyTarget, Proto::kTargetBoth);
    long percent = 40;
    cmd.getInt(Proto::kKeyValue, &percent);
    percent = constrain(percent, -100, 100);
    int left = (target == Proto::kTargetRight) ? 0 : percent;
    int right = (target == Proto::kTargetLeft) ? 0 : percent;
    Motors::driveRaw(left, right);
    v.lights.setBrake(left == 0 && right == 0);
    v.lastLeft = left;
    v.lastRight = right;
    v.lastDriveCommandAt = millis();
    v.watchdogTripped = false;

  } else if (cmd.verb == Proto::kVerbCalibrate) {
    long invL = cal.invertLeft, invR = cal.invertRight;
    long trimL = cal.trimLeft, trimR = cal.trimRight;
    long center = cal.servoCenter, smin = cal.servoMin, smax = cal.servoMax;
    cmd.getInt(Proto::kKeyInvertLeft, &invL);
    cmd.getInt(Proto::kKeyInvertRight, &invR);
    cmd.getInt(Proto::kKeyTrimLeft, &trimL);
    cmd.getInt(Proto::kKeyTrimRight, &trimR);
    cmd.getInt(Proto::kKeyServoCenter, &center);
    cmd.getInt(Proto::kKeyServoMin, &smin);
    cmd.getInt(Proto::kKeyServoMax, &smax);

    v.cal.setMotorCalibration(invL != 0, invR != 0,
                               (int8_t)constrain(trimL, -25, 25),
                               (int8_t)constrain(trimR, -25, 25));

    // Clamp the range to the physical 0-180 sweep *before* clamping centre
    // into it, so a malformed frame can never leave centre outside the
    // stored [min, max] band.
    long clampedMin = constrain(smin, 0, 180);
    long clampedMax = constrain(smax, 0, 180);
    if (clampedMin < clampedMax) {
      long clampedCenter = constrain(center, clampedMin, clampedMax);
      v.cal.setServoCalibration((uint8_t)clampedCenter, (uint8_t)clampedMin,
                                 (uint8_t)clampedMax);
    }

  } else if (cmd.verb == Proto::kVerbPing) {
    // Nothing to do beyond the ACK below — a liveness probe.

  } else {
    v.ble.send(buildErrorFrame(Proto::kErrBadCommand, "UNKNOWN_VERB"));
    return;
  }

  v.ble.send(buildAckFrame(cmd.verb));
}

inline const char* driveModeWireToken(DriveModeWire mode) {
  switch (mode) {
    case DriveModeWire::kAvoid:
      return Proto::kModeAvoid;
    case DriveModeWire::kScan:
      return Proto::kModeScan;
    default:
      return Proto::kModeManual;
  }
}

inline const char* vehicleStateToken(const Vehicle& v) {
  if (v.watchdogTripped) return Proto::kStateFault;
  switch (v.driveMode) {
    case DriveModeWire::kAvoid:
      return Proto::kStateAvoiding;
    case DriveModeWire::kScan:
      return Proto::kStateScanning;
    default:
      return (v.lastLeft != 0 || v.lastRight != 0) ? Proto::kStateDriving
                                                     : Proto::kStateStopped;
  }
}

inline String buildTelemetryFrame(const Vehicle& v) {
  TelemetryFrameBuilder frame;
  // A 0 reading (no echo) is sent as-is: the app's own parser already treats
  // DIST:0 as "no reading" rather than a real distance (see
  // CarProtocol.parseTelemetry), so there is no need to pre-filter here.
  frame.addInt(Proto::kKeyDistance, v.lastDistanceCm);
  frame.addInt(Proto::kKeyServo, v.lastServoAngle);
  frame.addInt(Proto::kKeySpeed, v.speedPercent);
  frame.addInt(Proto::kKeyLeft, v.lastLeft);
  frame.addInt(Proto::kKeyRight, v.lastRight);
  frame.addStr(Proto::kKeyMode, driveModeWireToken(v.driveMode));
  frame.addStr(Proto::kKeyLight, v.lights.toWire());
  frame.addStr(Proto::kKeySignalMode, v.lights.signalToWire());
  frame.addInt(Proto::kKeyBrake, v.lights.brakeOn() ? 1 : 0);
  frame.addStr(Proto::kKeyState, vehicleStateToken(v));
  if (v.lastDecision.length() > 0) {
    frame.addStr(Proto::kKeyDecision, v.lastDecision.c_str());
  }
  // No battery-sense pin is documented for this board (see firmware
  // README), so BAT is deliberately omitted rather than fabricated.
  return frame.finish();
}

// MANUAL-mode-only safety net: if a drive command was issued but nothing
// (DRIVE, STOP or TESTMOTOR) has followed inside the configured window, force
// a stop and surface it exactly like a firmware-detected fault.
inline void checkDriveWatchdog(Vehicle& v) {
  if (v.driveMode != DriveModeWire::kManual) return;
  if (v.lastLeft == 0 && v.lastRight == 0) return;
  if (v.watchdogTripped) return;

  unsigned long elapsed = millis() - v.lastDriveCommandAt;
  if (elapsed <= v.cal.get().commandTimeoutMs) return;

  Motors::stop();
  v.lights.setBrake(true);
  v.lastLeft = 0;
  v.lastRight = 0;
  v.watchdogTripped = true;
  v.ble.send(buildErrorFrame(Proto::kErrWatchdogStop, "WATCHDOG_STOP"));
}
