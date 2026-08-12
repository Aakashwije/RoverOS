// Behaviour that runs entirely on the vehicle: the radar sweep (DriveMode
// AUTO_SCAN / the CMD:SCAN verb) and basic obstacle avoidance (DriveMode
// AVOID). Both are non-blocking — driven by tick() calls from the main loop
// — so BLE, the watchdog and telemetry keep running while either is active.
//
// "Autonomous decisions happen on the vehicle. The phone only sends
// CMD:MODE/CMD:SCAN and displays telemetry.decision" (README Safety model).
#pragma once

#include <Arduino.h>

#include "calibration.h"
#include "motors.h"
#include "sensors.h"

static const int kRadarAngles[] = {0, 45, 90, 135, 180};
static const uint8_t kRadarAngleCount = 5;

// Sweeps the HC-SR04 across kRadarAngles, producing one (angle, distance)
// sample at a time for the caller to fold into a DATA;SERVO:..;DIST:.. frame
// — the same shape a live radar-sweep chart expects.
class RadarSweep {
 public:
  struct Sample {
    bool ready = false;
    int angle = 0;
    int distanceCm = 0;
  };

  void start(bool loop, const Calibration& cal) {
    active_ = true;
    loop_ = loop;
    index_ = 0;
    Sensors::moveServo(kRadarAngles[0], cal);
    phase_ = Phase::kSettling;
    phaseStartedAt_ = millis();
  }

  void stop(const Calibration& cal) {
    active_ = false;
    Sensors::centerServo(cal);
  }

  bool isActive() const { return active_; }

  Sample tick(const Calibration& cal) {
    Sample result;
    if (!active_) return result;

    unsigned long now = millis();
    if (phase_ == Phase::kSettling) {
      if (now - phaseStartedAt_ < kSettleMs) return result;
    }

    result.ready = true;
    result.angle = kRadarAngles[index_];
    result.distanceCm = Sensors::readDistanceCm();

    index_++;
    if (index_ >= kRadarAngleCount) {
      if (!loop_) {
        active_ = false;
        Sensors::centerServo(cal);
        return result;
      }
      index_ = 0;
    }
    Sensors::moveServo(kRadarAngles[index_], cal);
    phase_ = Phase::kSettling;
    phaseStartedAt_ = now;
    return result;
  }

 private:
  enum class Phase { kSettling, kMeasuring };
  static const unsigned long kSettleMs = 200;

  bool active_ = false;
  bool loop_ = true;
  uint8_t index_ = 0;
  Phase phase_ = Phase::kSettling;
  unsigned long phaseStartedAt_ = 0;
};

// Deliberately simple reference behaviour: drive forward until the centre
// reading crosses a fixed threshold, then reverse briefly and pivot to look
// for a clear path. There is currently no wire field carrying the app's
// user-configurable obstacle distance (AppSettings.minObstacleDistanceCm) —
// only client-side display thresholds exist on that end — so this threshold
// is a firmware constant rather than something CMD:CAL can adjust yet.
class ObstacleAvoider {
 public:
  void start(const Calibration& cal) {
    state_ = State::kForward;
    Sensors::centerServo(cal);
    lastSenseAt_ = 0;
    lastDistanceCm_ = 0;
  }

  struct Result {
    String decision;
    int distanceCm = -1;  // -1 == not re-sampled this tick
    // Percents actually commanded this tick, so the caller can mirror them
    // into telemetry's L/R fields — this class drives the motors directly,
    // so nothing else observes what it just sent.
    int left = 0;
    int right = 0;
  };

  Result tick(const Calibration& cal) {
    Result result;
    unsigned long now = millis();

    if (now - lastSenseAt_ >= kSenseIntervalMs) {
      lastSenseAt_ = now;
      lastDistanceCm_ = Sensors::readDistanceCm();
      result.distanceCm = lastDistanceCm_;
    }

    bool blocked = lastDistanceCm_ > 0 && lastDistanceCm_ < kThresholdCm;

    switch (state_) {
      case State::kForward:
        if (blocked) {
          state_ = State::kReversing;
          phaseStartedAt_ = now;
          result.left = result.right = 0;
          result.decision = "Obstacle ahead";
        } else {
          result.left = result.right = kForwardSpeed;
          result.decision = "Path clear";
        }
        break;

      case State::kReversing:
        result.left = result.right = -kReverseSpeed;
        result.decision = "Reversing";
        if (now - phaseStartedAt_ >= kReverseMs) {
          state_ = State::kTurning;
          phaseStartedAt_ = now;
        }
        break;

      case State::kTurning:
        result.left = kTurnSpeed;
        result.right = -kTurnSpeed;
        result.decision = "Turning";
        if (now - phaseStartedAt_ >= kTurnMs) {
          state_ = State::kForward;
        }
        break;
    }
    Motors::driveCalibrated(result.left, result.right, cal);
    return result;
  }

 private:
  enum class State { kForward, kReversing, kTurning };
  static const int kThresholdCm = 25;
  static const int kForwardSpeed = 35;
  static const int kReverseSpeed = 35;
  static const int kTurnSpeed = 45;
  static const unsigned long kReverseMs = 500;
  static const unsigned long kTurnMs = 600;
  static const unsigned long kSenseIntervalMs = 150;

  State state_ = State::kForward;
  unsigned long phaseStartedAt_ = 0;
  unsigned long lastSenseAt_ = 0;
  int lastDistanceCm_ = 0;
};
