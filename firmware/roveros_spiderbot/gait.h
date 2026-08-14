// Basic trot gait for a 4-leg, 2-servo-per-leg (hip + knee) quadruped.
//
// This is a starting point, not a tuned gait: exact leg geometry, servo
// orientation and travel range depend on how the kit is physically
// assembled, none of which is known before it's built. Everything under
// GaitTuning is meant to be adjusted on the bench once the legs are wired —
// the same role firmware/op_car_classic_optimized/op_car_classic_optimized.ino's
// "User tuning" block plays for that board.
#pragma once

#include <Arduino.h>
#include <Servo.h>

#include "wire_protocol.h"

/// Which way the gait should carry the body. Mirrors
/// lib/services/spider_commands.dart's `WalkDirection` — `kNone` is this
/// firmware's own addition, standing in for "no CMD:WALK direction field, or
/// the last one wasn't recognised".
enum class WalkDirection {
  kNone,
  kForward,
  kBack,
  kLeft,
  kRight,
  kRotateLeft,
  kRotateRight,
};

inline WalkDirection walkDirectionFromWire(const String& wire) {
  if (wire == Proto::kDirForward) return WalkDirection::kForward;
  if (wire == Proto::kDirBack) return WalkDirection::kBack;
  if (wire == Proto::kDirLeft) return WalkDirection::kLeft;
  if (wire == Proto::kDirRight) return WalkDirection::kRight;
  if (wire == Proto::kDirRotateLeft) return WalkDirection::kRotateLeft;
  if (wire == Proto::kDirRotateRight) return WalkDirection::kRotateRight;
  return WalkDirection::kNone;
}

namespace GaitTuning {
// --- TUNE THESE ON THE BENCH ------------------------------------------------
// Leg order used throughout this file: 0 = front-left, 1 = front-right,
// 2 = back-left, 3 = back-right.
constexpr uint8_t kLegCount = 4;

constexpr uint8_t kHipPins[kLegCount] = {3, 5, 6, 9};
constexpr uint8_t kKneePins[kLegCount] = {10, 11, A0, A1};

// Flip whichever entries move the wrong way once servos are wired — a servo
// mounted on the mirrored (right) side of the chassis usually reverses which
// physical direction counts as "forward" for that leg's hip joint.
constexpr bool kHipInvert[kLegCount] = {false, true, false, true};

constexpr int kHipNeutralDeg = 90;
constexpr int kHipSwingDeg = 30;    // Degrees off neutral at full stride.
constexpr int kKneeStanceDeg = 90;  // Leg planted, bearing weight.
constexpr int kKneeLiftDeg = 55;    // Leg lifted clear of the ground.

// Duration of one gait phase; a full step cycle is 2x this. Lower is a
// faster, choppier gait — raise it if the legs fight each other before a
// swing finishes.
constexpr unsigned long kStepIntervalMs = 220;
// --- END TUNE THESE ----------------------------------------------------------
}  // namespace GaitTuning

/// Drives the eight leg servos through a trot gait: legs move in diagonal
/// pairs (front-left + back-right, then front-right + back-left) so two feet
/// are always planted. `tick()` must be called every loop iteration — it
/// only actually advances the gait every `GaitTuning::kStepIntervalMs`.
class GaitEngine {
 public:
  void begin() {
    using namespace GaitTuning;
    for (uint8_t i = 0; i < kLegCount; i++) {
      hip_[i].attach(kHipPins[i]);
      knee_[i].attach(kKneePins[i]);
    }
    neutral();
  }

  /// Parks every leg in a stable standing pose and resets the gait phase, so
  /// the next step always starts from a known position.
  void neutral() {
    using namespace GaitTuning;
    for (uint8_t i = 0; i < kLegCount; i++) {
      hip_[i].write(kHipNeutralDeg);
      knee_[i].write(kKneeStanceDeg);
    }
    phase_ = false;
    lastStepAt_ = millis();
  }

  void tick(WalkDirection direction) {
    if (direction == WalkDirection::kNone) return;

    unsigned long now = millis();
    if (now - lastStepAt_ < GaitTuning::kStepIntervalMs) return;
    lastStepAt_ = now;
    phase_ = !phase_;
    applyPhase(direction);
  }

 private:
  static bool isPairA(uint8_t legIndex) {
    return legIndex == 0 || legIndex == 3;  // front-left + back-right
  }

  static bool isLeftSide(uint8_t legIndex) {
    return legIndex == 0 || legIndex == 2;
  }

  void applyPhase(WalkDirection direction) {
    using namespace GaitTuning;

    for (uint8_t i = 0; i < kLegCount; i++) {
      bool lifting = (isPairA(i) == phase_);
      int sign = kHipInvert[i] ? -1 : 1;
      int hipAngle = kHipNeutralDeg + sign * hipOffsetDeg(direction, i, lifting);
      hip_[i].write(constrain(hipAngle, 0, 180));
      knee_[i].write(lifting ? kKneeLiftDeg : kKneeStanceDeg);
    }
  }

  /// Offset from neutral for one leg's hip servo this phase, before the
  /// per-leg invert in `applyPhase` is applied.
  int hipOffsetDeg(WalkDirection direction, uint8_t legIndex, bool lifting) {
    const int full = GaitTuning::kHipSwingDeg;

    switch (direction) {
      case WalkDirection::kForward:
        return lifting ? full : -full;

      case WalkDirection::kBack:
        return lifting ? -full : full;

      case WalkDirection::kLeft:
      case WalkDirection::kRight: {
        // A gentle curve while walking forward: the leg on the inside of the
        // turn takes a shorter stride than the outside one.
        bool insideOfTurn =
            (direction == WalkDirection::kLeft) == isLeftSide(legIndex);
        int stride = insideOfTurn ? full / 2 : full;
        return lifting ? stride : -stride;
      }

      case WalkDirection::kRotateLeft:
      case WalkDirection::kRotateRight: {
        // In-place turn: while planted, a leg pushes toward one rotational
        // extreme; while lifted, it swings back to the other extreme, ready
        // to plant and push again next phase.
        bool pushForward =
            (direction == WalkDirection::kRotateLeft) != isLeftSide(legIndex);
        int extreme = pushForward ? full : -full;
        return lifting ? -extreme : extreme;
      }

      case WalkDirection::kNone:
        return 0;
    }
    return 0;
  }

  Servo hip_[GaitTuning::kLegCount];
  Servo knee_[GaitTuning::kLegCount];
  bool phase_ = false;
  unsigned long lastStepAt_ = 0;
};
