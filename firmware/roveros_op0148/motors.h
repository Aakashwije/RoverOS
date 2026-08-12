// Differential drive over the board's four L9110S-driven DC motors.
//
// M1 (front right) and M2 (rear right) are wired in lock-step as "right";
// M3 (front left) and M4 (rear left) as "left" — this board has no separate
// steering axis, so ROVEROS's signed L/R percents map straight onto sides.
#pragma once

#include <Arduino.h>
#include <math.h>

#include "calibration.h"
#include "pins.h"

namespace Motors {

inline void begin() {
  pinMode(PIN_M1_FORWARD, OUTPUT);
  pinMode(PIN_M1_BACKWARD, OUTPUT);
  pinMode(PIN_M2_FORWARD, OUTPUT);
  pinMode(PIN_M2_BACKWARD, OUTPUT);
  pinMode(PIN_M3_FORWARD, OUTPUT);
  pinMode(PIN_M3_BACKWARD, OUTPUT);
  pinMode(PIN_M4_FORWARD, OUTPUT);
  pinMode(PIN_M4_BACKWARD, OUTPUT);
}

inline int percentToPwm(int percent) {
  if (percent < -100) percent = -100;
  if (percent > 100) percent = 100;
  return (abs(percent) * MOTOR_PWM_MAX) / 100;
}

inline void driveSide(int forwardPin, int backwardPin, int percent) {
  int pwm = percentToPwm(percent);
  if (percent >= 0) {
    analogWrite(forwardPin, pwm);
    analogWrite(backwardPin, 0);
  } else {
    analogWrite(forwardPin, 0);
    analogWrite(backwardPin, pwm);
  }
}

// Executes an already-calibrated L/R percent pair (-100..100) as-is. The app
// applies trim/inversion/speed-ceiling client-side before sending CMD:DRIVE
// (see MotorMath.applyCalibration in lib/core/utils/motor_math.dart), so
// re-applying calibration here would double it.
inline void driveRaw(int leftPercent, int rightPercent) {
  driveSide(PIN_M3_FORWARD, PIN_M3_BACKWARD, leftPercent);
  driveSide(PIN_M4_FORWARD, PIN_M4_BACKWARD, leftPercent);
  driveSide(PIN_M1_FORWARD, PIN_M1_BACKWARD, rightPercent);
  driveSide(PIN_M2_FORWARD, PIN_M2_BACKWARD, rightPercent);
}

// For firmware-owned autonomous driving (AVOID / SCAN modes), which has no
// app in the loop to have already calibrated the output.
inline void driveCalibrated(int leftPercent, int rightPercent,
                             const Calibration& cal) {
  int left = leftPercent;
  int right = rightPercent;
  if (left != 0) left = (int)round(left * (1.0f + cal.trimLeft / 100.0f));
  if (right != 0) {
    right = (int)round(right * (1.0f + cal.trimRight / 100.0f));
  }
  if (cal.invertLeft) left = -left;
  if (cal.invertRight) right = -right;
  driveRaw(left, right);
}

inline void stop() { driveRaw(0, 0); }

}  // namespace Motors
