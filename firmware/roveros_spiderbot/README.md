# ROVEROS firmware — Optimus Spiderbot (Arduino Nano)

Firmware that makes the [Optimus Spiderbot DIY
kit](https://tronic.lk/product/optimus-spiderbot-diy-kit) speak ROVEROS's
wire protocol (the `CMD:`/`DATA;`/`ACK:`/`ERROR;` frame grammar shared with
the OP0148 car — see
[`car_protocol.dart`](../../lib/services/car_protocol.dart) /
[`command_constants.dart`](../../lib/core/constants/command_constants.dart)
— plus one verb of its own, `CMD:WALK`, in
[`spider_commands.dart`](../../lib/services/spider_commands.dart)).

Unlike the OP0148, this kit ships generic — "compatible with all popular
development boards" — with no fixed MCU, radio or pin table. This firmware
targets an **Arduino Nano**, which has no Bluetooth of its own, so it needs
an add-on **BLE-serial module** (an HM-10/AT-09-class board) wired to the
Nano's UART. That module handles BLE entirely on its own; the Nano just talks
plain serial to it.

## Requirements

- Arduino IDE, with the standard **AVR Boards** package (ships by default) —
  no extra board package needed for a Nano, unlike the OP0148's ESP32 core.
- Board setting: **Arduino Nano** (pick the correct bootloader — **Old
  Bootloader** for most clone boards, if uploads fail with the default).
- Library Manager → install **Servo** (usually bundled with the IDE already)
  — nothing else here needs an external library.
- An HM-10/AT-09-class BLE-serial module, wired to two spare digital pins
  (see [`pins.h`](pins.h)) — **not** an HC-05/HC-06 classic-Bluetooth module,
  which the app cannot see at all (see the note in the main
  [README](../../README.md) about why).

## Hardware unknowns — check these before flashing

This kit isn't in hand while writing this, so three things are starting
points, not confirmed values:

1. **The BLE module's UUIDs.** [`lib/models/vehicle_kind.dart`](../../lib/models/vehicle_kind.dart)
   defaults the spider profile to the common HM-10/AT-09 service
   `0000ffe0-…`/characteristic `0000ffe1-…`. If your module advertises
   something else (check with a generic BLE scanner app), update that file.
2. **The module's baud rate and whether it exposes a connection-state pin.**
   See the comments at the top of [`ble_bridge.h`](ble_bridge.h) and
   `PIN_BLE_STATE` in [`pins.h`](pins.h).
3. **Leg geometry** — how many degrees of freedom per leg, servo mounting
   orientation, and safe travel range. [`gait.h`](gait.h)'s `GaitTuning`
   block is where all of that lives, clearly marked, once the legs are
   physically wired.

## Flashing

1. Open this folder (`roveros_spiderbot/`) in the Arduino IDE — it will load
   `roveros_spiderbot.ino` plus its `.h` tabs together.
2. Tools → Board → **Arduino Nano**; Tools → Port → the board's serial port.
3. Upload.
4. Open the Serial Monitor at 115200 baud to confirm it prints
   `ROVEROS / Optimus Spiderbot firmware starting...`.

## Pairing with the app

1. In ROVEROS, open **Settings → Vehicle → Vehicle type** and switch it to
   **Spider**.
2. Go to **Connect Vehicle** and scan. Name your BLE module something the app
   recognises as a likely match (`SPIDER`, `HM-10`, `AT-09`, … — see
   `VehicleKind.spider.nameHints` in `vehicle_kind.dart`) so it sorts to the
   top, or just look for it by whatever name it already advertises.
3. Connect. The onboard LED goes solid once the link is up (or once traffic
   has been seen recently, if `PIN_BLE_STATE` isn't wired — see
   `ble_bridge.h`).

## What's implemented

| Wire verb / frame | Behaviour |
|---|---|
| `CMD:WALK` | Sets the commanded gait direction (`DIR:FWD/BACK/LEFT/RIGHT/ROTL/ROTR`); the trot gait in `gait.h` steps toward it every loop tick. `V` (speed percent) rides along but isn't consumed by the gait yet — see Known gaps. |
| `CMD:STOP` | Immediate neutral stance, always accepted. |
| `CMD:CONFIG` | Sets the drive watchdog window (300–2000ms), same as the car. |
| `CMD:PING` | ACKed, no side effect. |
| `DATA;...` | Sent every 250ms: `STATE` always, `BAT` only if `PIN_BATTERY_SENSE` is wired. |
| Drive watchdog | Force-stops to neutral stance and sends `ERROR;CODE:7;MSG:WATCHDOG_STOP` if no `WALK`/`STOP` arrives inside the configured window while a direction is held. |

## Known gaps

- **The gait is a starting point, not a tuned one.** Trot-gait phase timing
  and per-leg hip/knee angles are placeholder values in `gait.h`'s
  `GaitTuning` block — expect to spend real bench time here once the legs
  are wired, the same way `op_car_classic_optimized.ino`'s "User tuning"
  block needs a pass for that chassis.
- **No variable speed.** `CMD:WALK`'s `V` field is parsed by the app side but
  not yet read here — every gait step runs at the same stride/cadence
  regardless of the app's speed slider. Wire it into `GaitEngine::tick` (e.g.
  scaling `kStepIntervalMs`) once the base gait is tuned.
- **No battery telemetry** unless `PIN_BATTERY_SENSE` in `pins.h` is wired to
  a resistor divider — `BAT` is never fabricated, only omitted.
- **No leg calibration command.** The car has `CMD:CAL` for motor/servo trim;
  this vehicle has no equivalent yet, since leg geometry isn't known well
  enough yet to design one. `GaitTuning`'s compile-time constants are the
  calibration surface for now.

## File map

```
roveros_spiderbot.ino   setup()/loop()
pins.h                   GPIO map (placeholder — verify against your wiring)
wire_protocol.h          Proto:: tokens + frame parse/build (mirrors the Dart side)
ble_bridge.h             SoftwareSerial bridge to the BLE-serial add-on module
gait.h                   WalkDirection + the trot gait, incl. GaitTuning
command_handler.h        Vehicle state + CMD dispatch + telemetry/watchdog
```
