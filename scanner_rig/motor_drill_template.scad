// ─────────────────────────────────────────────────────────────
// Motor ear-hole drill template  (for salvaging an already-printed base)
//
// Locates on TWO existing features of the printed base so it cannot shift
// or rotate while you drill:
//   • center pin  → drops into the Ø12 shaft hole (the true axis / datum)
//   • locator pin → drops into ONE existing old ear hole (Ø4.2 at 17.5,0),
//                   which pins the rotation
// It then guides a drill at the two NEW ear positions (±17.5, 7 mm off the
// old line).
//
// PRINTS as-is: plate flat on the bed, the two pins as short studs pointing
// up. No supports.
//
// USE: remove the motor. Set the base plate-side UP (the flat platter face).
// FLIP the template over so the pins point down: seat the center pin in the
// shaft hole and the locator pin in EITHER old ear hole (both work). When it
// sits flush, drill straight down through the two guide holes with a 4.4 mm
// bit (11/64").
// Deburr. Mount the motor over the NEW hole pair, ears bolted through with
// nuts inside the skirt. (The offset side is symmetric — just rotate the
// motor so its ears line up with the holes you drilled.)
// ─────────────────────────────────────────────────────────────

$fn = 64;

c2c          = 35;    // ear-hole spacing (matches turntable.scad)
perp         = 7;     // shaft → new-ear-hole line offset (matches turntable.scad)

th           = 8;     // template thickness = drill-guide length (keeps bit straight)
center_pin_d = 11.7;  // into the Ø12 shaft hole
center_pin_h = 5;
loc_pin_d    = 3.6;   // into an existing old Ø4.2 ear hole at (c2c/2, 0)
loc_pin_h    = 4;
guide_d      = 4.5;   // drill guide for the new holes (use a 4.4 mm bit)

module template() {
    difference() {
        // body plate on the bed (z = 0 .. th), rounded around all features
        hull() for (p = [[-c2c/2, 0], [c2c/2, 0], [-c2c/2, perp], [c2c/2, perp]])
            translate([p[0], p[1], 0]) cylinder(d = 16, h = th);
        // guide holes at the NEW ear positions, all the way through
        for (s = [-1, 1])
            translate([s * c2c/2, perp, -1]) cylinder(d = guide_d, h = th + 2);
    }
    // registration pins as studs on top (become the locators when flipped)
    translate([0,     0, th]) cylinder(d = center_pin_d, h = center_pin_h);
    translate([c2c/2, 0, th]) cylinder(d = loc_pin_d,    h = loc_pin_h);
}

template();
