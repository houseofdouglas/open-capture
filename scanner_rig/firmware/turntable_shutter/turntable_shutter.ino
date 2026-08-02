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

#include <NimBLEDevice.h>   // for startAdvertising(); BleKeyboard.h doesn't pull it in
#include <BleKeyboard.h>

BleKeyboard bleKeyboard("ScanTable", "DIY", 100);

const int PINS[4] = {4, 5, 6, 7};     // ULN2003 IN1-4 (matches the wiring note)
const int BUTTON = 9;                 // BOOT button on the ESP32-C3 SuperMini
// Avoid GPIO 8 for a coil: it's a strapping pin (and the onboard LED on most
// C3 SuperMinis), so driving it can interfere with boot. GPIO 2 and 9 are
// also strapping pins — 9 is fine as the BOOT button (it has a pull-up).

// Drives however many iPhones are actually paired, 1 up to MAX_PHONES. This is
// a ceiling, not a requirement: nothing waits for a full set, and phones may
// join or drop at any time — each run fires whichever are connected.
//   1 phone  -> move the tray between the three arc stations, 3 revolutions
//   3 phones -> one tray per station, ONE revolution captures all 144 photos
// A BLE HID notify reaches every subscribed host, so a single keypress fires
// them all; the table is stationary ~3 s per step, so sync tolerance is about a
// second, not milliseconds.
// NimBLE defaults allow 3 simultaneous connections and 3 bonds.
const int   MAX_PHONES     = 3;

// THE reason a third phone silently fails to pair. Every bonded host stores one
// CCCD record per notify characteristic it subscribes to, and NimBLE keeps them
// all in ONE global array shared by every bond:
//     ble_store_config_cccds[MYNEWT_VAL_BLE_STORE_MAX_CCCDS]   (default 8)
// This HID device exposes 3 notify characteristics — keyboard report, media-key
// report, battery level — so N phones need 3N records. Two phones fit in 8;
// three need 9 and the store overflows, so phone 3 can't subscribe.
//
// Raised to 16 by build_opt.h next to this sketch. Note it must override
// MYNEWT_VAL_BLE_STORE_MAX_CCCDS and NOT CONFIG_BT_NIMBLE_MAX_CCCDS: nimconfig.h
// includes the core's sdkconfig.h, which defines the CONFIG_ name unconditionally
// and would clobber a -D. The MYNEWT_VAL_ alias is #ifndef-guarded everywhere,
// so a command-line define wins. This assert turns a lost or ineffective
// build_opt.h into a build error rather than a 2-phone mystery.
static_assert(MYNEWT_VAL_BLE_STORE_MAX_CCCDS >= 3 * MAX_PHONES,
              "CCCD store too small for MAX_PHONES: need 3 records per phone. "
              "Check build_opt.h sits next to this .ino and defines "
              "MYNEWT_VAL_BLE_STORE_MAX_CCCDS.");
const int   PHOTOS_PER_REV = 48;      // 48 per pass; x3 passes (or x3 phones)
const long  STEPS_PER_REV  = 4096;    // 28BYJ-48, half-stepping
const int   STEP_DELAY_US  = 1200;    // slower = more torque
const int   SETTLE_MS      = 1500;    // vibration die-down before the shot
// Slack taken up before the first shot so frame 1 isn't short. ~6 deg of D-bore
// play plus gear backlash; 100 half-steps is ~8.8 deg, comfortably over it.
// Costs nothing to overshoot — it only pre-loads the mechanism.
const long  BACKLASH_STEPS = 100;
const int   EXPOSURE_MS    = 1800;    // time for iPhone to capture + save

// Never hand-count connections: iOS's HID pairing does connect → bond →
// reconnect, so connect/disconnect callbacks don't reliably pair up and a
// counter drifts. The server knows the truth — ask it.
int hostsUp() {
  NimBLEServer* s = NimBLEDevice::getServer();
  return s ? s->getConnectedCount() : 0;
}

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

void coilsOff() {                     // release the rotor (see rotateSteps)
  for (int i = 0; i < 4; i++) digitalWrite(PINS[i], LOW);
}

// Do NOT cut the coils between shots.
//
// The drive train has real lost motion: the platter's D-bore on the 28BYJ-48's
// flatted shaft gives ~6 deg of free rotation on its own (0.4 mm of clearance
// across a 3 mm flat is a tiny moment arm, so it becomes a big angle), plus the
// motor's own plastic gear backlash on top. That is up to ~80% of a 7.5 deg
// step sitting in the mechanism.
//
// Turning one direction only, that slack is taken up ONCE at the start and then
// stays taken up — but only while the rotor is held. Releasing between shots
// lets the platter settle back into the slack under friction and any imbalance
// in the object, and the next move spends part of its travel re-taking it up:
// some advances land full, others short, unpredictably. So hold position for
// the whole revolution and release only at the end.
//
// Holding costs ~200 mA per energised phase and the motor runs warm — that is
// well within its continuous rating for a ~3 minute revolution.
void rotateSteps(long n) {
  for (long i = 0; i < n; i++) stepOnce();
}

void setup() {
  Serial.begin(115200);
  // The C3 SuperMini has NO USB-UART bridge — it's native USB, so `Serial`
  // only reaches the USB port when the sketch is built with
  // "USB CDC On Boot: Enabled" (Tools menu). Left Disabled (the board
  // default) Serial goes to UART0 on GPIO 20/21 and the monitor stays blank.
  // The host also enumerates the CDC port a beat after boot, so wait for it —
  // bounded, since the rig must still run when nothing is plugged in.
  for (unsigned long t0 = millis(); !Serial && millis() - t0 < 2000; ) delay(10);
  for (int i = 0; i < 4; i++) pinMode(PINS[i], OUTPUT);
  pinMode(BUTTON, INPUT_PULLUP);
  coilsOff();

  // The library stops advertising once a host connects, so for multiple phones
  // it has to be restarted. Do NOT restart it from these callbacks: they run in
  // the NimBLE host task while the connect event is still being processed, the
  // call can fail there, and a lost restart is unrecoverable — the next phone
  // never sees an advertisement. keepAdvertising() in loop() handles it
  // instead, so a failed attempt is simply retried. Callbacks only log.
  // Pair the phones ONE AT A TIME: wait for each to report connected before
  // starting the next, otherwise they race for the same advertising slot.
  bleKeyboard.onConnect([]() {
    Serial.printf("phone connected — %d of up to %d\n", hostsUp(), MAX_PHONES);
  });
  bleKeyboard.onDisconnect([]() {
    Serial.printf("phone dropped — %d still connected\n", hostsUp());
  });

  bleKeyboard.begin();
  Serial.printf("Advertising as 'ScanTable' — pair 1 to %d iPhone(s), one at a "
                "time. Press BOOT to run with whatever is connected.\n",
                MAX_PHONES);
}

// Keep advertising alive whenever there's a free slot, retrying until it takes.
// Called every loop, so a restart that fails inside the BLE stack just gets
// tried again a moment later instead of stranding the remaining phones. Since
// this only stops at MAX_PHONES, a second or third phone can be added at any
// time — including between revolutions — without touching the firmware.
void keepAdvertising() {
  static unsigned long lastTry = 0;
  if (hostsUp() >= MAX_PHONES) return;
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  if (!adv || adv->isAdvertising()) return;
  if (millis() - lastTry < 500) return;           // don't hammer the stack
  lastTry = millis();
  Serial.printf("advertising (%d connected)\n", hostsUp());
  NimBLEDevice::startAdvertising();
}

void loop() {
  keepAdvertising();

  if (digitalRead(BUTTON) == HIGH) { delay(20); return; }
  while (digitalRead(BUTTON) == LOW) delay(10);   // wait for release

  // Run with whatever is paired — one phone is a perfectly good scan, it just
  // takes three revolutions instead of one. Only a completely empty set is an
  // error, since then the shutter would go nowhere.
  int phones = hostsUp();
  if (phones < 1) {
    Serial.println("No phone connected — pair 'ScanTable' from iPhone Bluetooth "
                   "settings, then press BOOT.");
    return;
  }

  Serial.printf("Starting revolution — firing %d phone(s) per step…\n", phones);

  // Take up the drive-train slack BEFORE the first shot, in the same direction
  // the revolution runs. Without this the first advance or two are short while
  // the backlash closes, and those frames sit at the wrong angle. These steps
  // are deliberately not counted against STEPS_PER_REV — they buy motion in the
  // mechanism, not rotation of the platter.
  rotateSteps(BACKLASH_STEPS);
  delay(SETTLE_MS);

  long remainder = STEPS_PER_REV;
  for (int shot = 0; shot < PHOTOS_PER_REV; shot++) {
    long inc = remainder / (PHOTOS_PER_REV - shot);  // distributes rounding
    remainder -= inc;
    rotateSteps(inc);
    delay(SETTLE_MS);
    // One notify reaches every subscribed host, so all phones fire together.
    bleKeyboard.write(KEY_MEDIA_VOLUME_UP);          // shutter
    int now = hostsUp();
    if (now < phones) Serial.printf("  ! phone dropped mid-run — %d left\n", now);
    Serial.printf("Shot %d/%d  (x%d phones)\n", shot + 1, PHOTOS_PER_REV, now);
    delay(EXPOSURE_MS);
  }
  coilsOff();                          // released only now the run is over
  // Report against the phones that actually fired, not a configured target.
  int done = hostsUp();
  Serial.printf("Revolution complete — %d photos captured.%s\n",
                PHOTOS_PER_REV * done,
                done >= 3 ? " All three stations covered."
                          : " Move the tray to the next station and run again.");
}
