// ROVEROS firmware for the Optimus OP0148 ESP32 Car Controller Board.
//
// Speaks the exact BLE protocol the ROVEROS Flutter app expects — see
// ../../lib/services/car_protocol.dart and
// ../../lib/core/constants/command_constants.dart, which this firmware
// mirrors token-for-token. See README.md in this folder for the toolchain
// setup and a rundown of what is (and is not) implemented.
//
// Board reference: "ESP32 Car Controller Board User Guide V1.0.0".
#include "command_handler.h"

Vehicle vehicle;

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("ROVEROS / Optimus OP0148 firmware starting..."));

  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);

  vehicle.cal.begin();
  Motors::begin();
  vehicle.lights.begin();
  Sensors::begin();

  Sensors::centerServo(vehicle.cal.get());
  vehicle.lastServoAngle = vehicle.cal.get().servoCenter;

  vehicle.ble.begin([](const String& line) { handleCommand(vehicle, line); });

  Serial.print(F("BLE advertising as "));
  Serial.println(DEVICE_NAME);
}

// How the sensor gets shared between the three drive modes each loop tick.
void serviceCurrentMode() {
  switch (vehicle.driveMode) {
    case DriveModeWire::kAvoid: {
      ObstacleAvoider::Result r = vehicle.avoider.tick(vehicle.cal.get());
      if (r.distanceCm >= 0) vehicle.lastDistanceCm = r.distanceCm;
      vehicle.lastDecision = r.decision;
      vehicle.lastLeft = r.left;
      vehicle.lastRight = r.right;
      vehicle.lights.setBrake(r.left == 0 && r.right == 0);
      vehicle.lastServoAngle = vehicle.cal.get().servoCenter;
      break;
    }

    case DriveModeWire::kScan: {
      RadarSweep::Sample s = vehicle.radar.tick(vehicle.cal.get());
      if (s.ready) {
        vehicle.lastServoAngle = s.angle;
        vehicle.lastDistanceCm = s.distanceCm;
      }
      break;
    }

    case DriveModeWire::kManual: {
      if (vehicle.scanMode != ScanModeWire::kOff && vehicle.radar.isActive()) {
        // The user toggled the radar sweep on (CMD:SCAN) without leaving
        // manual drive — e.g. "look around" while stationary or crawling.
        RadarSweep::Sample s = vehicle.radar.tick(vehicle.cal.get());
        if (s.ready) {
          vehicle.lastServoAngle = s.angle;
          vehicle.lastDistanceCm = s.distanceCm;
        }
      } else {
        // Nothing else owns the sensor: keep the Drive screen's distance
        // card alive with a low-rate forward-facing reading.
        static unsigned long lastIdleSenseAt = 0;
        unsigned long now = millis();
        if (now - lastIdleSenseAt >= 150) {
          lastIdleSenseAt = now;
          vehicle.lastDistanceCm = Sensors::readDistanceCm();
        }
      }
      break;
    }
  }
}

void loop() {
  static unsigned long lastTelemetryAt = 0;
  const unsigned long kTelemetryIntervalMs = 150;

  digitalWrite(PIN_STATUS_LED, vehicle.ble.isConnected() ? HIGH : LOW);

  vehicle.lights.tick();
  checkDriveWatchdog(vehicle);
  serviceCurrentMode();

  unsigned long now = millis();
  if (now - lastTelemetryAt >= kTelemetryIntervalMs) {
    lastTelemetryAt = now;
    vehicle.ble.send(buildTelemetryFrame(vehicle));
  }
}
