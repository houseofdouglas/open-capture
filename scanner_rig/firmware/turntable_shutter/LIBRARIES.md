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

## Second patch — multi-phone support (only if PHONES > 1)

The library marks itself disconnected as soon as *any* host drops, which would
stop the shutter for the remaining phones. In
`ESP32-NimBLE-Keyboard/src/BleKeyboard.cpp`, in
`onDisconnect(NimBLEServer*, NimBLEConnInfo&, int)`:

```cpp
// was: connected = false;
connected = pServer->getConnectedCount() > 0;
```

Nothing else is needed for multi-host, and `NimBLECharacteristic::notify()` with
the default handle sends "to all subscribed clients" — so one keypress fires
every paired phone.

Also lost on library update — re-add it.

### Serial monitor is blank → USB CDC On Boot

The ESP32-C3 SuperMini has **no USB-UART bridge**; it uses the C3's native USB
Serial/JTAG (it enumerates as `/dev/cu.usbmodem*`, not `cu.usbserial*`). The
board's default is `CDCOnBoot=Disabled` (`boards.txt`: `esp32c3.menu.CDCOnBoot
.default=Disabled`), which routes `Serial` to **UART0 on GPIO 20/21** — pins
with nothing attached. Upload works, the sketch runs, the monitor stays empty.

Fix: **Tools → USB CDC On Boot → Enabled**, then reflash. On the CLI:

```
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc turntable_shutter
arduino-cli upload  --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc -p /dev/cu.usbmodemXXXX turntable_shutter
```

The plain `esp32:esp32:esp32c3` FQBN silently builds with CDC off.

Also note the host enumerates the CDC port a beat *after* boot, so prints issued
immediately in `setup()` are lost even when CDC is on. The sketch waits up to
2 s for `Serial` — bounded, so the rig still runs untethered.

### Verified connection ceilings (three phones IS supported)

If a third phone won't connect, it is **not** a configured limit — checked
against what's actually installed:

| layer | setting | value |
|---|---|---|
| NimBLE-Arduino 2.5.0 | `src/nimconfig.h` | `MAX_CONNECTIONS 3`, `MAX_BONDS 3` |
| esp32 core 3.3.11 (C3) | `tools/esp32c3-libs/3.3.11/sdkconfig` | `BT_NIMBLE_MAX_CONNECTIONS=3`, `BT_NIMBLE_MAX_BONDS=3` |
| C3 BLE controller | same sdkconfig | `BT_CTRL_BLE_MAX_ACT=6` |

Note 3 is the **hard ceiling** on simultaneous connections — a 4th phone needs
`CONFIG_BT_NIMBLE_MAX_CONNECTIONS` raised in `nimconfig.h` (a patch lost on
library update).

### Why the third phone fails even though 3 connections are allowed

**This is the actual cause of "only two phones will pair."** Connection count is
not the binding limit — the **CCCD store** is.

Every bonded host stores one CCCD record per notify characteristic it subscribes
to, and NimBLE keeps them all in **one global array shared by every bond**, not
per-peer:

```c
// nimble/host/store/config/src/ble_store_config.c:47
struct ble_store_value_cccd ble_store_config_cccds[MYNEWT_VAL(BLE_STORE_MAX_CCCDS)];
```

This HID device exposes exactly **3 notify characteristics** — keyboard input
report, media-key input report (`NimBLEHIDDevice::getInputReport`, `NOTIFY`), and
battery level (`NimBLEHIDDevice.cpp:64`, `READ | NOTIFY`). So N phones need 3N
records against a default of 8:

| phones | CCCDs needed | fits in 8? |
|---|---|---|
| 2 | 6 | yes |
| 3 | 9 | **no — store overflows** |

Hence exactly two phones, every time, with no error on the ESP32 side.

### The override must target `MYNEWT_VAL_BLE_STORE_MAX_CCCDS`

`build_opt.h` (sitting next to the `.ino`; the esp32 core copies it in via a
prebuild hook and appends its lines as compiler flags) carries:

```
-DMYNEWT_VAL_BLE_STORE_MAX_CCCDS=16
-DMYNEWT_VAL_BLE_STORE_MAX_BONDS=5
```

Do **not** try to override `CONFIG_BT_NIMBLE_MAX_CCCDS` instead — it silently
does nothing. `nimconfig.h:4` does `#include "sdkconfig.h"` on `ESP_PLATFORM`,
and the core's sdkconfig defines `CONFIG_BT_NIMBLE_MAX_CCCDS=8` *unconditionally*,
clobbering any `-D`. The `MYNEWT_VAL_` alias is `#ifndef`-guarded in both places
that define it (`esp_nimble_cfg.h:989`, `syscfg.h:1104`), so a command-line
define wins there.

The bond bump to 5 is headroom, not a strict requirement: `MAX_BONDS` defaults to
3, which fits three phones *exactly* — one stale bond from a re-pair or a
retired phone and the next pairing fails.

A `static_assert` in the sketch enforces `MYNEWT_VAL_BLE_STORE_MAX_CCCDS >=
3 * PHONES`, so losing `build_opt.h` is a build error rather than a silent
regression to two phones. **Unlike the library patches above, this one lives in
the sketch folder and survives library updates.**

Verify it took effect from the RAM figure — the CCCD bump alone moves global
variables by +128 bytes (8 extra records x 16 bytes).

### Advertising must be restarted from `loop()`, not from the callback

The library stops advertising when a host connects, so phones 2 and 3 need it
restarted. Do **not** do that inside `bleKeyboard.onConnect(...)`: that callback
runs in the NimBLE host task while the connect event is still being processed,
`NimBLEDevice::startAdvertising()` returns `bool` and can fail there, and a lost
restart is unrecoverable — the next phone never sees an advertisement and you
are stuck at two phones forever.

The sketch instead calls `keepAdvertising()` every `loop()`, which restarts
advertising whenever `getConnectedCount() < PHONES` and the radio is idle, so a
failed attempt is simply retried.

For the same reason the sketch never hand-counts hosts. iOS HID pairing does
connect → bond → reconnect, so connect/disconnect callbacks do not reliably pair
up; a counter drifts, reads 3 with two phones attached, and permanently
suppresses advertising. `hostsUp()` asks the server via `getConnectedCount()`.

## Pitfalls to avoid

- **NimBLE 1.4.x + this fork** → `marked 'override', but does not override`
  (1.x callbacks lack the `NimBLEConnInfo&` param). Use NimBLE **2.x**.
- **NimBLE 2.x without the `<functional>` patch** → the `std::function` error
  above.
- **GPIO 8** for a stepper coil → it's a C3 strapping pin (and usually the
  onboard LED); can wedge boot. Sketch uses GPIO 4–7 for the coils, 9 for BOOT.
