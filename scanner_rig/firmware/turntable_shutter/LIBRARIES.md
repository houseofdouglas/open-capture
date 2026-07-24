# Firmware library setup (turntable_shutter)

Records the exact toolchain that compiles `turntable_shutter.ino` cleanly for
the **ESP32-C3 SuperMini**. Reproduce this on a fresh machine and the sketch
builds (verified: `arduino-cli compile --fqbn esp32:esp32:esp32c3`, exit 0).

## Versions

| Component | Version | Notes |
|---|---|---|
| ESP32 Arduino core (`esp32:esp32`) | **3.3.11** | NimBLE 2.x requires core 3.x |
| NimBLE-Arduino | **2.5.0** | https://github.com/h2zero/NimBLE-Arduino |
| ESP32-NimBLE-Keyboard (fork) | commit **1f3a88a** | https://github.com/wakwak-koba/ESP32-NimBLE-Keyboard |

Board in Arduino IDE: **ESP32C3 Dev Module** (FQBN `esp32:esp32:esp32c3`).

## Why not the usual library

The common **T-vK `ESP32 BLE Keyboard`** (Bluedroid) **panics at boot** on the
ESP32-C3 — `Guru Meditation … Load access fault`, null deref (MTVAL 0x2c) in
NimBLE HID setup during `bleKeyboard.begin()`. It's a documented C3
incompatibility. The NimBLE fork above is a drop-in (same `<BleKeyboard.h>`
and API, incl. `KEY_MEDIA_VOLUME_UP`) but runs on the stack the C3 supports.

## Install

1. Arduino IDE Library Manager → install **NimBLE-Arduino 2.5.x**.
2. Install the keyboard fork (no releases — clone master):
   ```
   git clone https://github.com/wakwak-koba/ESP32-NimBLE-Keyboard.git \
     ~/Documents/Arduino/libraries/ESP32-NimBLE-Keyboard
   ```
3. **Remove/move out** the T-vK `ESP32-BLE-Keyboard` so its `BleKeyboard.h`
   isn't picked up instead. (Ours is parked in
   `~/Documents/Arduino/_disabled_libraries/`.)

## Required patch (one line)

The fork's master uses `std::function` without including it, which NimBLE
1.4.x pulled in transitively but 2.x does not. Without this, the build fails
with `'function' in namespace 'std' does not name a template type`.

In `ESP32-NimBLE-Keyboard/src/BleKeyboard.h`, after `#include <Print.h>`, add:

```cpp
#include <functional>   // for std::function (Callback); not transitive on NimBLE 2.x
```

**This patch is lost if the library is updated/re-cloned — re-add the line.**

## Pitfalls to avoid

- **NimBLE 1.4.x + this fork** → `marked 'override', but does not override`
  (1.x callbacks lack the `NimBLEConnInfo&` param). Use NimBLE **2.x**.
- **NimBLE 2.x without the `<functional>` patch** → the `std::function` error
  above.
- **GPIO 8** for a stepper coil → it's a C3 strapping pin (and usually the
  onboard LED); can wedge boot. Sketch uses GPIO 4–7 for the coils, 9 for BOOT.
