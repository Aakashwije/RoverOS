// HC-SR04 distance sensor and radar-sweep servo — the raw drivers only.
// Sweep/avoidance *behaviour* lives in autonomy.h.
#pragma once

#include <Arduino.h>
#include <ESP32Servo.h>

#include "calibration.h"
#include "pins.h"

namespace Sensors {

// `static`, not `inline`, on purpose: this sketch is one translation unit
// (Arduino concatenates the .ino + its .h tabs), so ODR-safe `inline`
// variables aren't needed, and `inline` namespace-scope variables require
// C++17, which not every arduino-esp32 core toolchain defaults to.
static Servo gRadarServo;
static bool gServoAttached = false;

inline void begin() {
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  digitalWrite(PIN_US_TRIG, LOW);
}

inline void attachServo() {
  if (gServoAttached) return;
  gRadarServo.setPeriodHertz(50);
  gRadarServo.attach(PIN_SERVO, 500, 2400);
  gServoAttached = true;
}

// Returns 0 on no echo — the app already treats DIST:0 as "no reading" (see
// CarProtocol.parseTelemetry's readDistance).
inline int readDistanceCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);

  // ~30ms caps the wait at roughly a 5m round trip — well past the sensor's
  // real ~4m limit, so a genuine timeout is unambiguous.
  unsigned long durationUs = pulseIn(PIN_US_ECHO, HIGH, 30000UL);
  if (durationUs == 0) return 0;
  return (int)(durationUs / 58.0);
}

inline void moveServo(int angle, const Calibration& cal) {
  attachServo();
  int clamped = constrain(angle, (int)cal.servoMin, (int)cal.servoMax);
  gRadarServo.write(clamped);
}

inline void centerServo(const Calibration& cal) {
  moveServo(cal.servoCenter, cal);
}

}  // namespace Sensors
