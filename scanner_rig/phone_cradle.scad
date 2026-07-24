// ─────────────────────────────────────────────────────────────
// iPhone 16 Pro scanning cradle + arc stand
//
// The tray holds the phone in landscape and bolts between two
// arch-shaped "wings". The wings carry three pivot stations that
// lie on an ARC of constant radius about the object centre, so
// each station puts the camera at a different height AND a
// different distance back — higher and closer as the angle
// steepens — while a matching lock hole pitches the tray down by
// the same angle. Result: the camera always looks straight at the
// object centre from the same distance, on all three passes.
//
// Parts:
//   tray      x1  (unchanged — reuse an already-printed one)
//   wing      x2  print flat, 238 x 321 x 6, no supports (one at a time)
//   crossbar  x2  print flat
//   shim      x2  only when retargeting the arc at a taller object
//   stand         legacy flat stand, kept for reference only
//
// Hardware per setup: 2x M4x12 pivots + 1x M4x12 lock pin
// (self-tap into the tray bosses) + 4x M4x12 for the crossbars.
//
// Use: the camera shoots out the tray's back window. Turntable
// axis is y = 0, the stand stands at +y. To change pass, move the
// tray's 3 screws to the next station's hole pair.
// ─────────────────────────────────────────────────────────────

part = "assembly"; // ["assembly", "arc_assembly", "tray", "wing", "crossbar", "shim", "stand"]

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

/* [Stand — legacy flat stand, superseded by the arc stand below] */
upright_t  = 5;
upright_w  = 70;
pivot_h    = 130;  // pivot height above the table — match your object's center height
base_t     = 5;
base_depth = 100;

/* [Arc stand — camera rides an arc centred on the object] */
// Tilting the tray alone only changes where the camera AIMS, not where it IS.
// To shoot down at angle θ and still have the object centred, the camera has
// to move along an arc of constant radius about the object centre: higher AND
// closer as θ grows. That also keeps framing, focus distance and scale
// identical on every pass, and it keeps the stand half as tall as a straight
// column would need to be (271 mm vs 519 mm to reach 65°).
//
//   camera at elevation θ:   y = cam_R·cos θ ,  z = obj_h + cam_R·sin θ ,  tilt = θ
//
// Turntable axis is y = 0; the stand stands at +y. Object centre is (0, obj_h).
//
// DATUM: every z here is measured from the DESK/TABLE the rig stands on, not
// from the platter — the wings sit on the same desk as the turntable, so they
// must share one origin. The platter top is 69.0 mm above the desk (measured
// from turntable.scad: legs 32 + plate 5 + platter_lift 26 + platter_t 6).
//
//        obj_h = platter_top + (object height)/2 = 69 + h/2
//
// You do NOT need a wing per object size. obj_h only fixes where the arc aims;
// what matters is the height difference between the wing's base and the object
// centre, so shim instead of reprinting:
//
//        shim = (object height)/2 + 69 - obj_h
//              + -> spacer under the WINGS (see the `shim` part)
//              - -> riser under the OBJECT, on the platter
//
// Default obj_h = 101 puts the zero-shim object at 64 mm, i.e. the sweet spot
// for 2x at cam_R = 200. No shim needed at all for 43..85 mm at 2x, or
// 23..105 mm at 1x (the wider frame is more forgiving).
platter_top = 69;           // platter surface above the desk — do not change
obj_h      = 101;           // object CENTRE above the DESK (= 69 + h/2)
cam_R      = 200;           // camera→object distance, constant along the arc
elevations = [15, 40, 65];  // the three camera positions (low / mid / high)

wing_t   = 6;    // wing plate thickness
band_in  = 10;   // band reaches this far inside the arc (material behind the
band_out = 30;   // camera only — nothing intrudes into the shot)
rail_h   = 14;   // bottom rail height
toe_y    = 100;  // front foot (clears the Ø184 turntable frame)
heel_y   = 290;  // rear foot — counters the forward lean of the arch
strut_w  = 18;   // rear diagonal width
xbar     = [16, 12];  // cross-bar cross-section

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

// ── Arc stand ────────────────────────────────────────────────
// Point on the arc at elevation `t`, radius `r`, in (y, z).
function arc_pt(t, r) = [r * cos(t), obj_h + r * sin(t)];

th_lo   = -8;                                   // band runs a little past the
th_hi   = elevations[len(elevations) - 1] + 8;  // outermost pivots, for material
diag_a  = arc_pt(50, cam_R + band_out);         // rear diagonal, top end
diag_b  = [heel_y - 5, rail_h / 2];             // rear diagonal, foot
// cross-bar seats: one on the diagonal, one in the rail. Both sit >30 mm clear
// of the tray at every elevation, and behind the camera at all times.
xbars   = [diag_a + 0.55 * (diag_b - diag_a), [heel_y - 20, rail_h / 2]];

// Wedge covering angles th_lo..th_hi, used to trim the band.
module arc_wedge(r) {
    pts = concat([[0, obj_h]],
                 [for (t = [th_lo : 3 : th_hi]) arc_pt(t, r)],
                 [arc_pt(th_hi, r)]);
    polygon(pts);
}

module wing_profile() {
  // Trim everything below z=0 so the bottom edge is dead flat and the wing
  // can't rock: the rear diagonal's Ø18 end cap sits at the rail's mid-height
  // and would otherwise poke 2 mm below the table.
  intersection() {
    translate([-100, 0]) square([heel_y + 200, obj_h + cam_R + 200]);
    union() {
        // the arch: a band straddling the camera arc
        intersection() {
            difference() {
                translate([0, obj_h]) circle(r = cam_R + band_out);
                translate([0, obj_h]) circle(r = cam_R - band_in);
            }
            arc_wedge(cam_R + band_out + 40);
        }
        // front leg, down from the low end of the arch
        hull() {
            translate(arc_pt(th_lo, cam_R - band_in + 2)) circle(d = 12);
            translate(arc_pt(th_lo, cam_R + band_out - 6)) circle(d = 12);
            translate([cam_R - band_in + 8, rail_h / 2]) circle(d = 12);
            translate([cam_R + band_out - 6, rail_h / 2]) circle(d = 12);
        }
        // rear diagonal
        hull() {
            translate(diag_a) circle(d = strut_w);
            translate(diag_b) circle(d = strut_w);
        }
        // bottom rail: toe forward of the leg for anti-tip, heel at the back
        translate([toe_y, 0]) square([heel_y - toe_y, rail_h]);
    }
  }
}

module arc_wing() {
    difference() {
        linear_extrude(wing_t) wing_profile();
        // pivot + tilt-lock hole pair for each elevation
        for (t = elevations) {
            translate(concat(arc_pt(t, cam_R), [-1]))
                cylinder(d = pin_d, h = wing_t + 2);
            translate([cam_R * cos(t) + lock_r * sin(t),
                       obj_h + cam_R * sin(t) - lock_r * cos(t), -1])
                cylinder(d = pin_d, h = wing_t + 2);
        }
        // cross-bar screw clearance
        for (p = xbars)
            translate(concat(p, [-1])) cylinder(d = pin_d, h = wing_t + 2);
    }
}

// Spacer that raises BOTH wings to retarget the arc at a taller object.
// Set shim_rise = (object height)/2 + 69 - obj_h, print 2, and stand each
// wing's bottom rail in the groove. Grooved so it locates itself and can't
// slide out from under the rail.
shim_rise  = 18;   // how much higher the arc should aim (see the formula above)
shim_groove = 4;   // groove depth; total height is shim_rise + shim_groove
module arc_shim() {
    len = heel_y - toe_y + 10;
    difference() {
        translate([-len / 2, -13, 0]) cube([len, 26, shim_rise + shim_groove]);
        translate([-len / 2 - 1, -(wing_t + 0.4) / 2, shim_rise])
            cube([len + 2, wing_t + 0.4, shim_groove + 1]);
    }
}

// Bar spanning between the wings; ends self-tap for M4 driven through the wing.
module arc_crossbar() {
    difference() {
        translate([0, -xbar[0] / 2, 0]) cube([span, xbar[0], xbar[1]]);
        for (x = [-1, span + 1])
            translate([x, 0, xbar[1] / 2]) rotate([0, 90, 0])
                cylinder(d = tap_d, h = 14);
    }
}

// Place a wing in 3D: local x→y (distance from turntable axis), local y→z.
module arc_wing_placed(side) {
    translate([side * span / 2 + (side > 0 ? 0 : -wing_t), 0, 0])
        rotate([90, 0, 90]) arc_wing();
}

module arc_stand() {
    for (s = [-1, 1]) arc_wing_placed(s);
    for (p = xbars)
        translate([-span / 2, p[0], p[1] - xbar[1] / 2]) arc_crossbar();
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

// Tray mounted on the arc at elevation t: sits at the arc point, pitched down
// by t so the camera looks straight at the object centre. The extra Z-180 puts
// the retaining tabs on the LOW side so the phone can't slide out.
module tray_on_arc(t) {
    translate([0, cam_R * cos(t), obj_h + cam_R * sin(t)])
        rotate([t - 90, 0, 0]) rotate([0, 0, 180])
            translate([0, 0, -rim_h / 2]) tray();
}

if (part == "tray")     tray();
if (part == "stand")    stand();          // legacy flat stand
if (part == "wing")     arc_wing();       // print 2
if (part == "crossbar") arc_crossbar();   // print 2
if (part == "shim")     arc_shim();       // print 2, only for taller objects

if (part == "assembly") {
    stand();
    // tray stood upright at 0° tilt, pivoting about the X axis
    color("SteelBlue", 0.9)
        translate([0, 0, pivot_h])
            rotate([90, 0, 0])            // stand the tray up
                translate([0, 0, -rim_h / 2])
                    tray();
}

// The arc stand with the tray shown at all three camera positions, plus the
// turntable and a stand-in object for context.
if (part == "arc_assembly") {
    color("Khaki") arc_stand();
    for (i = [0 : len(elevations) - 1])
        color(i == 0 ? "SteelBlue" : "LightSteelBlue", i == 0 ? 0.95 : 0.45)
            tray_on_arc(elevations[i]);
    // Turntable stand-in, measured from turntable.scad with the desk at z=0:
    // legs 0..32, base plate 32..37, platter 63..69 (Ø200).
    color("Gray")    cylinder(d = 184, h = 37);
    color("DimGray") translate([0, 0, 63]) cylinder(d = 200, h = 6);
    // the object: sits on the platter top (69) with its CENTRE at obj_h
    color("Tomato")  translate([0, 0, platter_top])
                         cylinder(d = 42, h = 2 * (obj_h - platter_top));
    // sight lines from each camera to the object centre
    for (t = elevations)
        color("Red") hull() {
            translate([0, cam_R * cos(t), obj_h + cam_R * sin(t)]) sphere(d = 1.5);
            translate([0, 0, obj_h]) sphere(d = 1.5);
        }
}
