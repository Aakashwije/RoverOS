// Ties the wire protocol to the gait: one function to handle an inbound CMD
// frame, one to build the outbound DATA frame, one to police the drive
// watchdog. Mirrors the shape of ../roveros_op0148/command_handler.h, cut
// down to the verbs this vehicle actually uses.
#pragma once

#include <Arduino.h>

#include "ble_bridge.h"
#include "gait.h"
#include "pins.h"
#include "wire_protocol.h"

// Everything the command handler and the main loop share.
struct Vehicle {
  GaitEngine gait;
  BleBridge ble;

  WalkDirection direction = WalkDirection::kNone;

  // CMD:CONFIG's watchdog window; 750ms matches
  // AppConfig.defaultCommandTimeoutMs on the app side.
  unsigned long commandTimeoutMs = 750;

  // Refreshed by WALK/STOP — if nothing follows within commandTimeoutMs
  // while a direction is held, the watchdog forces a stop.
  unsigned long lastDriveCommandAt = 0;
  bool watchdogTripped = false;
};

// Handles one fully-received line (terminator already stripped). Sends the
// resulting ACK/ERROR straight back over `v.ble`.
inline void handleCommand(Vehicle& v, const String& line) {
  ParsedCommand cmd = parseWireCommand(line);
  if (!cmd.valid) {
    v.ble.send(buildErrorFrame(Proto::kErrBadCommand, "BAD_COMMAND"));
    return;
  }

  if (cmd.verb == Proto::kVerbWalk) {
    String dirWire = cmd.getString(Proto::kKeyDirection, "");
    v.direction = walkDirectionFromWire(dirWire);
    v.lastDriveCommandAt = millis();
    v.watchdogTripped = false;
    // A speed field rides along (CMD:WALK;DIR:..;V:..) but this gait engine
    // only has one stride length for now — see GaitTuning in gait.h. Reading
    // it here is where a variable-speed gait would hook in later.

  } else if (cmd.verb == Proto::kVerbStop) {
    v.direction = WalkDirection::kNone;
    v.gait.neutral();
    v.lastDriveCommandAt = millis();
    v.watchdogTripped = false;

  } else if (cmd.verb == Proto::kVerbConfig) {
    long timeout = v.commandTimeoutMs;
    cmd.getInt(Proto::kKeyTimeout, &timeout);
    v.commandTimeoutMs = constrain(timeout, 300, 2000);

  } else if (cmd.verb == Proto::kVerbPing) {
    // Nothing to do beyond the ACK below — a liveness probe.

  } else {
    v.ble.send(buildErrorFrame(Proto::kErrBadCommand, "UNKNOWN_VERB"));
    return;
  }

  v.ble.send(buildAckFrame(cmd.verb));
}

inline const char* vehicleStateToken(const Vehicle& v) {
  if (v.watchdogTripped) return Proto::kStateFault;
  return v.direction == WalkDirection::kNone ? Proto::kStateStopped
                                              : Proto::kStateDriving;
}

inline String buildTelemetryFrame(const Vehicle& v) {
  TelemetryFrameBuilder frame;
  frame.addStr(Proto::kKeyState, vehicleStateToken(v));
#if PIN_BATTERY_SENSE >= 0
  // Coarse divider reading -> percent. Tune the divider ratio and the two
  // magic numbers below once a real pack is on the sense pin.
  int raw = analogRead(PIN_BATTERY_SENSE);
  long percent = map(raw, 0, 1023, 0, 100);
  frame.addInt(Proto::kKeyBattery, constrain(percent, 0, 100));
#endif
  // No battery-sense pin is wired by default (see README "Known gaps"), so
  // BAT is omitted rather than fabricated when PIN_BATTERY_SENSE is -1.
  return frame.finish();
}

// If a direction was commanded but nothing (WALK or STOP) has followed
// inside the configured window, force a stop and surface it exactly like a
// firmware-detected fault — same policy as the car's watchdog.
inline void checkDriveWatchdog(Vehicle& v) {
  if (v.direction == WalkDirection::kNone) return;
  if (v.watchdogTripped) return;

  if (millis() - v.lastDriveCommandAt <= v.commandTimeoutMs) return;

  v.direction = WalkDirection::kNone;
  v.gait.neutral();
  v.watchdogTripped = true;
  v.ble.send(buildErrorFrame(Proto::kErrWatchdogStop, "WATCHDOG_STOP"));
}
