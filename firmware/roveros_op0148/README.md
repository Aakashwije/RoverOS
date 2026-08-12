# ROVEROS firmware — Optimus OP0148 ESP32 Car Controller Board

Firmware that makes the OP0148 board speak ROVEROS's exact BLE protocol
(Nordic UART Service + the `CMD:`/`DATA;`/`ACK:`/`ERROR;` frame grammar in
[`car_protocol.dart`](../../lib/services/car_protocol.dart) /
[`command_constants.dart`](../../lib/core/constants/command_constants.dart)).
Having the board is not enough on its own — this is the piece that was
missing.

## Requirements

- Arduino IDE, with the **esp32 by Espressif Systems** board package
  installed (Boards Manager → search `esp32`) — same as the OP0148's own
  User Guide.
- Board setting: **ESP32 Dev Module**.
- Library Manager → install **ESP32Servo** (by Kevin Harrington /
  madhephaestus). Everything else (`BLEDevice`, `Preferences`) ships with the
  esp32 core.

## Flashing

1. Open this folder (`roveros_op0148/`) in the Arduino IDE — it will load
   `roveros_op0148.ino` plus its `.h` tabs together.
2. Tools → Board → **ESP32 Dev Module**; Tools → Port → the board's serial
   port (micro-USB, CH340).
3. Upload.
4. Open the Serial Monitor at 115200 baud to confirm it prints
   `BLE advertising as ROVEROS-OPTIMUS`.

## Pairing with the app

1. In ROVEROS, open **Settings → App** and turn **Mock car mode** off.
2. Go to **Connect Vehicle** and scan — the board advertises as
   `ROVEROS-OPTIMUS`, which matches the app's `OPTIMUS`/`ROVER` name hints
   ([`app_config.dart`](../../lib/core/constants/app_config.dart)) and sorts
   to the top of the list.
3. Connect. `LD2` (the onboard status LED) goes solid once the BLE link is
   up.

Wiring the motors/servo/HC-SR04/lights to the board's connectors is exactly
what the OP0148 User Guide already documents (`M1`–`M4`, `SERVO`, `US1`,
`FL1`/`FL2`, `RL1`/`RL2`) — this firmware doesn't change any of that.

## What's implemented

| Wire verb / frame | Behaviour |
|---|---|
| `CMD:DRIVE` | Differential drive across all four motors (M1+M2 = right, M3+M4 = left). Already calibrated by the app before it's sent — see below. |
| `CMD:STOP` | Immediate zero, always accepted regardless of drive mode. |
| `CMD:SPEED` | Stored and echoed in telemetry; also caps the AVOID-mode cruise speed. |
| `CMD:LIGHT` | Front headlights (`FL1`+`FL2`) — `OFF`/`ON`(+brightness)/`FLASH_SLOW`/`FLASH_FAST`/`HAZARD`, timed on-device. |
| `CMD:SIGNAL` | Side signals — `LEFT` drives `SFL`+`SRL`, `RIGHT` drives `SFR`+`SRR`, `HAZARD` drives all four, timed on-device. |
| `CMD:SERVO` | Direct radar-servo aim, clamped to the calibrated min/max. |
| `CMD:MODE` | `MANUAL` / `AVOID` / `SCAN`, each stopping the motors and resetting the radar sweep on entry. |
| `CMD:SCAN` | Independent radar sweep control (`AUTO`/`ONCE`/`OFF`), usable in `MANUAL` too. |
| `CMD:CONFIG` | Sets and persists the drive watchdog window (300–2000ms). |
| `CMD:TESTMOTOR` | Bench-test one side (or both) at a raw percent, for wiring/calibration checks. |
| `CMD:CAL` | Persists motor invert/trim and servo centre/min/max (`Preferences`, survives reboot). |
| `CMD:PING` | ACKed, no side effect. |
| `DATA;...` | Sent ~every 150ms: `DIST`, `SERVO`, `SPD`, `L`, `R`, `MODE`, `LIGHT`, `SIGNAL`, `BRAKE`, `STATE`, and `DEC` while avoiding. |
| Drive watchdog | Manual-mode only (autonomous modes drive the motors every loop tick regardless of the phone). Force-stops and sends `ERROR;CODE:7;MSG:WATCHDOG_STOP` if nothing follows a drive command inside the configured window. |

Calibration split: the app already applies trim/inversion/speed-ceiling to
`CMD:DRIVE` client-side before sending it
([`motor_math.dart`](../../lib/core/utils/motor_math.dart)), so this firmware
executes manual `DRIVE` frames as-is. `CMD:CAL` exists so the **firmware's
own** autonomous driving (`AVOID` mode) applies the same corrections when
there's no app in the loop deciding L/R.

## Known gaps

- **No battery telemetry.** The OP0148's documented pinout has no
  battery-voltage-sense ADC pin, so `BAT` is never sent rather than
  fabricated. If you wire a resistor divider to a free ADC pin (e.g. one of
  the line-sensor pins, if unused), add an `addInt(Proto::kKeyBattery, ...)`
  call to `buildTelemetryFrame()` in `command_handler.h`.
- **Obstacle-avoidance threshold is a firmware constant** (`kThresholdCm` in
  `autonomy.h`, 25cm), not the app's `minObstacleDistanceCm` setting — the
  wire protocol currently has no field carrying it from the app.
- **The buzzer, the line-hunting sensor input, and the NRF24L01 connector**
  are present on the board but unused here — the ROVEROS protocol has no
  commands addressing them yet.
- **Obstacle avoidance is a minimal reference behaviour** (drive forward,
  reverse briefly, pivot, repeat) — tune `autonomy.h`'s `ObstacleAvoider`
  constants for your chassis.

## File map

```
roveros_op0148.ino    setup()/loop(), mode scheduling, telemetry timer
pins.h                 GPIO map (User Guide Table 1)
wire_protocol.h         Proto:: tokens + frame parse/build (mirrors the Dart side)
calibration.h           Preferences-backed CAL/CONFIG storage
motors.h                Differential drive over the L9110S pins
lights.h                Headlight mode state machine + brake light
sensors.h               HC-SR04 + radar servo drivers
autonomy.h              RadarSweep (SCAN) and ObstacleAvoider (AVOID)
ble_link.h              Nordic UART Service BLE server
command_handler.h        Vehicle state + CMD dispatch + telemetry/watchdog
```
