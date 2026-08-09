# ROVEROS

A premium, dashboard-style Flutter app for controlling a DIY ESP32-based 4WD
smart robot car over Bluetooth Low Energy — built to feel like an EV control
console and an RC transmitter, not a bare-bones Arduino remote.

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue">
  <img alt="flutter" src="https://img.shields.io/badge/Flutter-3.44-02569B">
  <img alt="tests" src="https://img.shields.io/badge/tests-100%20passing-brightgreen">
</p>

---

## What this is

ROVEROS pairs with an ESP32 rover over BLE, drives it with an analog virtual
joystick, and surfaces live telemetry (battery, distance, servo angle, motor
output) on a dark, high-contrast dashboard. It also runs a fully autonomous
**mock rover** with no hardware attached, so the whole app — including its
safety behaviour — can be built, demoed, and tested without a soldering iron.

## Hardware target

| Component | Role |
|---|---|
| ESP32 "Optimus" controller board | Central MCU, BLE peripheral |
| 4× TT geared DC motor + driver | Differential drive |
| 2× 18650 Li-ion | Power |
| HC-SR04 | Front obstacle distance |
| SG90 9g servo | Sweeps the HC-SR04 for the radar view |
| White LED headlights | Solid / flash / hazard, ESP32-timed |

**The phone never makes a safety decision.** Motor stop logic, the
communication watchdog, and autonomous obstacle-avoidance decisions all live
on the ESP32. The app only sends high-level commands and displays what the
vehicle reports back — see [Safety model](#safety-model) below.

## Screens

| Screen | Orientation | Purpose |
|---|---|---|
| Splash | Portrait | Boot sequence: load settings, check saved vehicle, animate in |
| Home | Portrait | Vehicle status, battery, readiness, recent activity, START DRIVING |
| Connect | Portrait | BLE scan/connect/reconnect, connection-quality detail |
| **Drive** | **Landscape** | Joystick, speed, emergency stop, lights, distance, servo/radar preview |
| Auto | Portrait | MANUAL / OBSTACLE AVOIDANCE / AUTO SCAN, live radar, vehicle decisions |
| Telemetry | Portrait | Full dashboard: every reported value, link health, last ACK, errors |
| Settings | Portrait | Vehicle, controls, motors, sensors, lights, connection, app preferences |

## Getting started

```bash
flutter pub get
flutter run                # Mock mode is on by default — no hardware needed
```

Mock mode is enabled out of the box (Settings → App → **Mock car mode**), so
`flutter run` gets you a fully interactive simulated rover immediately:
connect, drive, watch the battery drain under load, trigger obstacle
avoidance, and inject faults, all without an ESP32 in the room.

To drive real hardware, turn **Mock car mode** off in Settings. The app then
scans for BLE devices exposing the Nordic UART Service (the de-facto BLE
serial profile most ESP32 Arduino sketches use) — see
[`lib/core/constants/app_config.dart`](lib/core/constants/app_config.dart) for
the service/characteristic UUIDs your firmware needs to expose.

### Requirements

- Flutter 3.44+ / Dart 3.12+ (`environment: sdk: ^3.12.2` in `pubspec.yaml`)
- Android: minSdk 24, targetSdk 36 (BLE central role needs API 23+)
- iOS: Bluetooth usage descriptions are already set in `Info.plist`

### Building

```bash
flutter build apk --debug     # or --release with your own signing config
flutter build ios             # requires Xcode + a valid provisioning profile
```

The debug Android build uses debug signing so `flutter run --release` works
out of the box; wire up real release signing in `android/app/build.gradle.kts`
before shipping to a store.

## Testing

```bash
flutter test        # 100 tests: protocol, motor math, safety, layout metrics
flutter analyze      # zero warnings
```

Coverage focuses on what actually breaks a robot: differential-drive math,
dead-zone and speed-limit clamping, accel/decel ramping, command
serialisation/validation, telemetry parsing (including malformed and
out-of-range frames), emergency stop, disconnect handling, and the firmware
watchdog — exercised end-to-end against `MockTransport`, not just asserted in
isolation.

## Architecture

```
lib/
  core/          theme, constants, router, pure utils (motor math, throttle,
                 clamp, validation), Riverpod bootstrap providers
  models/        strongly-typed domain types (Telemetry, Settings, Commands,
                 ConnectionState, Vehicle) — no protocol strings, no widgets
  services/      car_protocol.dart (the ONLY place that builds/parses wire
                 frames), storage_service.dart, transport/ (the abstraction)
  features/      one folder per screen: screen + controller (Riverpod
                 Notifier) + local widgets/
  widgets/       the shared UI kit (AppButton, AppCard, TelemetryCard, …)
```

**Transport abstraction.** `Transport` is a single interface
(`connect/disconnect/send/subscribe/scan`) implemented by both
`BluetoothTransport` (flutter_blue_plus) and `MockTransport` (a simulated
ESP32 with its own watchdog, telemetry stream, and injectable faults). The UI
and `DriveController` depend only on this interface, so mock and real
hardware are interchangeable behind one `transportProvider`.

**Protocol.** Every wire token lives in
[`command_constants.dart`](lib/core/constants/command_constants.dart); every
frame is built or parsed exclusively by
[`car_protocol.dart`](lib/services/car_protocol.dart)
(`buildDriveCommand`, `buildStopCommand`, `parseTelemetry`, `parseAck`,
`parseError`, `validateCommand`, …). No widget ever touches a raw command
string.

**State.** Riverpod `Notifier`s split communication state
(`ConnectionController`, holding the `LinkState`) from commanded/UI state
(`DriveController`, holding the `DriveState`) from vehicle-reported truth
(`TelemetryController`). Settings persist through `StorageService`
(SharedPreferences) and are re-validated on every load.

## Safety model

1. **The ESP32 owns the stop.** It runs its own communication watchdog — if
   no valid drive command arrives within a configurable window (sent via
   `CMD:CONFIG;TIMEOUT:ms`, default 750ms), it cuts the motors itself. The app
   never has to succeed at sending a message for the vehicle to stop safely.
2. **Release-to-stop bypasses everything.** Letting go of the joystick sends
   `CMD:STOP` immediately, ungated by throttling or acceleration ramping.
3. **Leaving Drive, backgrounding the app, or losing the link** all trigger an
   immediate stop attempt and clear the commanded output client-side.
4. **Emergency stop latches.** It requires a deliberate second tap to release
   — a twitching thumb can't immediately re-arm the motors.
5. **Autonomous decisions happen on the vehicle.** The phone only sends
   `CMD:MODE`/`CMD:SCAN` and displays `telemetry.decision`; a reported sensor
   or motor fault automatically drops the app out of autonomous mode.
6. **Drive commands are throttled and epsilon-filtered** (≤15/s, changes below
   a small threshold are skipped) so the radio is never flooded — but a
   transition to or from a full stop is never suppressed.

## Known limitations

- Bluetooth has only been exercised against `MockTransport` in this
  environment; `BluetoothTransport` compiles and follows the Nordic UART
  Service convention, but pairing with real ESP32 firmware has not been
  hardware-verified here.
- No CI pipeline is configured — `flutter analyze` / `flutter test` /
  `flutter build apk` are run manually (see [Testing](#testing)).
- Release signing for Android/iOS is left to the maintainer.
