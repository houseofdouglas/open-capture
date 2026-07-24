// BLE camera-shutter test — flashed directly to the Uno R4 WiFi's onboard
// ESP32-S3 connectivity module (NOT the main Renesas RA4M1).
//
// The Uno R4 WiFi's WiFi/BLE coprocessor IS a standalone ESP32-S3, wired to
// its own USB-JTAG/Serial port. Putting it into download mode and flashing
// it directly (bypassing the RA4M1) turns it into a normal ESP32-S3 dev
// board for as long as this sketch is on it — good for validating the BLE
// keyboard shutter trick from firmware/turntable_shutter before committing
// to the ESP32-C3 SuperMini.
//
// Board:   ESP32S3 Dev Module (Arduino IDE, board package "esp32")
// Library: "ESP32 BLE Keyboard" by T-vK (same as turntable_shutter)
//
// ENTER DIRECT-FLASH MODE (see the official Arduino tutorial for the exact
// header/pin diagram: docs.arduino.cc/tutorials/uno-r4-wifi/esp32-upload):
//   1. Unplug the board.
//   2. Short GND to the "Download" pin on the 3x2 header near the USB-C
//      connector (silkscreen-labelled) with a jumper wire.
//   3. Plug in USB while shorted — it should enumerate as
//      "USB JTAG/serial debug unit", NOT the normal Uno R4 port.
//   4. Remove the jumper, select board "ESP32S3 Dev Module" and that new
//      port, then upload this sketch as usual.
//   5. Unplug/replug once more to reboot into the sketch normally.
//
// RESTORE normal Uno R4 WiFi behaviour afterward (WiFiS3, etc.) via
// Arduino IDE: Tools > Firmware Updater > UNO R4 WiFi > Check Updates.
// The RA4M1 (running uno_r4_stepper_test.ino via the main USB port) is
// completely unaffected by any of this — the two chips are independent.
//
// Use: open Serial Monitor at 115200 baud on the new JTAG/serial port.
// Pair "ScanTable-Test" from the iPhone's Bluetooth settings, open the
// Camera app, then type 's' + Enter to fire the shutter (volume-up
// keypress). Kept as a separate device name from the real "ScanTable" so
// the two don't collide in your iPhone's paired-devices list.

#include <BleKeyboard.h>

BleKeyboard bleKeyboard("ScanTable-Test", "DIY", 100);

void setup() {
  Serial.begin(115200);
  bleKeyboard.begin();
  Serial.println("Advertising as 'ScanTable-Test' — pair from the iPhone.");
  Serial.println("Type 's' + Enter to fire the shutter once connected.");
}

void loop() {
  if (Serial.available() && Serial.read() == 's') {
    if (!bleKeyboard.isConnected()) {
      Serial.println("Not paired yet — connect from iPhone Bluetooth settings.");
    } else {
      bleKeyboard.write(KEY_MEDIA_VOLUME_UP);
      Serial.println("Shutter fired.");
    }
  }
}
