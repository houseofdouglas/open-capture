# Automated Photogrammetry Scanning Rig

Motorized turntable + tilting iPhone 16 Pro cradle for Object Capture
scans. The ESP32 rotates the table and triggers the iPhone shutter over
Bluetooth (it emulates a volume-up keypress — the native Camera app's
shutter). One button press = one full revolution of evenly spaced photos.

## Bill of materials

| Item | Qty | Notes |
|---|---|---|
| 28BYJ-48 stepper + ULN2003 driver | 1 | sold as a pair, ~$4 |
| ESP32-C3 SuperMini | 1 | 22.52 x 18 mm, 2.54 mm pitch headers |
| 608ZZ bearings (skateboard) | 3 | platter support rollers |
| (printed axle x3) | 3 | snap-in bearing axles — no rod/bolt needed |
| M4 x 8 screws + nuts | 2 | motor ears, bolted through the hub (nut underneath) |
| Zip ties | 2 | lash the ULN2003 board to a spoke |
| M4 x 12 screws | 3 | 2 pivots + 1 angle-lock pin (self-tap into tray bosses) |
| M4 x 12 screws | 4 | crossbars, through each wing into the bar ends (self-tap) |
| M4 x 12 screws | 6 | roller brackets, up through the plate (self-tap into bracket feet) |
| USB cable + 5 V supply | 1 | powers ESP32 and motor |
| Cork or rubber sheet, ~175 mm disc | 1 | optional platter grip, glued to the top face |

## Print

All parts print without supports. PLA or PETG, 3–4 walls, ~25% infill.
PETG note: drive the self-tapping M4 screws slowly — PETG grips hard and
can crack a boss if forced; the pilot holes are sized 3.6 mm for it.

The wing is 238 x 312 mm, so print the two **one at a time** — they won't fit
side by side on a 350 mm bed. Use a brim: it's a long, thin, flat PETG part and
the corners are the most likely thing to lift.

The base is a lightweight spoked frame (motor hub + bracket ring + 3 spokes
+ 3 feet) — about half the filament of a solid disc. Set `solid_base = true`
in `turntable.scad` if you'd rather have the fully enclosed disc + skirt.

| File | Part | Orientation |
|---|---|---|
| `turntable.scad` | `motor_test` (`stl/turntable_motor_test.stl`) | OPTIONAL: dry-fit the motor first (see below) |
| `turntable.scad` | `base_print` (`stl/turntable_base_print.stl`) | pre-flipped: plate face down, skirt up |
| `turntable.scad` | `bracket` x3 (`stl/turntable_bracket.stl`) | foot down |
| `turntable.scad` | `axle` x3 (`stl/turntable_axle.stl`) | flange on the bed, tip up |
| `turntable.scad` | `platter` | **upside down** (hub boss up) — or use `platter_print` / `stl/turntable_platter_print.stl`, which is pre-flipped |
| `phone_cradle.scad` | `tray` | flat on its back |
| `phone_cradle.scad` | `wing` x2 (`stl/cradle_arc_wing.stl`) | flat (238 x 312 x 6) |
| `phone_cradle.scad` | `crossbar` x2 (`stl/cradle_arc_crossbar.stl`) | flat |
| `phone_cradle.scad` | `shim` x2 (`stl/cradle_arc_shim.stl`) | only for taller objects — see below |

(`stand` is the older flat stand — superseded by the arc wings, see below.)
| `header_pin_jig.scad` (`stl/header_pin_jig.stl`) | OPTIONAL: solder the ESP32-C3 SuperMini's header pins | flat on the bed |

Export from the CLI: `openscad -o platter.stl -D 'part="platter"' turntable.scad`
(pre-exported copies are in `stl/`).

**Soldering the SuperMini's header pins:** print `header_pin_jig.scad`. Snap
two 1x8 segments off a standard break-away header strip and push each,
long-pin-down, into a row of the jig's holes until the plastic shoulder
sits flat on top — same as plugging them into a breadboard. The short pins
now point up ~2.5 mm; lower the SuperMini (component side up) so its two
rows of through-holes slide over them, tack-solder one corner pin per row,
check it sits flat and square, then solder the rest from the top.

Dry-fit before reprinting the base: print `motor_test` and check that
(1) the shaft passes through the center hole, (2) the body drops into the
recess and can rotate freely to any angle, and (3) both ear bolts pass
through the holes with the ears flat. If an ear is off, tweak `mount_c2c`
(spacing) or `mount_perp` (offset) and reprint the coupon until it fits —
then the full base is guaranteed right.

Key parameters to check before printing:

- `turntable.scad` → `shaft_len`: measure your motor's shaft protrusion
  above the mounting flange (typically ~10 mm).
- `phone_cradle.scad` → `fit` / `phone_t`: bump to ~2.0 / case thickness
  if the phone wears a case.
- `phone_cradle.scad` → `obj_h`: where the arc aims — the height of the object's
  **centre** above the table, `69 + objectHeight/2`. Default 101 targets a 64 mm
  object (the 2x sweet spot). **You don't need a wing per object size** — see
  One stand, any object size below.
- `phone_cradle.scad` → `cam_R`: camera-to-object distance. Leave at 200 mm and
  change **zoom** rather than geometry to handle different object sizes — see
  Framing below. This sets the size of the wings, so pick it before printing.

## Why the stand is an arc

Tilting the tray only changes where the camera *aims*, not where it *is*. A
cradle fixed at object height shooting 40° down aims at the tabletop in front
of the object. To shoot down at θ and keep the object centred and the same size
in frame, the camera has to ride an arc of constant radius about the object
centre:

```
y = cam_R·cos θ        z = obj_h + cam_R·sin θ        tilt = θ
```

Higher **and** closer as θ grows. Besides framing, that's also what keeps the
stand short — reaching 65° on an arc needs 271 mm of height, but a straight
column 200 mm back would need **519 mm**:

| elevation | arc: dist / height | straight column: height |
|---|---|---|
| 15° | 193 mm / 142 mm | 144 mm |
| 40° | 153 mm / 219 mm | 258 mm |
| 65° | 85 mm / 271 mm | 519 mm |

The wings' three pivot stations sit on that arc, each with a lock hole that
sets the matching tilt, so the geometry can't be set wrong. Verified in CAD:
the tray clears the wings and crossbars at all three stations, and the stand
stays stable (worst-case CG 23 mm inside the front foot).

## Assemble

**Reusing an already-printed base** (motor and bracket-screw holes moved in
this revision — you do NOT need to reprint the big base): the safest way to
locate the new holes is to use the parts themselves as drill templates.
- Motor: print `motor_drill_template.scad` (`stl/motor_drill_template.stl`).
  Flip it onto the flat plate face — its center pin drops into the shaft
  hole and its locator pin into an old ear hole, fixing position AND
  rotation. Drill through the two guides with a 4.4 mm bit. Old holes stay
  unused. (More precise than free-hand marking through the ears.)
- Brackets: centre a new (reprinted) bracket over each old hole pair, mark
  through its two foot holes, drill Ø4.4. This puts the screws fore & aft
  of the bearing where they belong.
Only the **brackets** must be reprinted (the old ones bury the bearing on
the foot and put screws under it). The platter is fine as-is; reprint it
only if shaft engagement feels shallow.

1. Mount the motor: shaft up through the center hole, body in the recess.
   The 28BYJ-48 shaft is OFFSET from the body centre, so the recess is
   oversized and centred on the shaft — rotate the motor so its two ears
   lie over the bolt holes, then bolt through with M4 x 8 + nuts. (The
   motor carries no load, it only turns the platter, so light retention
   is enough.)
2. Drop a 608ZZ into each bracket's gap and push a printed `axle` through
   from the outer tab — barb first — until it clicks past the far tab and
   the flange seats flush. The bearing spins on the shaft; no rod or bolt
   needed. Screw the three brackets to the plate top with M4 x 12 from
   underneath — the two screws sit fore & aft of the bearing so they can't
   foul it, and the foot is relieved beneath the bearing so the outer race
   spins free.
3. Press the platter's hub onto the D-shaft; its rim rests on the bearings.
   The platter's weight sits on the three bearings, not the motor shaft.
4. Bolt the tray between the uprights (M4 pivots through the big holes,
   self-tapping into the tray bosses). The third M4 through an arc hole
   into the tray's lock hole sets the tilt. Both long walls are relieved
   so the phone's side buttons never get pressed — slide the phone in
   under the two retaining tabs; either orientation works. The window
   is sized so the camera island passes through it and the phone seats
   on the flat glass around it (rather than rocking on the lenses).
5. Wire the ULN2003 (IN1/2/3/4 → GPIO 4/5/6/7, 5 V, GND) and zip-tie the
   board to one of the spokes; the motor and wiring hang in the open frame
   below the platter.

   Bring-up tip: if you want to check the motor and coil wiring before
   committing to the ESP32, `firmware/uno_r4_stepper_test/` runs the same
   coil sequence on an Arduino Uno R4 (IN1-4 → D8-D11) — press a button on
   D2, or type `r` in Serial Monitor, for one revolution. Once that spins
   smoothly, move IN1-4 to the ESP32 GPIOs above and flash
   `turntable_shutter` for real.

   Have a Uno R4 **WiFi**? Its connectivity module is itself a standalone
   ESP32-S3 with its own USB-JTAG/Serial port — `firmware/uno_r4_esp32s3_shutter_test/`
   can be flashed directly onto it (bypassing the RA4M1 main chip entirely)
   to test the BLE-keyboard shutter trick before wiring up the SuperMini.
   See that file's header comment for how to enter direct-flash mode.

## One stand, any object size

`obj_h` is baked into the wings, but it only fixes where the arc *aims*. What
actually matters is the height difference between the wings' base and the object
centre — so change that with a shim instead of reprinting a stand:

```
shim = (object height)/2 + 69 − obj_h      (69 = platter top above the desk)
```

- **positive** → spacer under both wings (`shim` part; set `shim_rise`, print 2)
- **negative** → riser under the object, on the platter (any disc of that height)

At the default `obj_h = 101`:

| object height | shim |
|---|---|
| 20 mm | 22 mm riser under the object |
| 40 mm | 12 mm riser under the object |
| **64 mm** | **none — exact** |
| 80 mm | 8 mm under the wings |
| 100 mm | 18 mm under the wings |
| 130 mm | 33 mm under the wings |
| 160 mm | 48 mm under the wings |

And you can ignore the shim entirely over a useful range, because the object just
sits slightly off-centre in frame rather than badly misaimed: **no shim needed
for 43–85 mm objects at 2x, or 23–105 mm at 1x** (the wider 1x frame is more
forgiving). Only reach for a shim outside those bands.

## Framing — how much of the frame the object should fill

Apple's rule is "maximize the portion of the field of view capturing the
object", but "each image should contain the entirety of the object". For a
turntable that needs one extra constraint: **the object rotates**, so you have
to frame its *widest* rotational profile, not the width you happen to see when
setting up.

**Target ~65% of the short (vertical) frame dimension at the object's widest
rotation.** Spin the platter a full turn by hand and confirm nothing clips.

- Below ~50%: throwing away resolution.
- Above ~80%: the object clips on some rotations, and it sits in the
  lens-distortion zone at the frame edges. Clipped frames cost more than the
  extra detail gains.

At `cam_R = 200 mm`, the vertical frame is almost exactly the camera distance
at 1x, and half that at 2x:

| zoom | vertical frame | detail | 65% fill = object |
|---|---|---|---|
| **1x** (24 mm eq, 24 MP) | 199 mm | 21 px/mm | **130 mm** |
| **2x** (48 mm eq, 12 MP) | 100 mm | 30 px/mm | **65 mm** |

So one printed stand covers roughly **50–160 mm** objects just by switching
zoom — and 2x actually resolves *more* detail per mm than 1x, because it's a
true sensor crop of the 48 MP main camera (not interpolation). Smaller objects
still work at reduced fill: a 30 mm object at 2x is ~900 px across, plenty for
a good mesh. Avoid the 5x lens — it's a separate camera with a much longer
minimum focus distance.

**Keep the zoom locked and identical for all 144 shots** of a session, along
with focus and exposure — Apple asks for consistent focal length, shutter,
aperture and ISO across the set. Never change zoom mid-session.

### Aligning the lens with the turntable axis

The arc is centred on the tray's pivot, but the iPhone's rear lens is **not** at
the centre of the phone — the camera island sits near one end, roughly 45–50 mm
off centre along the phone's long axis. In landscape that offset is sideways, so
if you line the *stand* up with the turntable axis, the object lands well off
centre in the frame (~14° off axis at 200 mm — near the edge at 2x).

Fix at setup, no parts change: **slide the turntable sideways until the object
is centred in the camera preview**, then mark the spot. Aligning the lens (not
the stand) with the platter axis also makes the camera-to-object distance
exactly `cam_R`. There's a smaller ~9 mm vertical offset too; nudge the
turntable or `obj_h` if the object sits high or low in frame.

Overlap is already comfortable: 48 shots/revolution = 7.5° steps ≈ 96% overlap
between adjacent frames (Apple's minimum is 70%), and 3 orbits × 48 = 144
images (Apple's minimum is 100).

## Scan workflow

1. Flash `firmware/turntable_shutter/` (Arduino IDE, ESP32 board package,
   "ESP32 BLE Keyboard" library). Pair **ScanTable** in iPhone Bluetooth
   settings.
2. Place the turntable ~25–35 cm in front of the cradle (object should
   fill ~70% of the frame; use 2x at ~50 cm for small objects). Even,
   diffuse lighting on all sides — your lighting kit, or a light tent.
   Matte-coat shiny objects (dry shampoo / scanning spray).
3. Open the Camera app, lock focus/exposure (long-press → AE/AF LOCK).
4. Tray on the lowest arc station (15°) → press the ESP32 button → 48 photos.
   Move the tray's 3 screws to the 40° station, repeat; then 65°. ≈144 photos.
   Set `obj_h` so the arc is centred on your object, and re-check framing at
   the first station — all three stations then frame identically.
5. AirDrop the photos to the Mac and reconstruct:

   ```sh
   ./photogrammetry ./photos ./model.usdz -d full -f high
   ```

6. Blender: import USDZ → voxel remesh → selective smooth → fix
   non-manifold → scale check → export STL → slice.

Note: turntable scans defeat Object Capture's automatic background
separation only if the background is textured. Use a plain featureless
backdrop (paper sweep) so the only thing that appears to move is the
object — this is what the plain platter and backdrop are for.
