// Stepper bring-up test: 28BYJ-48 via ULN2003, on an Arduino Uno R4.
//
// Standalone wiring/motor check before moving to the ESP32 — same coil
// sequence, step count, and timing as firmware/turntable_shutter, so once
// the motor turns smoothly and the direction looks right here, the wiring
// carries straight over (just move IN1-4 to the ESP32 GPIOs in that
// sketch's header comment).
//
// Board:   Arduino Uno R4 (Minima or WiFi), Arduino IDE
// Library: none — direct digitalWrite coil stepping, no AccelStepper/etc.
//
// Wiring (ULN2003 driver board):
//   IN1 -> D8      IN2 -> D9
//   IN3 -> D10     IN4 -> D11
//   Driver VCC -> 5V, GND -> GND
//   Optional pushbutton: D2 -> GND (uses the internal pull-up)
//
// Use: open Serial Monitor at 115200 baud. Press the button on D2, or type
// 'r' + Enter, to run one full revolution. Type '+' / '-' to speed up /
// slow down (adjusts STEP_DELAY_US), 'x' to reverse direction.

const int PINS[4]  = {8, 9, 10, 11};
const int BUTTON   = 2;              // to GND, INPUT_PULLUP

const long STEPS_PER_REV = 4096;     // 28BYJ-48, half-stepping
int        stepDelayUs   = 1200;     // slower = more torque
bool       reversed      = false;

// half-step sequence
const uint8_t SEQ[8] = {0b1000, 0b1100, 0b0100, 0b0110,
                        0b0010, 0b0011, 0b0001, 0b1001};
long stepIndex = 0;

void stepOnce() {
  stepIndex = (stepIndex + (reversed ? 7 : 1)) % 8;
  for (int i = 0; i < 4; i++)
    digitalWrite(PINS[i], (SEQ[stepIndex] >> (3 - i)) & 1);
  delayMicroseconds(stepDelayUs);
}

void coilsOff() {                    // don't cook the motor between runs
  for (int i = 0; i < 4; i++) digitalWrite(PINS[i], LOW);
}

void rotateOneRev() {
  Serial.println("Rotating one revolution...");
  for (long i = 0; i < STEPS_PER_REV; i++) stepOnce();
  coilsOff();
  Serial.println("Done.");
}

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < 4; i++) pinMode(PINS[i], OUTPUT);
  pinMode(BUTTON, INPUT_PULLUP);
  coilsOff();
  Serial.println("Stepper bring-up ready.");
  Serial.println("Button D2, or 'r' = one revolution | '+'/'-' = speed | 'x' = reverse");
}

void loop() {
  if (Serial.available()) {
    char c = Serial.read();
    if (c == 'r') {
      rotateOneRev();
    } else if (c == '+') {
      stepDelayUs = max(300, stepDelayUs - 100);
      Serial.print("STEP_DELAY_US = "); Serial.println(stepDelayUs);
    } else if (c == '-') {
      stepDelayUs += 100;
      Serial.print("STEP_DELAY_US = "); Serial.println(stepDelayUs);
    } else if (c == 'x') {
      reversed = !reversed;
      Serial.print("Direction: "); Serial.println(reversed ? "reversed" : "normal");
    }
  }

  if (digitalRead(BUTTON) == LOW) {
    while (digitalRead(BUTTON) == LOW) delay(10);  // wait for release
    rotateOneRev();
  }
}
