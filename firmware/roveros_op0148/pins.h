// Pin map for the Optimus OP0148 ESP32 Car Controller Board.
//
// Source: "ESP32 Car Controller Board User Guide V1.0.0", Table 1 (Pin
// configuration), cross-checked against Optimus's own BLE sample sketch in
// the same guide ("Code to Control the Optimus ESP32 Car Controller Using
// Bluetooth"). Motor pin names/values are taken verbatim from that sample
// since it is the vendor's own validated mapping of INA/INB to physical
// forward/backward rotation for this board.
#pragma once

// --- Motors (L9110S drivers, one pair of pins per motor) -------------------
// Right side = M1 (front) + M2 (rear); Left side = M3 (front) + M4 (rear).
#define PIN_M1_FORWARD 32  // Front Right
#define PIN_M1_BACKWARD 33
#define PIN_M2_FORWARD 25  // Rear Right
#define PIN_M2_BACKWARD 26
#define PIN_M3_FORWARD 27  // Front Left
#define PIN_M3_BACKWARD 14
#define PIN_M4_FORWARD 4  // Rear Left
#define PIN_M4_BACKWARD 15

// --- Lights ------------------------------------------------------------
#define PIN_SIGNAL_RIGHT 17  // SFR + SRR, active HIGH
#define PIN_SIGNAL_LEFT 19   // SFL + SRL, active HIGH
#define PIN_BRAKE_LIGHT 16   // RL1 + RL2, active HIGH
#define PIN_HEADLIGHT 23     // FL1 + FL2, active HIGH
#define PIN_HORN_BUZZER 12   // Buzzer horn, active HIGH

// --- Sensors / actuators -------------------------------------------------
#define PIN_US_TRIG 13  // HC-SR04 TRIG (US1)
#define PIN_US_ECHO 22  // HC-SR04 ECHO (US1)
#define PIN_SERVO 21    // Radar-sweep servo (SG90/MG90)

// --- Onboard status ----------------------------------------------------
#define PIN_STATUS_LED 2  // LD2, user-programmable indicator, active HIGH

// PWM duty range for analogWrite() on this core (8-bit).
#define MOTOR_PWM_MAX 255
