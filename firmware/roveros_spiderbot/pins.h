// Pin map for the Optimus Spiderbot on an Arduino Nano.
//
// Unlike the OP0148 car (an Optimus board with a documented, fixed pinout),
// this kit ships generic — "compatible with all popular development boards"
// — so there is no vendor pin table to transcribe. Every value here is a
// reasonable starting point on a Nano, not a confirmed wiring: check it
// against how the kit is actually assembled before flashing.
//
// Leg servo pins live in gait.h's GaitTuning block instead of here, next to
// the other values that need bench tuning together.
#pragma once

// --- BLE bridge (SoftwareSerial to an HM-10/AT-09 class add-on module) -----
// The Nano has no radio of its own — see ble_bridge.h.
#define PIN_BLE_RX 2  // Nano RX  <- module TX
#define PIN_BLE_TX 8  // Nano TX  -> module RX

// Wire the module's STATE/connection-status pin here if it breaks one out
// (many HM-10 clones do, some AT-09 boards don't). Set to -1 if not wired;
// the bridge then infers "connected" from recent traffic instead.
#define PIN_BLE_STATE -1

// --- Onboard status ----------------------------------------------------
#define PIN_STATUS_LED LED_BUILTIN  // Nano's onboard LED (D13)

// --- Optional battery sense (not wired by default — see README) -----------
// A resistor divider from the pack into a free analog pin, if you add one.
// Leave at -1 to keep DATA;BAT omitted rather than fabricated.
#define PIN_BATTERY_SENSE -1
