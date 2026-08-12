# OP CAR optimized Bluetooth Classic board-test sketch

This sketch keeps the original single-character controller protocol while
making left/right steering symmetric and independently tunable.

## Upload

Open `op_car_classic_optimized.ino` in Arduino IDE, select **ESP32 Dev Module**,
and upload it. It supports both Arduino-ESP32 2.x and 3.x LEDC APIs.

## Commands

| Command | Action |
|---|---|
| `W` / `F` | Forward / backward |
| `A` / `D` | Timed, self-stopping 90-degree left / right pivot |
| `T` / `Y` | Forward-left / forward-right curve |
| `P` / `U` | Back-left / back-right curve |
| `S` | Immediate stop |
| `0`-`9`, `q` | Speed levels |
| `B` / `b` | Headlight on / off |
| `M` / `m` | Horn on / off |

## Steering calibration

`A` and `D` always use the fixed `kTimedTurnPwm`, so changing the driving speed
does not change the turn angle. Hold the controller button until the rover
self-stops; `S` remains an emergency stop and cancels the turn immediately.

Start on a flat surface with a charged battery. Mark the rover's starting
direction, send `A`, and measure the resulting angle. Calculate the corrected
time with:

```text
new left time = current left time * 90 / measured left angle
```

Example: if `kLeft90TurnMs` is `560` and the rover turns only 80 degrees, use
`560 * 90 / 80 = 630`, so set `kLeft90TurnMs` to `630`. Repeat separately for
`kRight90TurnMs`.

After the timing is correct, use gain correction only if the rover twists or
one side audibly struggles during the pivot:

- Left turn is too small: increase `kLeftTurnRightSideGain` by `0.03`.
- Left turn is too large: decrease `kLeftTurnRightSideGain` by `0.03`.
- Right turn is too small: increase `kRightTurnLeftSideGain` by `0.03`.
- Right turn is too large: decrease `kRightTurnLeftSideGain` by `0.03`.
- Rover drifts while driving straight: raise the gain of the weaker motor,
  using `kM1Gain` through `kM4Gain`, in steps of `0.02`.

Keep gains in the `0.80` to `1.20` range. If more correction is required,
check wheel drag, gearbox condition, battery voltage, and tyre grip first.

The sketch intentionally keeps M2 electrically reversed. Calibrated timing is
repeatable on the same surface and battery level, but exact angle control under
changing conditions requires wheel encoders or an IMU with feedback control.

## RoverOS app compatibility

This is a Bluetooth Classic SPP test sketch, matching the supplied character
commands. The Flutter RoverOS app uses BLE Nordic UART and framed commands, so
use `firmware/roveros_op0148/` when connecting this board to RoverOS on iOS.
