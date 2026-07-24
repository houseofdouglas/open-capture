// Automated scanning turntable: 28BYJ-48 via ULN2003 + BLE camera shutter.
//
// The ESP32 advertises as a Bluetooth keyboard. iOS treats a volume-up
// keypress as the shutter button while the Camera app is open, so each
// cycle is: rotate one increment -> settle -> snap.
//
// Board:   ESP32-C3 SuperMini (Arduino IDE, board package "esp32",
//          board "ESP32C3 Dev Module")
// Library: "ESP32-NimBLE-Keyboard" (wakwak-koba fork) + "NimBLE-Arduino".
//          The classic T-vK "ESP32 BLE Keyboard" uses Bluedroid and PANICS
//          at begin() on the ESP32-C3 (null deref in NimBLE HID setup, MTVAL
//          0x2c). The NimBLE fork is a drop-in — same <BleKeyboard.h> and
//          same API — but runs on the stack the C3 actually supports.
//          Install: Library Manager → "NimBLE-Arduino"; then add the fork
//          from https://github.com/wakwak-koba/ESP32-NimBLE-Keyboard
//          (Sketch → Include Library → Add .ZIP Library). Remove/avoid the
//          T-vK library so its BleKeyboard.h isn't picked up instead.
//
// Wiring (ULN2003 driver board):
//   IN1 -> GPIO 4      IN2 -> GPIO 5
//   IN3 -> GPIO 6      IN4 -> GPIO 7
//   Driver VCC -> 5V, GND -> GND
//
// NOTE: this targets the ESP32-C3 SuperMini specifically, not a classic
// ESP32 WROOM board. GPIO 18/19 aren't broken out on the C3 (used
// internally for native USB), so the stepper moved to GPIO 4-7. The
// onboard BOOT button is wired to GPIO9 on the C3 (a strapping pin) —
// GPIO0 has no button behind it on this board.
//
// Use: pair "ScanTable" in iPhone Bluetooth settings, open the Camera
// app, frame the object, press the ESP32 BOOT button to run one full
// revolution. Re-tilt the cradle, press again for the next orbit.

#include <BleKeyboard.h>

BleKeyboard bleKeyboard("ScanTable", "DIY", 100);

const int PINS[4] = {4, 5, 6, 7};     // ULN2003 IN1-4 (matches the wiring note)
const int BUTTON = 9;                 // BOOT button on the ESP32-C3 SuperMini
// Avoid GPIO 8 for a coil: it's a strapping pin (and the onboard LED on most
// C3 SuperMinis), so driving it can interfere with boot. GPIO 2 and 9 are
// also strapping pins — 9 is fine as the BOOT button (it has a pull-up).

const int   PHOTOS_PER_REV = 48;      // 3 orbits x 48 = 144 photos
const long  STEPS_PER_REV  = 4096;    // 28BYJ-48, half-stepping
const int   STEP_DELAY_US  = 1200;    // slower = more torque
const int   SETTLE_MS      = 1500;    // vibration die-down before the shot
const int   EXPOSURE_MS    = 1800;    // time for iPhone to capture + save

// half-step sequence
const uint8_t SEQ[8] = {0b1000, 0b1100, 0b0100, 0b0110,
                        0b0010, 0b0011, 0b0001, 0b1001};
long stepIndex = 0;

void stepOnce() {
  stepIndex = (stepIndex + 1) % 8;
  for (int i = 0; i < 4; i++)
    digitalWrite(PINS[i], (SEQ[stepIndex] >> (3 - i)) & 1);
  delayMicroseconds(STEP_DELAY_US);
}

void coilsOff() {                     // don't cook the motor between shots
  for (int i = 0; i < 4; i++) digitalWrite(PINS[i], LOW);
}

void rotateSteps(long n) {
  for (long i = 0; i < n; i++) stepOnce();
  coilsOff();
}

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < 4; i++) pinMode(PINS[i], OUTPUT);
  pinMode(BUTTON, INPUT_PULLUP);
  coilsOff();
  bleKeyboard.begin();
  Serial.println("Advertising as 'ScanTable' — pair from the iPhone.");
}

void loop() {
  if (digitalRead(BUTTON) == HIGH) { delay(20); return; }
  while (digitalRead(BUTTON) == LOW) delay(10);   // wait for release

  if (!bleKeyboard.isConnected()) {
    Serial.println("Not paired yet — connect from iPhone Bluetooth settings.");
    return;
  }

  Serial.println("Starting revolution…");
  long remainder = STEPS_PER_REV;
  for (int shot = 0; shot < PHOTOS_PER_REV; shot++) {
    long inc = remainder / (PHOTOS_PER_REV - shot);  // distributes rounding
    remainder -= inc;
    rotateSteps(inc);
    delay(SETTLE_MS);
    bleKeyboard.write(KEY_MEDIA_VOLUME_UP);          // shutter
    Serial.printf("Shot %d/%d\n", shot + 1, PHOTOS_PER_REV);
    delay(EXPOSURE_MS);
  }
  Serial.println("Revolution complete. Re-tilt the cradle for the next orbit.");
}
