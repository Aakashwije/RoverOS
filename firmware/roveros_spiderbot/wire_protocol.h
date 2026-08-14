// Wire protocol tokens and framing helpers.
//
// Mirrors lib/core/constants/command_constants.dart and
// lib/services/spider_commands.dart on the Flutter side exactly. If a token
// changes on either side, it must change on both — nothing here is
// coincidental. Frame grammar (identical to the OP0148 car's protocol —
// see ../roveros_op0148/wire_protocol.h — this vehicle just uses a smaller
// slice of the same vocabulary):
//
//   <PREFIX>[:<VERB>][;<KEY>:<VALUE>]*\n
//   CMD:WALK;DIR:FWD;V:60
//   DATA;BAT:82;STATE:DRIVING
//   ACK:STOP
//   ERROR;CODE:07;MSG:WATCHDOG_STOP
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
// Only the generic verbs the app sends to every vehicle, plus WALK — the
// spiderbot's own. See command_constants.dart's `Wire.knownVerbs` for the
// full car+spider vocabulary; this firmware only needs to recognise its own
// slice of it.
constexpr const char* kVerbStop = "STOP";
constexpr const char* kVerbConfig = "CONFIG";
constexpr const char* kVerbPing = "PING";
constexpr const char* kVerbWalk = "WALK";

// --- Command / telemetry keys -------------------------------------------
constexpr const char* kKeyValue = "V";
constexpr const char* kKeyTimeout = "TIMEOUT";
constexpr const char* kKeyDirection = "DIR";

constexpr const char* kKeyBattery = "BAT";
constexpr const char* kKeyState = "STATE";

constexpr const char* kKeyErrorCode = "CODE";
constexpr const char* kKeyErrorMessage = "MSG";

// --- CMD:WALK direction values ------------------------------------------
constexpr const char* kDirForward = "FWD";
constexpr const char* kDirBack = "BACK";
constexpr const char* kDirLeft = "LEFT";
constexpr const char* kDirRight = "RIGHT";
constexpr const char* kDirRotateLeft = "ROTL";
constexpr const char* kDirRotateRight = "ROTR";

// --- DATA;STATE values ---------------------------------------------------
constexpr const char* kStateStopped = "STOPPED";
constexpr const char* kStateDriving = "DRIVING";
constexpr const char* kStateFault = "FAULT";

// RoverErrorCode values, from lib/core/constants/command_constants.dart.
constexpr int kErrBadCommand = 1;
constexpr int kErrWatchdogStop = 7;

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
  static const uint8_t kMaxFields = 8;
  WireField fields[kMaxFields];
  uint8_t fieldCount = 0;

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
