// Range helpers shared by motor math, settings validation and telemetry
// parsing. Kept typed (rather than using `num.clamp`) so callers never leak a
// `num` into an `int` field.

int clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

double clampDouble(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

/// Clamp to the signed motor range used everywhere in the app.
int clampMotor(int value) => clampInt(value, -100, 100);

/// Clamp to an unsigned 0–100 percentage.
int clampPercent(int value) => clampInt(value, 0, 100);

double clampUnit(double value) => clampDouble(value, -1, 1);

/// Linear interpolation, with [t] clamped so callers cannot overshoot.
double lerpDouble(double a, double b, double t) =>
    a + (b - a) * clampDouble(t, 0, 1);

/// Map [value] from one range to another, clamped to the output range.
double mapRange(
  double value,
  double inMin,
  double inMax,
  double outMin,
  double outMax,
) {
  if (inMax == inMin) return outMin;
  final normalized = (value - inMin) / (inMax - inMin);
  return clampDouble(outMin + normalized * (outMax - outMin), outMin, outMax);
}
