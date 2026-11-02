// ─────────────────────────────────────────────────────────────
// Laser-line scanner head for the turntable
//
// A fixed webcam watches two vertical laser lines sweep the object as
// the turntable steps. Each line's image position gives depth by
// triangulation; the turntable angle (from the step count) puts every
// profile in place. No photogrammetry, so no textured-background tricks,
// and the scan comes out in real millimetres.
//
// Parts:
//   base  x1  desk-level frame that captures two turntable feet, plus
//             the beam out to the mast. The turntable drops into the
//             same spot every time, so one calibration keeps working.
//   mast  x1  square post, base -> head
//   head  x1  camera cradle + both laser sleeves on one rigid plate.
//             Camera-to-laser geometry is what calibration measures, so
//             it all lives in one printed piece that can't shift.
//
// Hardware: 4x M4x12 self-tap (mast into base and head sockets),
//           2x M3 grub/self-tap (laser locks), 2 zip ties (camera),
//           2x 12 mm 650 nm line-laser modules, Logitech Brio 500/501.
//
// Frame: turntable axis = z, desk z = 0, camera on +y — same convention
// as phone_cradle.scad. Nothing here needs to be exact: calibration
// measures the real camera, laser planes and axis. It only has to be
// rigid and roughly aimed.
// ─────────────────────────────────────────────────────────────

part = "assembly"; // ["assembly", "base", "mast", "head", "mast_print"]

$fn = 64;

/* [Turntable — from turntable.scad, do not change] */
platter_top = 69;    // legs 32 + plate 5 + platter_lift 26 + platter_t 6
platter_d   = 200;
tt_leg_r    = 80;    // foot centre radius   (turntable.scad: leg_r)
tt_leg_x    = 18;    // foot radial depth    (leg_x)
tt_leg_y    = 26;    // foot tangential width (leg_y)
tt_leg_h    = 32;    // foot height          (skirt_h)
foot_az     = [30, 150]; // the two feet the base captures (third stays free)

/* [Scan geometry] */
aim_z    = platter_top + 55; // point on the axis that camera and lasers aim at
cam_d    = 200;  // lens -> axis, horizontal. At 200 the Brio's 1080p frame is
                 // 349 x 196 mm at the axis: 5.5 px/mm, objects to ~150 mm tall
cam_tilt = 15;   // camera pitch, down
laser_az = 30;   // each laser this far round the axis from the camera.
                 // Wider = finer depth, but more of the object is hidden
                 // from one of camera/laser. 30 deg is the usual compromise.
laser_r  = 200;  // laser aperture -> axis, horizontal

/* [Camera — Logitech Brio 500/501 body] */
brio_w   = 110;
brio_h   = 31.5;
brio_t   = 31.5;
cam_fit  = 0.5;
cradle_x = [20, 42]; // each cradle spans this |x| range: lens (centre) and both
                     // ends stay clear, whichever end or face the cable uses
cradle_wall = 3;
cradle_lip  = 3;     // front lip at the bottom edge: the tilted camera rests on it
tie_w       = 5;     // zip-tie groove

/* [Lasers] */
laser_d     = 12;    // module barrel diameter — measure yours
laser_fit   = 0.3;
sleeve_len  = 24;
sleeve_wall = 4;
grub_tap    = 2.5;   // M3 self-tap lock screw into the barrel

/* [Structure] */
mast_w    = 24;
mast_fit  = 0.4;
sock_wall = 4;
sock_h    = 26;      // socket depth at each end of the mast
base_t    = 6;
pocket_h  = 10;      // foot pocket wall height (feet are 32 tall)
pocket_wall = 4;
foot_fit  = 0.6;     // total clearance round each foot
beam_w    = 40;
plate_t   = 8;
plate_gap = 24;      // head plate top this far below the lens
arm_w     = 18;
screw_clr = 4.4;
screw_tap = 3.6;
roof_t    = 3;

// ── Derived geometry ─────────────────────────────────────────
cam_z    = aim_z + cam_d * tan(cam_tilt);
laser_z  = cam_z;
laser_pitch = atan((laser_z - aim_z) / laser_r);
cam_pos  = [0, cam_d, cam_z];
laser_pos = [for (s = [1, -1]) [s * laser_r * sin(laser_az), laser_r * cos(laser_az), laser_z]];
aim_pt   = [0, 0, aim_z];
plate_top = cam_z - plate_gap;
cradle_T  = brio_t + cam_fit + cradle_wall;              // cradle depth, camera frame
mast_y    = cam_d + cradle_T * cos(cam_tilt) + mast_w / 2 + sock_wall + 4;
mast_top  = plate_top + sock_h - roof_t;                 // under the head socket roof
mast_len  = mast_top - base_t;

echo(str("camera lens at z=", cam_z, "  laser pitch=", laser_pitch,
         "  mast length=", mast_len, "  mast at y=", mast_y));

// Point the local +z axis along vector v.
module orient_to(v) {
    rotate([0, acos(v[2] / norm(v)), atan2(v[1], v[0])]) children();
}

// Camera frame: lens at origin looking -y, body behind it, pitched down.
module cam_place() {
    translate(cam_pos) rotate([cam_tilt, 0, 0]) children();
}

// ── Base ─────────────────────────────────────────────────────
module foot_pocket() {
    ix = tt_leg_x + foot_fit;  iy = tt_leg_y + foot_fit;
    difference() {
        translate([-ix / 2 - pocket_wall, -iy / 2 - pocket_wall, 0])
            cube([ix + 2 * pocket_wall, iy + 2 * pocket_wall, pocket_h]);
        translate([-ix / 2, -iy / 2, -1]) cube([ix, iy, pocket_h + 2]);
    }
}

module pocket_footprint() {
    ix = tt_leg_x + foot_fit + 2 * pocket_wall;  iy = tt_leg_y + foot_fit + 2 * pocket_wall;
    square([ix, iy], center = true);
}

// Mast socket: open-topped square well, two screws pull the mast into one
// corner so the fit clearance can't become wobble at the head.
module socket_block(h) {
    o = mast_w + mast_fit + 2 * sock_wall;
    translate([-o / 2, -o / 2, 0]) cube([o, o, h]);
}
module socket_holes(z_screw) {
    i = mast_w + mast_fit;
    translate([-i / 2, -i / 2, 0]) cube([i, i, 200]);
    translate([0, 0, z_screw]) {
        rotate([0, 90, 0]) cylinder(d = screw_clr, h = 40);   // +x wall
        rotate([-90, 0, 0]) cylinder(d = screw_clr, h = 40);  // +y wall
    }
}

module base() {
    // The foot pockets only ring the feet — no floor — so the turntable still
    // stands on the desk at its usual height and the base can't tilt it.
    difference() {
        union() {
            linear_extrude(base_t) {
                // bridge between the two captured feet
                hull() for (a = foot_az)
                    rotate(a) translate([tt_leg_r, 0]) pocket_footprint();
                // beam out to the mast
                hull() {
                    translate([0, tt_leg_r * sin(foot_az[0])]) circle(d = beam_w);
                    translate([0, mast_y]) square(mast_w + mast_fit + 2 * sock_wall, center = true);
                }
            }
            for (a = foot_az) rotate([0, 0, a]) translate([tt_leg_r, 0, 0]) foot_pocket();
            translate([0, mast_y, 0]) socket_block(base_t + sock_h);
        }
        for (a = foot_az)   // clear the foot itself out of the bridge plate
            rotate([0, 0, a]) translate([tt_leg_r, 0, 0])
                cube([tt_leg_x + foot_fit, tt_leg_y + foot_fit, 4 * pocket_h], center = true);
        translate([0, mast_y, base_t]) socket_holes(sock_h / 2);
    }
}

// ── Mast ─────────────────────────────────────────────────────
module mast() {
    c = 1;   // chamfered ends ease it into the sockets
    difference() {
        hull() {
            translate([-mast_w / 2 + c, -mast_w / 2 + c, 0]) cube([mast_w - 2 * c, mast_w - 2 * c, mast_len]);
            translate([-mast_w / 2, -mast_w / 2, c]) cube([mast_w, mast_w, mast_len - 2 * c]);
        }
        // pilot holes matching both sockets' screws (+x and +y faces)
        for (z = [sock_h / 2, mast_len - (sock_h - roof_t) / 2])
            translate([0, 0, z]) {
                rotate([0, 90, 0]) cylinder(d = screw_tap, h = mast_w);
                rotate([-90, 0, 0]) cylinder(d = screw_tap, h = mast_w);
            }
    }
}

// ── Head ─────────────────────────────────────────────────────
// One cradle segment, camera frame. U-shaped (bottom + back, open top) so it
// prints without supports; a zip tie round the groove holds the camera down.
module cradle_seg(x0, x1) {
    w = x1 - x0;
    ih = brio_h + cam_fit;
    difference() {
        translate([x0, -cradle_wall, -ih / 2 - cradle_wall])
            cube([w, cradle_T + cradle_wall, cradle_wall + ih * 0.6]);
        // body pocket
        translate([x0 - 1, 0, -ih / 2]) cube([w + 2, brio_t + cam_fit, ih]);
        // front opening above the lip
        translate([x0 - 1, -cradle_wall - 1, -ih / 2 + cradle_lip]) cube([w + 2, cradle_wall + 2, ih]);
        // zip-tie groove round the outside
        translate([x0 + (w - tie_w) / 2, -cradle_wall - 1, -ih / 2 - cradle_wall - 1])
            difference() {
                cube([tie_w, cradle_T + cradle_wall + 2, ih + 2 * cradle_wall + 2]);
                translate([-1, 2.5, 2.5]) cube([tie_w + 2, cradle_T + cradle_wall - 3, ih + 2 * cradle_wall - 3]);
            }
    }
}

// Solid pillar from a camera-frame slab straight down to the head plate.
module drop_to_plate() {
    hull() {
        children();
        translate([0, 0, plate_top - 0.01]) linear_extrude(0.01) projection() children();
    }
}

module head() {
    sock_o = mast_w + mast_fit + 2 * sock_wall;
    difference() {
        union() {
            // plate: mast pad -> camera, mast pad -> each laser
            translate([0, 0, plate_top - plate_t]) linear_extrude(plate_t) {
                hull() {
                    translate([0, mast_y]) square(sock_o, center = true);
                    translate([-cradle_x[1] - 2, cam_d - 6]) square([2 * cradle_x[1] + 4, cradle_T + 6]);
                }
                for (p = laser_pos) hull() {
                    translate([0, mast_y]) square(sock_o, center = true);
                    translate([p[0], p[1]]) circle(d = arm_w + 4);
                }
            }
            // mast socket, roofed so the mast top sets the head height
            translate([0, mast_y, plate_top - plate_t]) socket_block(plate_t + sock_h);
            // camera cradles on pillars
            for (s = [-1, 1]) {
                x0 = s > 0 ? cradle_x[0] : -cradle_x[1];
                drop_to_plate() cam_place()
                    translate([x0, -cradle_wall, -(brio_h + cam_fit) / 2 - cradle_wall])
                        cube([cradle_x[1] - cradle_x[0], cradle_T + cradle_wall, 0.01]);
                cam_place() cradle_seg(x0, x0 + cradle_x[1] - cradle_x[0]);
            }
            // laser sleeves on pillars
            for (p = laser_pos) hull() {
                translate(p) orient_to(aim_pt - p)
                    cylinder(d = laser_d + laser_fit + 2 * sleeve_wall, h = sleeve_len, center = true);
                translate([p[0], p[1], plate_top - 0.01]) cylinder(d = arm_w, h = 0.01);
            }
        }
        // mast well (from below, up to the roof)
        translate([0, mast_y, plate_top - plate_t - 1]) {
            i = mast_w + mast_fit;
            translate([-i / 2, -i / 2, 0]) cube([i, i, plate_t + sock_h - roof_t + 1]);
        }
        // mast screws (+x and +y walls), level with the mast's upper pilots
        translate([0, mast_y, mast_top - (sock_h - roof_t) / 2]) {
            rotate([0, 90, 0]) cylinder(d = screw_clr, h = 40);
            rotate([-90, 0, 0]) cylinder(d = screw_clr, h = 40);
        }
        // laser bores + lock screws
        for (p = laser_pos) translate(p) orient_to(aim_pt - p) {
            cylinder(d = laser_d + laser_fit, h = sleeve_len + 40, center = true);
            rotate([0, -90, 0]) cylinder(d = grub_tap, h = laser_d + 2 * sleeve_wall);
        }
        // keep the camera pocket clear of the pillars' hull
        cam_place() translate([-brio_w / 2 - 1, 0, -(brio_h + cam_fit) / 2])
            cube([brio_w + 2, brio_t + cam_fit, brio_h + 20]);
    }
}

// ── Output ───────────────────────────────────────────────────
if (part == "base") base();
if (part == "mast") mast();
if (part == "mast_print") rotate([0, 90, 0]) translate([0, 0, -mast_len / 2]) mast();
if (part == "head") head();
if (part == "assembly") {
    color("SteelBlue") base();
    color("Silver") translate([0, mast_y, base_t]) mast();
    color("Coral") head();
    // ghosts: turntable feet and platter, camera, lasers, laser fans
    %for (a = [30, 150, 270]) rotate([0, 0, a]) translate([tt_leg_r, 0, tt_leg_h / 2])
        cube([tt_leg_x, tt_leg_y, tt_leg_h], center = true);
    %translate([0, 0, platter_top - 6]) cylinder(d = platter_d, h = 6);
    %cam_place() translate([-brio_w / 2, 0, -brio_h / 2]) cube([brio_w, brio_t, brio_h]);
    for (p = laser_pos) {
        %translate(p) orient_to(aim_pt - p) cylinder(d = laser_d, h = 32, center = true);
        // the laser plane: vertical, through the laser and the axis
        color("Red", 0.15) hull() {
            translate(p) sphere(0.5);
            translate([0, 0, platter_top]) sphere(0.5);
            translate([0, 0, platter_top + 150]) sphere(0.5);
        }
    }
}
