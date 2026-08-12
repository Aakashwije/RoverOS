// Headlight, brake, and signal-light state machines.
//
// "Flash timing lives on the ESP32; the app names a mode exactly once and
// never toggles the LED itself" (car_protocol.dart) — so all blink timing is
// owned here, driven by tick() from the main loop.
#pragma once

#include <Arduino.h>

#include "pins.h"
#include "wire_protocol.h"

enum class HeadlightMode { kOff, kOn, kFlashSlow, kFlashFast, kHazard };
enum class SignalMode { kOff, kLeft, kRight, kHazard };

class Lights {
 public:
  void begin() {
    pinMode(PIN_SIGNAL_RIGHT, OUTPUT);
    pinMode(PIN_SIGNAL_LEFT, OUTPUT);
    pinMode(PIN_BRAKE_LIGHT, OUTPUT);
    pinMode(PIN_HEADLIGHT, OUTPUT);
    pinMode(PIN_HORN_BUZZER, OUTPUT);
    digitalWrite(PIN_SIGNAL_RIGHT, LOW);
    digitalWrite(PIN_SIGNAL_LEFT, LOW);
    digitalWrite(PIN_BRAKE_LIGHT, LOW);
    digitalWrite(PIN_HORN_BUZZER, LOW);
    applyHeadlight(0);
  }

  void setMode(HeadlightMode mode, uint8_t brightnessPercent) {
    mode_ = mode;
    brightness_ = brightnessPercent;
    blinkOn_ = true;
    lastBlinkAt_ = millis();
    applyForCurrentState();
  }

  void setSignal(SignalMode mode) {
    signalMode_ = mode;
    signalBlinkOn_ = true;
    lastSignalBlinkAt_ = millis();
    applySignalForCurrentState();
  }

  void setBrake(bool on) {
    brakeOn_ = on;
    digitalWrite(PIN_BRAKE_LIGHT, on ? HIGH : LOW);
  }

  bool brakeOn() const { return brakeOn_; }

  void tick() {
    tickHeadlight();
    tickSignal();
  }

  void tickHeadlight() {
    if (mode_ == HeadlightMode::kOff || mode_ == HeadlightMode::kOn) return;

    unsigned long interval = mode_ == HeadlightMode::kFlashSlow ? 600
                              : mode_ == HeadlightMode::kFlashFast
                                  ? 250
                                  : 150;  // hazard
    unsigned long now = millis();
    if (now - lastBlinkAt_ < interval) return;
    lastBlinkAt_ = now;
    blinkOn_ = !blinkOn_;
    applyForCurrentState();
  }

  void tickSignal() {
    if (signalMode_ == SignalMode::kOff) return;

    const unsigned long kSignalIntervalMs = 450;
    unsigned long now = millis();
    if (now - lastSignalBlinkAt_ < kSignalIntervalMs) return;
    lastSignalBlinkAt_ = now;
    signalBlinkOn_ = !signalBlinkOn_;
    applySignalForCurrentState();
  }

  static HeadlightMode fromWire(const String& value) {
    if (value == Proto::kLightOn) return HeadlightMode::kOn;
    if (value == Proto::kLightFlashSlow) return HeadlightMode::kFlashSlow;
    if (value == Proto::kLightFlashFast) return HeadlightMode::kFlashFast;
    if (value == Proto::kLightHazard) return HeadlightMode::kHazard;
    return HeadlightMode::kOff;
  }

  static SignalMode signalFromWire(const String& value) {
    if (value == Proto::kSignalLeft) return SignalMode::kLeft;
    if (value == Proto::kSignalRight) return SignalMode::kRight;
    if (value == Proto::kSignalHazard) return SignalMode::kHazard;
    return SignalMode::kOff;
  }

  const char* toWire() const {
    switch (mode_) {
      case HeadlightMode::kOn:
        return Proto::kLightOn;
      case HeadlightMode::kFlashSlow:
        return Proto::kLightFlashSlow;
      case HeadlightMode::kFlashFast:
        return Proto::kLightFlashFast;
      case HeadlightMode::kHazard:
        return Proto::kLightHazard;
      default:
        return Proto::kLightOff;
    }
  }

  const char* signalToWire() const {
    switch (signalMode_) {
      case SignalMode::kLeft:
        return Proto::kSignalLeft;
      case SignalMode::kRight:
        return Proto::kSignalRight;
      case SignalMode::kHazard:
        return Proto::kSignalHazard;
      default:
        return Proto::kSignalOff;
    }
  }

 private:
  void applyForCurrentState() {
    switch (mode_) {
      case HeadlightMode::kOff:
        applyHeadlight(0);
        break;
      case HeadlightMode::kOn:
        applyHeadlight((brightness_ * MOTOR_PWM_MAX) / 100);
        break;
      default:
        applyHeadlight(blinkOn_ ? MOTOR_PWM_MAX : 0);
        break;
    }
  }

  void applySignalForCurrentState() {
    bool left = false;
    bool right = false;

    if (signalBlinkOn_) {
      switch (signalMode_) {
        case SignalMode::kLeft:
          left = true;
          break;
        case SignalMode::kRight:
          right = true;
          break;
        case SignalMode::kHazard:
          left = true;
          right = true;
          break;
        default:
          break;
      }
    }

    digitalWrite(PIN_SIGNAL_LEFT, left ? HIGH : LOW);
    digitalWrite(PIN_SIGNAL_RIGHT, right ? HIGH : LOW);
  }

  void applyHeadlight(int pwm) { analogWrite(PIN_HEADLIGHT, pwm); }

  HeadlightMode mode_ = HeadlightMode::kOff;
  SignalMode signalMode_ = SignalMode::kOff;
  uint8_t brightness_ = 100;
  bool brakeOn_ = false;
  bool blinkOn_ = true;
  bool signalBlinkOn_ = true;
  unsigned long lastBlinkAt_ = 0;
  unsigned long lastSignalBlinkAt_ = 0;
};
