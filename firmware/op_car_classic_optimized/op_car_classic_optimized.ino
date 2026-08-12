#include "BluetoothSerial.h"

#if __has_include("esp_arduino_version.h")
#include "esp_arduino_version.h"
#endif

#ifndef ESP_ARDUINO_VERSION_MAJOR
#define ESP_ARDUINO_VERSION_MAJOR 2
#endif

BluetoothSerial SerialBT;

// -----------------------------------------------------------------------------
// User tuning
// -----------------------------------------------------------------------------

constexpr char kBluetoothName[] = "OP CAR";
constexpr uint32_t kPwmFrequency = 500;
constexpr uint8_t kPwmResolution = 8;
constexpr int kMaxPwm = 255;

// Increase only the gain for a motor that is measurably weaker. Keep each value
// between 0.80 and 1.20. M2's direction is handled separately below.
constexpr float kM1Gain = 1.00f;  // Front right
constexpr float kM2Gain = 1.00f;  // Rear right, physically reversed
constexpr float kM3Gain = 1.00f;  // Front left
constexpr float kM4Gain = 1.00f;  // Rear left

// A/D are self-stopping 90-degree pivot turns. Start with these values, measure
// the real angle once, then use: newMs = oldMs * 90 / measuredAngle.
constexpr int kTimedTurnPwm = 150;
constexpr uint32_t kLeft90TurnMs = 560;
constexpr uint32_t kRight90TurnMs = 560;

// These gains correct a side that is mechanically weaker in one direction.
constexpr float kLeftTurnRightSideGain = 1.00f;
constexpr float kLeftTurnLeftSideGain = 1.00f;
constexpr float kRightTurnRightSideGain = 1.00f;
constexpr float kRightTurnLeftSideGain = 1.00f;

constexpr float kCurveInsideRatio = 0.55f;

constexpr int kRampUpStep = 8;
constexpr int kRampDownStep = 16;
constexpr uint32_t kRampIntervalMs = 20;
constexpr uint32_t kIndicatorIntervalMs = 450;
constexpr bool kStopWhenBluetoothDisconnects = true;

// -----------------------------------------------------------------------------
// OP0148 pin map
// -----------------------------------------------------------------------------

constexpr uint8_t kSignalRightPin = 17;
constexpr uint8_t kSignalLeftPin = 19;
constexpr uint8_t kBrakeLightPin = 16;
constexpr uint8_t kHeadlightPin = 23;
constexpr uint8_t kHornPin = 12;

constexpr uint8_t kM1APin = 33;
constexpr uint8_t kM1BPin = 32;
constexpr uint8_t kM2APin = 26;
constexpr uint8_t kM2BPin = 25;
constexpr uint8_t kM3APin = 14;
constexpr uint8_t kM3BPin = 27;
constexpr uint8_t kM4APin = 15;
constexpr uint8_t kM4BPin = 4;

enum MotorIndex : uint8_t {
  kM1 = 0,
  kM2,
  kM3,
  kM4,
  kMotorCount,
};

struct MotorConfig {
  uint8_t pinA;
  uint8_t pinB;
  uint8_t channelA;
  uint8_t channelB;
  bool positiveUsesPinA;
  float gain;
};

// M2 intentionally uses the opposite positive direction. Do not swap it back.
constexpr MotorConfig kMotors[kMotorCount] = {
    {kM1APin, kM1BPin, 0, 1, false, kM1Gain},
    {kM2APin, kM2BPin, 2, 3, true, kM2Gain},
    {kM3APin, kM3BPin, 4, 5, false, kM3Gain},
    {kM4APin, kM4BPin, 6, 7, false, kM4Gain},
};

int speedCar = 170;
int currentMotor[kMotorCount] = {0, 0, 0, 0};
int targetMotor[kMotorCount] = {0, 0, 0, 0};

char activeMotionCommand = 'S';
bool headlightOn = false;
bool hornOn = false;
bool leftIndicatorOn = false;
bool rightIndicatorOn = false;
bool indicatorPhaseOn = false;
bool hadBluetoothClient = false;
bool timedTurnActive = false;

uint32_t lastRampAt = 0;
uint32_t lastIndicatorAt = 0;
uint32_t timedTurnStartedAt = 0;
uint32_t timedTurnDurationMs = 0;

int clampPwm(int value) {
  return constrain(value, -kMaxPwm, kMaxPwm);
}

int scaledPwm(int value, float gain) {
  return clampPwm(static_cast<int>(roundf(value * gain)));
}

void attachPwmPin(uint8_t pin, uint8_t channel) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(pin, kPwmFrequency, kPwmResolution);
#else
  ledcSetup(channel, kPwmFrequency, kPwmResolution);
  ledcAttachPin(pin, channel);
#endif
}

void writePwm(uint8_t pin, uint8_t channel, int duty) {
  duty = constrain(duty, 0, kMaxPwm);
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(pin, duty);
#else
  ledcWrite(channel, duty);
#endif
}

void writeMotor(MotorIndex index, int requestedValue) {
  const MotorConfig &motor = kMotors[index];
  const int value = scaledPwm(requestedValue, motor.gain);
  const int duty = abs(value);

  int dutyA = 0;
  int dutyB = 0;
  if (value != 0) {
    const bool useA = value > 0 ? motor.positiveUsesPinA
                                : !motor.positiveUsesPinA;
    dutyA = useA ? duty : 0;
    dutyB = useA ? 0 : duty;
  }

  writePwm(motor.pinA, motor.channelA, dutyA);
  writePwm(motor.pinB, motor.channelB, dutyB);
}

void writeAllMotors() {
  for (uint8_t i = 0; i < kMotorCount; ++i) {
    writeMotor(static_cast<MotorIndex>(i), currentMotor[i]);
  }
}

void setTargets(int m1, int m2, int m3, int m4) {
  targetMotor[kM1] = clampPwm(m1);
  targetMotor[kM2] = clampPwm(m2);
  targetMotor[kM3] = clampPwm(m3);
  targetMotor[kM4] = clampPwm(m4);
}

void setSideTargets(int right, int left) {
  setTargets(right, right, left, left);
}

bool motorsAreStopped() {
  for (uint8_t i = 0; i < kMotorCount; ++i) {
    if (currentMotor[i] != 0 || targetMotor[i] != 0) return false;
  }
  return true;
}

void updateBrakeLight() {
  digitalWrite(kBrakeLightPin, motorsAreStopped() ? HIGH : LOW);
}

void clearIndicators() {
  leftIndicatorOn = false;
  rightIndicatorOn = false;
  indicatorPhaseOn = false;
  digitalWrite(kSignalLeftPin, LOW);
  digitalWrite(kSignalRightPin, LOW);
}

void setIndicators(bool left, bool right) {
  leftIndicatorOn = left;
  rightIndicatorOn = right;
  indicatorPhaseOn = left || right;
  lastIndicatorAt = millis();
  digitalWrite(kSignalLeftPin, left ? HIGH : LOW);
  digitalWrite(kSignalRightPin, right ? HIGH : LOW);
}

void stopRobotImmediate() {
  timedTurnActive = false;
  activeMotionCommand = 'S';
  setTargets(0, 0, 0, 0);
  for (uint8_t i = 0; i < kMotorCount; ++i) currentMotor[i] = 0;
  writeAllMotors();
  clearIndicators();
  updateBrakeLight();
}

void driveForward() {
  setSideTargets(speedCar, speedCar);
  clearIndicators();
}

void driveBackward() {
  setSideTargets(-speedCar, -speedCar);
  clearIndicators();
}

void pivotLeft(int speed) {
  const int right = scaledPwm(speed, kLeftTurnRightSideGain);
  const int left = scaledPwm(-speed, kLeftTurnLeftSideGain);
  setSideTargets(right, left);
  setIndicators(true, false);
}

void pivotRight(int speed) {
  const int right = scaledPwm(-speed, kRightTurnRightSideGain);
  const int left = scaledPwm(speed, kRightTurnLeftSideGain);
  setSideTargets(right, left);
  setIndicators(false, true);
}

void startTimedTurn(char command) {
  // Some controller apps repeat a held button. Do not restart the timer when
  // the same command arrives again.
  if (timedTurnActive && activeMotionCommand == command) return;

  timedTurnActive = true;
  activeMotionCommand = command;
  timedTurnStartedAt = millis();
  timedTurnDurationMs =
      command == 'A' ? kLeft90TurnMs : kRight90TurnMs;

  if (command == 'A') {
    pivotLeft(kTimedTurnPwm);
  } else {
    pivotRight(kTimedTurnPwm);
  }

  Serial.print(command == 'A' ? "Timed left turn: " : "Timed right turn: ");
  Serial.print(timedTurnDurationMs);
  Serial.println(" ms");
}

void updateTimedTurn() {
  if (!timedTurnActive) return;
  if (millis() - timedTurnStartedAt < timedTurnDurationMs) return;

  stopRobotImmediate();
  Serial.println("Timed 90-degree turn complete");
}

void curveForwardRight() {
  const int inside = static_cast<int>(roundf(speedCar * kCurveInsideRatio));
  setSideTargets(inside, speedCar);
  setIndicators(false, true);
}

void curveForwardLeft() {
  const int inside = static_cast<int>(roundf(speedCar * kCurveInsideRatio));
  setSideTargets(speedCar, inside);
  setIndicators(true, false);
}

void curveBackwardRight() {
  const int inside = static_cast<int>(roundf(speedCar * kCurveInsideRatio));
  setSideTargets(-inside, -speedCar);
  setIndicators(false, true);
}

void curveBackwardLeft() {
  const int inside = static_cast<int>(roundf(speedCar * kCurveInsideRatio));
  setSideTargets(-speedCar, -inside);
  setIndicators(true, false);
}

void applyMotionCommand(char command) {
  if (command == 'A' || command == 'D') {
    startTimedTurn(command);
    updateBrakeLight();
    return;
  }

  timedTurnActive = false;
  activeMotionCommand = command;
  switch (command) {
    case 'W':
      driveForward();
      break;
    case 'F':
      driveBackward();
      break;
    case 'Y':
      curveForwardRight();
      break;
    case 'T':
      curveForwardLeft();
      break;
    case 'U':
      curveBackwardRight();
      break;
    case 'P':
      curveBackwardLeft();
      break;
    default:
      stopRobotImmediate();
      break;
  }
  updateBrakeLight();
}

int rampToward(int current, int target) {
  // Never reverse an H-bridge directly. First ramp to zero, then accelerate
  // in the requested direction on a later update.
  int safeTarget = target;
  if ((current > 0 && target < 0) || (current < 0 && target > 0)) {
    safeTarget = 0;
  }

  if (current == safeTarget) return current;

  const bool slowing = abs(safeTarget) < abs(current);
  const int step = slowing ? kRampDownStep : kRampUpStep;
  if (current < safeTarget) return min(current + step, safeTarget);
  return max(current - step, safeTarget);
}

void updateMotors() {
  const uint32_t now = millis();
  if (now - lastRampAt < kRampIntervalMs) return;
  lastRampAt = now;

  for (uint8_t i = 0; i < kMotorCount; ++i) {
    currentMotor[i] = rampToward(currentMotor[i], targetMotor[i]);
  }
  writeAllMotors();
  updateBrakeLight();
}

void updateIndicators() {
  const uint32_t now = millis();
  if (now - lastIndicatorAt < kIndicatorIntervalMs) return;
  lastIndicatorAt = now;
  indicatorPhaseOn = !indicatorPhaseOn;
  digitalWrite(kSignalLeftPin,
               leftIndicatorOn && indicatorPhaseOn ? HIGH : LOW);
  digitalWrite(kSignalRightPin,
               rightIndicatorOn && indicatorPhaseOn ? HIGH : LOW);
}

void setSpeedFromCommand(char command) {
  static constexpr int kSpeedLevels[] = {
      100, 115, 130, 145, 160, 175, 190, 205, 220, 235};
  speedCar = command == 'q' ? 255 : kSpeedLevels[command - '0'];

  // Make a speed-button change effective while a direction button is held.
  if (!timedTurnActive && activeMotionCommand != 'S') {
    applyMotionCommand(activeMotionCommand);
  }
}

void processCommand(char command) {
  if (command == '\r' || command == '\n' || command == ' ') return;

  Serial.print("Bluetooth command: ");
  Serial.println(command);

  if ((command >= '0' && command <= '9') || command == 'q') {
    setSpeedFromCommand(command);
    return;
  }

  switch (command) {
    case 'W':
    case 'F':
    case 'A':
    case 'D':
    case 'Y':
    case 'T':
    case 'U':
    case 'P':
      applyMotionCommand(command);
      break;
    case 'S':
    case 's':
      stopRobotImmediate();
      break;
    case 'B':
      headlightOn = true;
      digitalWrite(kHeadlightPin, HIGH);
      break;
    case 'b':
      headlightOn = false;
      digitalWrite(kHeadlightPin, LOW);
      break;
    case 'M':
      hornOn = true;
      digitalWrite(kHornPin, HIGH);
      break;
    case 'm':
      hornOn = false;
      digitalWrite(kHornPin, LOW);
      break;
    default:
      break;
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(kSignalRightPin, OUTPUT);
  pinMode(kSignalLeftPin, OUTPUT);
  pinMode(kBrakeLightPin, OUTPUT);
  pinMode(kHeadlightPin, OUTPUT);
  pinMode(kHornPin, OUTPUT);

  digitalWrite(kSignalRightPin, LOW);
  digitalWrite(kSignalLeftPin, LOW);
  digitalWrite(kBrakeLightPin, HIGH);
  digitalWrite(kHeadlightPin, LOW);
  digitalWrite(kHornPin, LOW);

  for (uint8_t i = 0; i < kMotorCount; ++i) {
    attachPwmPin(kMotors[i].pinA, kMotors[i].channelA);
    attachPwmPin(kMotors[i].pinB, kMotors[i].channelB);
  }
  stopRobotImmediate();

  if (!SerialBT.begin(kBluetoothName)) {
    Serial.println("ERROR: Bluetooth Classic failed to start");
  } else {
    Serial.println();
    Serial.println("================================");
    Serial.println(" ROVEROS BOARD TEST READY");
    Serial.print(" Bluetooth Classic: ");
    Serial.println(kBluetoothName);
    Serial.println("================================");
  }
}

void loop() {
  const bool hasBluetoothClient = SerialBT.hasClient();
  if (kStopWhenBluetoothDisconnects && hadBluetoothClient &&
      !hasBluetoothClient) {
    stopRobotImmediate();
    hornOn = false;
    digitalWrite(kHornPin, LOW);
    Serial.println("Bluetooth disconnected: emergency stop");
  }
  hadBluetoothClient = hasBluetoothClient;

  while (SerialBT.available() > 0) {
    processCommand(static_cast<char>(SerialBT.read()));
  }

  updateTimedTurn();
  updateMotors();
  updateIndicators();

  // Keep latched accessories deterministic if another function changes a pin.
  digitalWrite(kHeadlightPin, headlightOn ? HIGH : LOW);
  digitalWrite(kHornPin, hornOn ? HIGH : LOW);
}
