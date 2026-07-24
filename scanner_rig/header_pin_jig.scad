// ─────────────────────────────────────────────────────────────
// Header-pin soldering jig for the ESP32-C3 SuperMini
//
// Holds two 1x8 male header strips upright at the SuperMini's exact
// pin spacing so the board drops straight onto them for soldering —
// the same trick as plugging headers into a breadboard, just shaped
// for this one board so there's nothing to eyeball.
//
// Board mechanical spec (from the SuperMini datasheet): 22.52 x 18 mm,
// two rows of 8 pins, 2.54 mm pitch, rows 15.24 mm apart (0.6" — the
// same breadboard-spanning spacing as an Arduino Nano).
//
// USE: snap two 1x8 segments off a standard 2.54 mm break-away header
// strip. Push each strip LONG-pin-down into a row of holes until the
// plastic shoulder sits flat on the jig's top face — exactly how the
// strip would sit in a breadboard. The SHORT pins now point up above
// the jig by ~2.5 mm. Lower the SuperMini (component side up) onto
// them so its two rows of through-holes slide over the short pins.
// Tack-solder one corner pin on each row first, check the board sits
// flat and square, then solder the rest from the top. Lift the board
// off the jig (friction fit only, no glue) once cool.
//
// PRINTS as-is, flat on the bed, no supports.
// ─────────────────────────────────────────────────────────────

$fn = 32;

pins_per_row = 8;      // SuperMini header pin count per row
pitch        = 2.54;   // header pin pitch
row_spacing  = 15.24;  // row-to-row spacing (0.6", from datasheet)

margin       = 4;      // block margin beyond the outermost pin holes
corner_r     = 3;      // corner rounding
th           = 8.5;    // block thickness ~= header long-pin length, for full-depth grip
hole_d       = 1.0;    // friction-fit hole for 0.64 mm square header pins
                        // (ream to ~1.1-1.2 mm with a drill bit if too tight off your printer)
chamfer_d    = 1.8;    // top countersink so pins guide in easily
chamfer_h    = 0.6;

row_len   = (pins_per_row - 1) * pitch;
block_len = row_len + 2 * margin;
block_wid = row_spacing + 2 * margin;

module block_shape(h) {
    hull()
        for (x = [-1, 1], y = [-1, 1])
            translate([x * (block_len/2 - corner_r), y * (block_wid/2 - corner_r), 0])
                cylinder(r = corner_r, h = h);
}

module header_pin_jig() {
    difference() {
        block_shape(th);
        for (r = [-1, 1])
            for (i = [0 : pins_per_row - 1])
                translate([-row_len/2 + i * pitch, r * row_spacing/2, -1]) {
                    cylinder(d = hole_d, h = th + 2);
                    translate([0, 0, th - chamfer_h])
                        cylinder(d1 = hole_d, d2 = chamfer_d, h = chamfer_h + 1);
                }
    }
}

header_pin_jig();
