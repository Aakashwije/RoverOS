// ROVEROS firmware for the Optimus Spiderbot (Arduino Nano + a BLE-serial
// add-on module).
//
// Speaks the same generic wire protocol as the ESP32 car firmware
// (../roveros_op0148/), plus one command of its own: CMD:WALK. See
// ../../lib/services/spider_commands.dart and
// ../../lib/core/constants/command_constants.dart, which this firmware
// mirrors token-for-token. See README.md in this folder for wiring,
// toolchain setup and known gaps.
#include "command_handler.h"

Vehicle vehicle;

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("ROVEROS / Optimus Spiderbot firmware starting..."));

  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);

  vehicle.gait.begin();
  vehicle.ble.begin([](const String& line) { handleCommand(vehicle, line); });

  Serial.println(F("Waiting for a BLE central to connect..."));
}

void loop() {
  static unsigned long lastTelemetryAt = 0;
  const unsigned long kTelemetryIntervalMs = 250;

  // The BLE module has no interrupt-driven receive path on this MCU, unlike
  // the ESP32's own BLE stack — bytes only move when polled.
  vehicle.ble.poll();
  digitalWrite(PIN_STATUS_LED, vehicle.ble.isConnected() ? HIGH : LOW);

  checkDriveWatchdog(vehicle);
  vehicle.gait.tick(vehicle.direction);

  unsigned long now = millis();
  if (now - lastTelemetryAt >= kTelemetryIntervalMs) {
    lastTelemetryAt = now;
    vehicle.ble.send(buildTelemetryFrame(vehicle));
  }
}
