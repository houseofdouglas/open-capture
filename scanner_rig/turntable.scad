// ─────────────────────────────────────────────────────────────
// Motorized scanning turntable
// Direct-drive 28BYJ-48 stepper; platter weight carried by
// three 608ZZ skateboard bearings so the motor only turns it.
//
// Print "base" and "platter" separately (set `part` below or
// use -D 'part="base"' from the CLI). Platter prints upside
// down (hub boss up). No supports needed for either part.
// ─────────────────────────────────────────────────────────────

part = "assembly"; // ["assembly", "base", "base_print", "motor_test", "bracket", "axle", "platter", "platter_print"]
// Print: base_print (x1), bracket (x3), platter_print (x1).
// Brackets bolt on with 2x M4x10 each, inserted from under the plate
// (heads end up inside the skirt cavity). All parts support-free.

$fn = 120;

/* [Platter] */
platter_d    = 200;  // fits well within a 350 mm bed; raise if you like
platter_t    = 6;
platter_lift = 26;   // platter underside above base plate top (set by roller size)
grip_recess  = 0;    // optional cork-disc recess depth on the top face.
                     // Leave 0: the platter prints top-face-down, and any
                     // recess becomes an air gap under the first layer.

/* [Base] */
solid_base = false;  // false = lightweight spoked frame (~half the filament)
plate_t = 5;
skirt_h = 32;        // leg/skirt height: motor-body clearance under the plate
base_d  = 210;       // (solid_base only) full disc + skirt diameter
skirt_t = 4;         // (solid_base only) skirt wall thickness

/* [Lightweight frame] */
hub_d   = 58;        // central motor hub (clears the Ø47 recess + ear holes)
ring_ri = 68;        // bracket ring inner radius
ring_ro = 92;        // bracket ring outer radius (brackets bolt on at r=80)
spoke_w = 22;        // width of the 3 hub→ring spokes
leg_r   = 80;        // radius of the 3 feet (sit between the brackets)
leg_x   = 18;        // foot size, radial
leg_y   = 26;        // foot size, tangential

/* [Support rollers — 608ZZ bearings] */
roller_r = 80;       // radius of the ring the bearings support
brg_od   = 22;
brg_w    = 7;
axle_d   = 8.2;      // clearance for an M8 bolt or 8 mm rod
tab_t    = 5;
brg_clr  = 0.8;
foot_t   = 4;        // bracket foot thickness (at the screw pads)
foot_y   = 15;       // half-length of the foot; screws live in the ends
screw_y  = 11;       // screw holes sit fore & aft of the Ø22 bearing, clear
                     // of it, with a full 2.2 mm wall of foot all around the
                     // hole (bearing only grazes the foot near its centre)
screw_clr = 4.4;     // clearance holes in the plate (M4)
screw_tap = 3.6;     // self-tap holes in the bracket foot pads (PETG-proven)

/* [Motor — 28BYJ-48 with OFFSET shaft] */
// Values below are MEASURED and validated by the motor_test coupon fitting
// this specific motor (body Ø28.7, ~19 mm tall). The shaft is offset from
// the body centre; the recess is centred on the shaft and oversized so the
// body drops in and rotates freely to align the ears.
shaft_len   = 10;    // shaft length beyond the flange face
shaft_d     = 5.4;   // clearance bore for the 5 mm shaft
shaft_flats = 3.4;   // clearance across the 3 mm flats
recess_t    = 2.5;   // flange recess depth in the plate underside
motor_shaft_offset = 8;   // shaft axis → body centre (recess sizing)
recess_d    = 2*(motor_shaft_offset + 14) + 3; // Ø47 — coupon-validated fit for the Ø28.7 body
mount_c2c   = 35;    // ear-hole spacing — MEASURED (ears centered on shaft)
mount_perp  = 7;     // shaft axis → the ear-hole line — MEASURED
mount_d     = 4.2;   // M4 clearance; ears bolt through with nuts underneath

shaft_above_plate = shaft_len - (plate_t - recess_t);
brg_center_h      = platter_lift - brg_od / 2;

module tube(od, wall, h) {
    difference() {
        cylinder(d = od, h = h);
        translate([0, 0, -0.5]) cylinder(d = od - 2 * wall, h = h + 1);
    }
}

// One bolt-on roller bracket: axle along local X (radial when placed),
// bearing rolls tangentially. Prints foot-down, no supports.
module roller_bracket() {
    gap = brg_w + brg_clr;
    w = gap + 2 * tab_t;             // tangential extent
    difference() {
        union() {
            translate([-w / 2, -foot_y, 0]) cube([w, 2 * foot_y, foot_t]);   // foot
            for (s = [-1, 1])
                translate([s * (gap / 2 + tab_t / 2), 0, 0])
                    hull() {
                        translate([-tab_t / 2, -12, foot_t - 1]) cube([tab_t, 24, 1]);
                        translate([0, 0, brg_center_h])
                            rotate([0, 90, 0]) cylinder(d = axle_d + 7, h = tab_t, center = true);
                    }
        }
        // axle bore
        translate([0, 0, brg_center_h])
            rotate([0, 90, 0]) cylinder(d = axle_d, h = w + 2, center = true);
        // clearance pocket so the bearing OD spins free of the foot. Only
        // needs to span the narrow band where the bearing grazes the foot
        // (±7 mm); beyond that the round bearing has curved clear on its own.
        translate([-3.8, -7, 1.5]) cube([7.6, 14, foot_t]);
        // screw holes fore & aft of the bearing, in the solid foot ends
        for (s = [-1, 1])
            translate([0, s * screw_y, -1]) cylinder(d = screw_tap, h = foot_t + 2);
    }
}

// Holes shared by both base styles: shaft clearance, motor recess, ear
// bolts, and the three bracket screw pairs.
module base_holes() {
    cylinder(d = 12, h = 4 * plate_t, center = true);                  // shaft clearance
    // motor flange recess — oversized & centred so the offset body seats
    // flat no matter how the motor is rotated to align its ears
    translate([0, 0, -plate_t - 0.01]) cylinder(d = recess_d, h = recess_t + 0.01);
    // ear bolt holes (through-holes; nut underneath)
    for (s = [-1, 1])
        translate([s * mount_c2c / 2, mount_perp, -plate_t - 1])
            cylinder(d = mount_d, h = plate_t + 2);
    // bracket screw clearance holes, 2 per bracket at 0/120/240
    for (a = [0, 120, 240], s = [-1, 1])
        rotate([0, 0, a])
            translate([roller_r, s * screw_y, -plate_t - 1])
                cylinder(d = screw_clr, h = plate_t + 2);
}

module base() { if (solid_base) base_solid(); else base_light(); }

// Lightweight spoked frame: motor hub + bracket ring + 3 spokes + 3 feet.
// Feet and spokes sit at 60/180/300 (between the brackets at 0/120/240).
module base_light() {
    difference() {
        union() {
            translate([0, 0, -plate_t]) cylinder(d = hub_d, h = plate_t);   // motor hub
            translate([0, 0, -plate_t]) difference() {                       // bracket ring
                cylinder(d = 2 * ring_ro, h = plate_t);
                translate([0, 0, -1]) cylinder(d = 2 * ring_ri, h = plate_t + 2);
            }
            for (a = [60, 180, 300]) rotate([0, 0, a]) {
                translate([0, -spoke_w / 2, -plate_t]) cube([ring_ro, spoke_w, plate_t]); // spoke
                translate([leg_r - leg_x / 2, -leg_y / 2, -plate_t - skirt_h])            // foot
                    cube([leg_x, leg_y, skirt_h + 0.01]);
            }
        }
        base_holes();
        // zip-tie slots on one spoke to lash the ULN2003 board
        for (dy = [-1, 1])
            rotate([0, 0, 60]) translate([42, dy * 7, -plate_t - 1])
                cylinder(d = 3.5, h = plate_t + 2);
    }
}

// Original enclosed disc + skirt (heavier). Set solid_base = true to use.
module base_solid() {
    union() {
        difference() {
            translate([0, 0, -plate_t]) cylinder(d = base_d, h = plate_t);
            base_holes();
        }
        difference() {
            translate([0, 0, -plate_t - skirt_h]) tube(base_d, skirt_t, skirt_h);
            rotate([0, 0, 60])
                translate([base_d / 2 - skirt_t - 1, -15, -plate_t - skirt_h - 0.5])
                    cube([skirt_t + 4, 30, 22]);
        }
    }
}

// Small test coupon: just the motor hub, to dry-fit the motor and confirm
// the measured shaft hole, recess, and ear-hole positions before committing
// to a full base reprint. Prints flat with the recess opening UP (no bridge),
// which is also the handy way to drop the motor in and check the fit.
module motor_test() {
    difference() {
        cylinder(d = hub_d, h = plate_t);                              // hub disc on the bed
        translate([0, 0, -1]) cylinder(d = 12, h = plate_t + 2);       // shaft clearance
        translate([0, 0, plate_t - recess_t])                          // recess, opening up
            cylinder(d = recess_d, h = recess_t + 1);
        for (s = [-1, 1])                                              // ear bolt holes
            translate([s * mount_c2c / 2, mount_perp, -1])
                cylinder(d = mount_d, h = plate_t + 2);
    }
}

/* [Printed bearing axle] */
axle_shaft_d = 7.8;  // rides in the 608 Ø8 bore, slips the Ø8.2 tab bores
axle_flg_d   = 13;   // flange plate that seats flush against the outer tab
axle_flg_t   = 2.5;
axle_barb_d  = 8.7;  // snaps past the far tab (bore 8.2); reduce if too stiff
axle_play    = 0.3;  // axial float once seated
axle_slot_w  = 2;    // flex slot that lets the barbed tip compress on the way in

// Self-retaining printed axle: flange one end, barbed snap tip the other, so
// it needs no rod or bolt. Prints vertically, flange on the bed (the small
// downward catch ledge is a minor overhang, no supports). Insert barb-first:
// push through the outer tab, the bearing, and the far tab until the barb
// clicks out past the far tab and the flange seats on the near tab.
module axle() {
    gap = brg_w + brg_clr;            // bearing gap between the tabs
    span = gap + 2 * tab_t;           // full bracket width the axle crosses
    barb_h = 3.2;
    slot_len = 13;
    tip_top = axle_flg_t + span + axle_play + barb_h;
    difference() {
        union() {
            cylinder(d = axle_flg_d, h = axle_flg_t);                     // flange plate
            translate([0, 0, axle_flg_t])
                cylinder(d = axle_shaft_d, h = span + axle_play);         // shaft
            translate([0, 0, axle_flg_t + span + axle_play])              // barbed tip
                cylinder(d1 = axle_barb_d, d2 = 3, h = barb_h);
        }
        // flex slot through the tip so the barb can compress going in
        translate([-axle_slot_w / 2, -axle_flg_d, tip_top - slot_len])
            cube([axle_slot_w, 2 * axle_flg_d, slot_len + 1]);
    }
}

module platter() {
    hub_gap = 1;   // hub bottom this far above the plate top
    difference() {
        union() {
            translate([0, 0, platter_lift]) cylinder(d = platter_d, h = platter_t);
            translate([0, 0, hub_gap]) cylinder(d = 18, h = platter_lift - hub_gap); // hub boss
        }
        // Deep D-bore: engages whatever length of shaft protrudes and is cut
        // deeper than the shaft so the platter rests on the bearings, not the
        // shaft tip. Bore starts near the plate to maximise engagement.
        translate([0, 0, hub_gap - 0.01])
            linear_extrude(shaft_above_plate + 4)
                intersection() {
                    circle(d = shaft_d);
                    square([shaft_d + 2, shaft_flats], center = true);
                }
        // optional shallow recess on top for a cork/rubber grip disc
        if (grip_recess > 0)
            translate([0, 0, platter_lift + platter_t - grip_recess])
                cylinder(d = platter_d - 24, h = grip_recess + 1);
    }
}

if (part == "base")       base();
if (part == "motor_test") motor_test();
if (part == "bracket")    roller_bracket();
if (part == "axle")       axle();
// base flipped into print orientation: plate face on the bed, skirt up —
// the motor recess and cable notch both print as open pockets, no bridges
if (part == "base_print") rotate([180, 0, 0]) base();
if (part == "platter") platter();
// platter already flipped into print orientation: disc on the bed, hub up
if (part == "platter_print")
    translate([0, 0, platter_lift + platter_t]) rotate([180, 0, 0]) platter();
if (part == "assembly") {
    base();
    color("Coral")
        for (a = [0, 120, 240])
            rotate([0, 0, a]) translate([roller_r, 0, 0]) roller_bracket();
    color("SteelBlue", 0.85) platter();
    // ghost bearings
    for (a = [0, 120, 240])
        rotate([0, 0, a]) translate([roller_r, 0, brg_center_h])
            color("Silver") rotate([0, 90, 0])
                tube_h();
}
module tube_h() {
    difference() {
        cylinder(d = brg_od, h = brg_w, center = true);
        cylinder(d = 8, h = brg_w + 1, center = true);
    }
}
