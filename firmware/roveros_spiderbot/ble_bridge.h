// UART bridge to an HM-10/AT-09 class BLE-serial add-on module.
//
// The Arduino Nano has no radio of its own — this class only shuffles bytes
// over a SoftwareSerial port to a module that speaks BLE on the Nano's
// behalf. Compare with ../roveros_op0148/ble_link.h, which runs a full BLE
// GATT server directly on the ESP32: there is no equivalent stack to wrap
// here, just a serial line the module bridges to its BLE characteristic.
//
// The exact module in this kit isn't known yet — HM-10/AT-09 clones vary in
// their factory baud rate and whether they break out a connection-state pin.
// 9600 baud is the common factory default; check yours (many are configured
// over the same serial link with `AT` commands) and update kBaudRate below
// if it's different.
#pragma once

#include <Arduino.h>
#include <SoftwareSerial.h>

#include <functional>

#include "pins.h"
#include "wire_protocol.h"

class BleBridge {
 public:
  using LineHandler = std::function<void(const String&)>;

  void begin(LineHandler onLine) {
    onLine_ = onLine;
    port_.begin(kBaudRate);
#if PIN_BLE_STATE >= 0
    pinMode(PIN_BLE_STATE, INPUT);
#endif
  }

  /// Must be called every loop() iteration. Unlike the ESP32's BLE stack,
  /// nothing here is interrupt- or callback-driven — bytes only move when
  /// this is called.
  void poll() {
    while (port_.available() > 0) {
      char c = (char)port_.read();
      lastRxAt_ = millis();
      if (c == Proto::kTerminator) {
        if (buffer_.length() > 0 && onLine_) onLine_(buffer_);
        buffer_ = "";
        continue;
      }
      if (buffer_.length() < Proto::kMaxFrameLength) buffer_ += c;
    }
  }

  void send(const String& frame) { port_.print(frame); }

  bool isConnected() const {
#if PIN_BLE_STATE >= 0
    return digitalRead(PIN_BLE_STATE) == HIGH;
#else
    // No STATE pin wired: infer the link is up from recent traffic instead.
    // Good enough for the status LED; it is not load-bearing for safety —
    // the drive watchdog in command_handler.h stops the gait on its own if
    // commands stop arriving, regardless of what this reports.
    return millis() - lastRxAt_ < kAssumeConnectedWindowMs;
#endif
  }

 private:
  static constexpr long kBaudRate = 9600;
  static constexpr unsigned long kAssumeConnectedWindowMs = 3000;

  SoftwareSerial port_{PIN_BLE_RX, PIN_BLE_TX};
  LineHandler onLine_;
  String buffer_;
  unsigned long lastRxAt_ = 0;
};
