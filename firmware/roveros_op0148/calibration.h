// Persisted calibration + watchdog config, pushed from the app via
// `CMD:CAL` and `CMD:CONFIG` (see lib/services/car_protocol.dart) and applied
// here so both manual driving (app-calibrated already) and firmware-owned
// autonomous driving use the same corrections.
//
// Defaults mirror AppSettings.defaults in lib/models/settings.dart so a
// freshly-flashed board behaves the same as a freshly-installed app before
// the two have ever exchanged a CAL/CONFIG frame.
#pragma once

#include <Preferences.h>

struct Calibration {
  bool invertLeft = false;
  bool invertRight = false;
  int8_t trimLeft = 0;   // -25..25, percent
  int8_t trimRight = 0;
  uint8_t servoCenter = 90;  // 0..180
  uint8_t servoMin = 0;
  uint8_t servoMax = 180;
  uint16_t commandTimeoutMs = 750;  // AppConfig.defaultCommandTimeoutMs
};

class CalibrationStore {
 public:
  void begin() {
    prefs_.begin("roveros", /*readOnly=*/false);
    data_.invertLeft = prefs_.getBool("invL", data_.invertLeft);
    data_.invertRight = prefs_.getBool("invR", data_.invertRight);
    data_.trimLeft = prefs_.getChar("trimL", data_.trimLeft);
    data_.trimRight = prefs_.getChar("trimR", data_.trimRight);
    data_.servoCenter = prefs_.getUChar("svCenter", data_.servoCenter);
    data_.servoMin = prefs_.getUChar("svMin", data_.servoMin);
    data_.servoMax = prefs_.getUChar("svMax", data_.servoMax);
    data_.commandTimeoutMs =
        prefs_.getUShort("timeout", data_.commandTimeoutMs);
  }

  const Calibration& get() const { return data_; }

  void setMotorCalibration(bool invL, bool invR, int8_t trimL, int8_t trimR) {
    data_.invertLeft = invL;
    data_.invertRight = invR;
    data_.trimLeft = trimL;
    data_.trimRight = trimR;
    prefs_.putBool("invL", invL);
    prefs_.putBool("invR", invR);
    prefs_.putChar("trimL", trimL);
    prefs_.putChar("trimR", trimR);
  }

  void setServoCalibration(uint8_t center, uint8_t minAngle,
                            uint8_t maxAngle) {
    data_.servoCenter = center;
    data_.servoMin = minAngle;
    data_.servoMax = maxAngle;
    prefs_.putUChar("svCenter", center);
    prefs_.putUChar("svMin", minAngle);
    prefs_.putUChar("svMax", maxAngle);
  }

  void setCommandTimeout(uint16_t timeoutMs) {
    data_.commandTimeoutMs = timeoutMs;
    prefs_.putUShort("timeout", timeoutMs);
  }

 private:
  Preferences prefs_;
  Calibration data_;
};
