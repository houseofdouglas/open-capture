// ─────────────────────────────────────────────────────────────
// iPhone 16 Pro scanning cradle
// Landscape tray pivoting between two uprights, with indexed
// lock holes at 0/15/30/45/60° camera-down tilt — one setting
// per orbit pass of an Object Capture scan.
//
// Print "tray" flat on its back and "stand" base-down (set
// `part` below or -D from the CLI). No supports needed.
//
// Hardware: 2x M4x12 (pivots) + 1x M4x12 (angle lock pin),
// self-tapped into the tray bosses.
//
// Use: the camera shoots out the tray's back window, so the
// turntable sits on the side OPPOSITE the lock-hole arc (the
// arc leans backward as the camera pitches down toward the
// table in front).
// ─────────────────────────────────────────────────────────────

part = "assembly"; // ["assembly", "tray", "stand"]

$fn = 64;

/* [Phone — iPhone 16 Pro] */
phone_l = 149.6;
phone_w = 71.5;
phone_t = 8.25;
fit     = 0.6;   // total clearance; use ~2.0 and a bigger phone_t if it wears a case

/* [Tray] */
wall   = 4;
back_t = 3;
lip    = 3;      // retaining tab overhang
border = 4;      // resting ledge around the camera window. Kept narrow so
                 // the phone contacts only the flat glass perimeter and the
                 // whole camera island passes through the window without
                 // touching the ledge — in either landscape orientation.
                 // The iPhone 16 Pro island is inset ~6 mm from the edges,
                 // so 4 mm leaves ~2 mm clearance. Camera-bump depth is
                 // irrelevant: the window is a through-hole, so the island
                 // protrudes out the back toward the turntable.

button_relief = true; // open the central span of both long walls so the
                      // iPhone's side buttons (Action/volume, Side/Camera
                      // Control) never bear on plastic; also serves as
                      // finger access. Orientation-agnostic.
relief_land   = 18;   // solid wall kept at each end of the long walls;
                      // registers the phone and backs the retaining tabs

/* [Pivot] */
boss_t = 6;
lock_r = 22;                  // lock-hole radius from the pivot
angles = [0, 15, 30, 45, 60]; // indexed tilt positions
pin_d  = 4.4;                 // through-holes in the stand (M4)
tap_d  = 3.6;                 // self-tap holes in the tray bosses

/* [Stand] */
upright_t  = 5;
upright_w  = 70;
pivot_h    = 130;  // pivot height above the table — match your object's center height
base_t     = 5;
base_depth = 100;

inner_l = phone_l + fit;
inner_w = phone_w + fit;
tray_l  = inner_l + 2 * wall;
tray_w  = inner_w + 2 * wall;
rim_h   = back_t + phone_t + 3;
span    = tray_l + 2 * boss_t + 2;   // inner distance between uprights

// Paddle-shaped pivot boss: hub at the pivot plus a lobe holding the
// single lock hole. In use (tray stood upright) the lobe points down at 0°.
module boss_paddle() {
    // drawn in the tray's flat printing pose: boss axis = X, lobe toward -Y
    hull() {
        rotate([0, 90, 0]) cylinder(d = 14, h = boss_t, center = true);
        translate([0, -lock_r, 0]) rotate([0, 90, 0]) cylinder(d = 12, h = boss_t, center = true);
    }
}

module tray() {
    union() {
        difference() {
            union() {
                translate([-tray_l / 2, -tray_w / 2, 0]) cube([tray_l, tray_w, rim_h]);
                for (s = [-1, 1])
                    translate([s * (tray_l / 2 + boss_t / 2), 0, rim_h / 2])
                        boss_paddle();
            }
            // phone pocket
            translate([-inner_l / 2, -inner_w / 2, back_t]) cube([inner_l, inner_w, rim_h]);
            // camera window through the back
            translate([-(inner_l / 2 - border), -(inner_w / 2 - border), -1])
                cube([inner_l - 2 * border, inner_w - 2 * border, back_t + 2]);
            // button relief: open both long walls across the central span,
            // leaving `relief_land` of solid wall at each end
            if (button_relief) {
                for (s = [-1, 1])
                    translate([-(inner_l / 2 - relief_land),
                               s == 1 ? inner_w / 2 - 0.5 : -(inner_w / 2 + wall + 0.5),
                               back_t])
                        cube([inner_l - 2 * relief_land, wall + 1, rim_h - back_t + 2]);
            } else {
                // fallback: thumb notches on the +Y (open) side
                for (s = [-1, 1])
                    translate([s * 35, tray_w / 2, rim_h])
                        rotate([90, 0, 0]) cylinder(d = 26, h = wall + 2, center = true);
            }
            // pivot + lock holes, self-tap
            for (s = [-1, 1]) translate([s * (tray_l / 2 + boss_t / 2), 0, rim_h / 2]) {
                rotate([0, 90, 0]) cylinder(d = tap_d, h = boss_t + 2, center = true);
                translate([0, -lock_r, 0])
                    rotate([0, 90, 0]) cylinder(d = tap_d, h = boss_t + 2, center = true);
            }
        }
        // retaining tabs on the -Y side, sitting on the corner lands so
        // they have solid wall behind them: slide the phone in under them,
        // the tilted tray keeps it seated against that side
        for (sx = [-1, 1])
            translate([sx * (inner_l / 2 - relief_land / 2),
                       -(inner_w / 2 + (wall - lip) / 2),
                       rim_h - 1])
                cube([min(14, relief_land - 2), lip + wall, 2], center = true);
    }
}

module upright() {
    // local: plate in the YZ plane, thickness +X, sitting on z=0
    difference() {
        hull() {
            translate([0, -upright_w / 2, 0]) cube([upright_t, upright_w, 2]);
            translate([0, 0, pivot_h]) rotate([0, 90, 0]) cylinder(d = 56, h = upright_t);
        }
        translate([-1, 0, pivot_h]) rotate([0, 90, 0]) cylinder(d = pin_d, h = upright_t + 2);
        for (a = angles)
            translate([-1, -lock_r * sin(a), pivot_h - lock_r * cos(a)])
                rotate([0, 90, 0]) cylinder(d = pin_d, h = upright_t + 2);
    }
}

module stand() {
    union() {
        translate([-(span / 2 + upright_t), -base_depth / 2, 0])
            cube([span + 2 * upright_t, base_depth, base_t]);
        for (s = [-1, 1]) {
            translate([s == 1 ? span / 2 : -span / 2 - upright_t, 0, 0]) upright();
            // gusset
            translate([s == 1 ? span / 2 : -span / 2 - upright_t, upright_w / 2 - 0.1, 0])
                rotate([90, 0, 90]) linear_extrude(upright_t)
                    polygon([[0, 0], [-35, 0], [0, 45]]);
        }
    }
}

if (part == "tray") tray();
if (part == "stand") stand();
if (part == "assembly") {
    stand();
    // tray stood upright at 0° tilt, pivoting about the X axis
    color("SteelBlue", 0.9)
        translate([0, 0, pivot_h])
            rotate([90, 0, 0])            // stand the tray up
                translate([0, 0, -rim_h / 2])
                    tray();
}
