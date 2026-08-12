// Wire protocol tokens and framing helpers.
//
// Mirrors lib/core/constants/command_constants.dart and
// lib/services/car_protocol.dart on the Flutter side exactly. If a token
// changes on either side, it must change on both — nothing here is
// coincidental. Frame grammar:
//
//   <PREFIX>[:<VERB>][;<KEY>:<VALUE>]*\n
//   CMD:DRIVE;L:70;R:-40
//   DATA;BAT:82;DIST:64;SERVO:90
//   ACK:STOP
//   ERROR;CODE:03;MSG:SENSOR_FAIL
#pragma once

#include <Arduino.h>
#include <stdlib.h>

namespace Proto {

// --- Frame structure -------------------------------------------------------
constexpr const char* kPrefixCommand = "CMD";
constexpr const char* kPrefixData = "DATA";
constexpr const char* kPrefixAck = "ACK";
constexpr const char* kPrefixError = "ERROR";

constexpr char kFieldSeparator = ';';
constexpr char kKeyValueSeparator = ':';
constexpr char kTerminator = '\n';
constexpr size_t kMaxFrameLength = 256;

// --- Command verbs -----------------------------------------------------
constexpr const char* kVerbDrive = "DRIVE";
constexpr const char* kVerbStop = "STOP";
constexpr const char* kVerbSpeed = "SPEED";
constexpr const char* kVerbLight = "LIGHT";
constexpr const char* kVerbSignal = "SIGNAL";
constexpr const char* kVerbServo = "SERVO";
constexpr const char* kVerbMode = "MODE";
constexpr const char* kVerbScan = "SCAN";
constexpr const char* kVerbConfig = "CONFIG";
constexpr const char* kVerbPing = "PING";
constexpr const char* kVerbTestMotor = "TESTMOTOR";
constexpr const char* kVerbCalibrate = "CAL";

// --- Command / telemetry keys -------------------------------------------
constexpr const char* kKeyLeft = "L";
constexpr const char* kKeyRight = "R";
constexpr const char* kKeyValue = "V";
constexpr const char* kKeyMode = "MODE";
constexpr const char* kKeyAngle = "ANGLE";
constexpr const char* kKeyModeValue = "VALUE";
constexpr const char* kKeyTimeout = "TIMEOUT";
constexpr const char* kKeyTarget = "TARGET";
constexpr const char* kKeyBrightness = "BRIGHT";
constexpr const char* kKeyInvertLeft = "INVL";
constexpr const char* kKeyInvertRight = "INVR";
constexpr const char* kKeyTrimLeft = "TRIML";
constexpr const char* kKeyTrimRight = "TRIMR";
constexpr const char* kKeyServoCenter = "SCENTER";
constexpr const char* kKeyServoMin = "SMIN";
constexpr const char* kKeyServoMax = "SMAX";

constexpr const char* kKeyBattery = "BAT";
constexpr const char* kKeyDistance = "DIST";
constexpr const char* kKeyServo = "SERVO";
constexpr const char* kKeySpeed = "SPD";
constexpr const char* kKeyLight = "LIGHT";
constexpr const char* kKeySignalMode = "SIGNAL";
constexpr const char* kKeyBrake = "BRAKE";
constexpr const char* kKeyDecision = "DEC";
constexpr const char* kKeyState = "STATE";

constexpr const char* kKeyErrorCode = "CODE";
constexpr const char* kKeyErrorMessage = "MSG";

// --- Enum wire values ----------------------------------------------------
constexpr const char* kLightOff = "OFF";
constexpr const char* kLightOn = "ON";
constexpr const char* kLightFlashSlow = "FLASH_SLOW";
constexpr const char* kLightFlashFast = "FLASH_FAST";
constexpr const char* kLightHazard = "HAZARD";

constexpr const char* kSignalOff = "OFF";
constexpr const char* kSignalLeft = "LEFT";
constexpr const char* kSignalRight = "RIGHT";
constexpr const char* kSignalHazard = "HAZARD";

constexpr const char* kModeManual = "MANUAL";
constexpr const char* kModeAvoid = "AVOID";
constexpr const char* kModeScan = "SCAN";

constexpr const char* kScanAuto = "AUTO";
constexpr const char* kScanOnce = "ONCE";
constexpr const char* kScanOff = "OFF";

constexpr const char* kTargetLeft = "L";
constexpr const char* kTargetRight = "R";
constexpr const char* kTargetBoth = "BOTH";

constexpr const char* kStateIdle = "IDLE";
constexpr const char* kStateDriving = "DRIVING";
constexpr const char* kStateStopped = "STOPPED";
constexpr const char* kStateAvoiding = "AVOIDING";
constexpr const char* kStateScanning = "SCANNING";
constexpr const char* kStateFault = "FAULT";

// RoverErrorCode values, from lib/core/constants/command_constants.dart.
constexpr int kErrUnknown = 0;
constexpr int kErrBadCommand = 1;
constexpr int kErrMotorFault = 2;
constexpr int kErrSensorFail = 3;
constexpr int kErrServoFail = 4;
constexpr int kErrLowBattery = 5;
constexpr int kErrOverCurrent = 6;
constexpr int kErrWatchdogStop = 7;
constexpr int kErrCalibrationFail = 8;

}  // namespace Proto

// One `KEY:VALUE` field parsed from an inbound frame.
struct WireField {
  String key;
  String value;
};

// A fully parsed inbound CMD frame.
struct ParsedCommand {
  bool valid = false;
  String verb;
  static const uint8_t kMaxFields = 12;
  WireField fields[kMaxFields];
  uint8_t fieldCount = 0;

  bool has(const char* key) const {
    for (uint8_t i = 0; i < fieldCount; i++) {
      if (fields[i].key.equalsIgnoreCase(key)) return true;
    }
    return false;
  }

  // Returns 0 (and leaves `out` untouched) when absent or unreadable, which
  // is treated the same as "field not sent" — mirrors car_protocol.dart's
  // tolerant field parsing.
  bool getInt(const char* key, long* out) const {
    for (uint8_t i = 0; i < fieldCount; i++) {
      if (!fields[i].key.equalsIgnoreCase(key)) continue;
      // strtol reports failure via endptr, not errno, so check it explicitly.
      char* end = nullptr;
      long value = strtol(fields[i].value.c_str(), &end, 10);
      if (end == fields[i].value.c_str()) return false;
      *out = value;
      return true;
    }
    return false;
  }

  String getString(const char* key, const String& fallback = "") const {
    for (uint8_t i = 0; i < fieldCount; i++) {
      if (fields[i].key.equalsIgnoreCase(key)) return fields[i].value;
    }
    return fallback;
  }
};

// Parses one line (terminator already stripped) shaped like
// `CMD:VERB;KEY:VALUE;KEY:VALUE`. Never throws: a malformed frame just comes
// back with `.valid == false`.
inline ParsedCommand parseWireCommand(const String& line) {
  ParsedCommand result;

  String trimmed = line;
  trimmed.trim();
  if (trimmed.length() == 0 || trimmed.length() > Proto::kMaxFrameLength) {
    return result;
  }

  int cursor = 0;
  int semi = trimmed.indexOf(Proto::kFieldSeparator);
  String head = semi < 0 ? trimmed : trimmed.substring(0, semi);
  cursor = semi < 0 ? trimmed.length() : semi + 1;

  int colon = head.indexOf(Proto::kKeyValueSeparator);
  if (colon < 0) return result;
  String prefix = head.substring(0, colon);
  if (prefix != Proto::kPrefixCommand) return result;

  result.verb = head.substring(colon + 1);
  result.verb.toUpperCase();

  while (cursor < (int)trimmed.length() &&
         result.fieldCount < ParsedCommand::kMaxFields) {
    int next = trimmed.indexOf(Proto::kFieldSeparator, cursor);
    String segment = next < 0 ? trimmed.substring(cursor)
                               : trimmed.substring(cursor, next);
    cursor = next < 0 ? trimmed.length() : next + 1;

    int kv = segment.indexOf(Proto::kKeyValueSeparator);
    if (kv <= 0) continue;  // malformed field pair: skip, don't abort.
    String key = segment.substring(0, kv);
    String value = segment.substring(kv + 1);
    key.trim();
    value.trim();
    if (key.length() == 0 || value.length() == 0) continue;
    key.toUpperCase();

    result.fields[result.fieldCount].key = key;
    result.fields[result.fieldCount].value = value;
    result.fieldCount++;
  }

  result.valid = true;
  return result;
}

// --- Outbound frame builders ------------------------------------------------

// Small fixed-field DATA frame builder. Call `add*` for whichever fields are
// currently known, then `finish()`. Fields with no known value are simply
// never added, matching the app's tolerant "a frame may carry any subset of
// fields" parsing.
class TelemetryFrameBuilder {
 public:
  TelemetryFrameBuilder() { buffer_ = Proto::kPrefixData; }

  void addInt(const char* key, long value) {
    buffer_ += Proto::kFieldSeparator;
    buffer_ += key;
    buffer_ += Proto::kKeyValueSeparator;
    buffer_ += value;
  }

  void addStr(const char* key, const char* value) {
    buffer_ += Proto::kFieldSeparator;
    buffer_ += key;
    buffer_ += Proto::kKeyValueSeparator;
    buffer_ += value;
  }

  String finish() {
    buffer_ += Proto::kTerminator;
    return buffer_;
  }

 private:
  String buffer_;
};

inline String buildAckFrame(const String& verb) {
  String frame = Proto::kPrefixAck;
  frame += Proto::kKeyValueSeparator;
  frame += verb;
  frame += Proto::kTerminator;
  return frame;
}

inline String buildErrorFrame(int code, const char* message) {
  String frame = Proto::kPrefixError;
  frame += Proto::kFieldSeparator;
  frame += Proto::kKeyErrorCode;
  frame += Proto::kKeyValueSeparator;
  frame += code;
  frame += Proto::kFieldSeparator;
  frame += Proto::kKeyErrorMessage;
  frame += Proto::kKeyValueSeparator;
  frame += message;
  frame += Proto::kTerminator;
  return frame;
}
