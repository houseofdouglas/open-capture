#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "numpy",
#   "opencv-python",
#   "pyserial",
#   "open3d==0.19.*",  # 0.20's macOS wheel links Homebrew libusb and fails to load
# ]
# ///
"""Laser-line turntable scanner: Brio webcam + two line lasers + the ScanTable.

A fixed camera watches a vertical laser line on the object. Each image row
gives one point by triangulation (camera ray ∩ calibrated laser plane), and
the turntable angle — known from the step count, not from the images —
rotates every profile into place. The result is in real millimetres.

Run from Terminal.app: macOS only gives camera access to apps you've allowed
in System Settings > Privacy & Security > Camera.

  ./laser_scan.py board                  write calib-board.svg; print at 100 %
  ./laser_scan.py preview                live view: set focus/exposure, aim lasers
  ./laser_scan.py intrinsics             wave the board in front of the camera
  ./laser_scan.py calibrate              board standing on the platter
  ./laser_scan.py scan NAME              -> scan/NAME.ply (points), .npz, .stl
  ./laser_scan.py mesh scan/NAME.npz     re-mesh a saved scan

Calibration order matters: preview (fix focus) -> intrinsics -> calibrate.
Changing focus changes the lens model, so redo intrinsics + calibrate after.

Needs uvc-util (locks exposure/focus; OpenCV can't on macOS): on PATH, in
$UVC_UTIL, or at bin/uvc-util. See scanner_rig/README.md, "Laser scanner".
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")
import cv2  # noqa: E402
import numpy as np  # noqa: E402

REPO = Path(__file__).resolve().parent
CALIB = REPO / "calib"
SCANS = REPO / "scan"

# 28BYJ-48 half-steps per platter revolution: 64 x (32/9)(22/11)(26/9)(31/10).
# Calibration measures the real figure; this is the starting point.
HALF_STEPS_PER_REV = 64 * (32 / 9) * (22 / 11) * (26 / 9) * (31 / 10)   # 4075.77
NOMINAL_DEG_PER_STEP = 360 / HALF_STEPS_PER_REV

# 10 x 7 squares: one even and one odd count, so the board has no 180° symmetry
# and its corner order can't flip between views.
BOARD_SQUARES = (10, 7)
PATTERN = (BOARD_SQUARES[0] - 1, BOARD_SQUARES[1] - 1)
SQUARE_MM = 15.0

LEFT, RIGHT = 1, 2                 # firmware LASER mask bits (GPIO 3, GPIO 10)
LASERS = {LEFT: "left", RIGHT: "right"}
PLATTER_R = 100.0
CAMERAS = {"brio": "0x046d:0x0946", "c920": "0x046d:0x08e5"}
DEFAULT_SETTINGS = {"exposure": 100, "focus": 40, "gain": 0}   # exposure in 0.1 ms


# ── small helpers ────────────────────────────────────────────

def load_json(name):
    p = CALIB / name
    return json.loads(p.read_text()) if p.exists() else None


def save_json(name, data):
    CALIB.mkdir(exist_ok=True)
    (CALIB / name).write_text(json.dumps(data, indent=2))
    print(f"saved {CALIB / name}")


def need(name, cmd):
    data = load_json(name)
    if data is None:
        sys.exit(f"No {CALIB / name} yet - run `./laser_scan.py {cmd}` first.")
    return data


def distribute(total, n):
    """Split `total` steps into n integer increments that sum exactly."""
    out, left = [], total
    for i in range(n):
        inc = left // (n - i)
        out.append(inc)
        left -= inc
    return out


# ── turntable (ESP32 over USB serial) ────────────────────────

class Table:
    def __init__(self, port=None):
        import serial
        from serial.tools import list_ports
        if port is None:
            esp = [p.device for p in list_ports.comports() if p.vid == 0x303A]
            if not esp:
                sys.exit("ScanTable not found on USB (no Espressif device). "
                         "Plug in the ESP32 or pass --port.")
            port = esp[0]
        self.s = serial.Serial()
        self.s.port, self.s.baudrate, self.s.timeout = port, 115200, 10
        # Both lines low: the C3's USB-serial resets the chip on some DTR/RTS
        # patterns, which would drop the held coils mid-scan.
        self.s.dtr = self.s.rts = False
        self.s.open()
        for _ in range(20):                          # tolerate a just-booted board
            try:
                self.cmd("PING", timeout=0.5)
                break
            except (TimeoutError, RuntimeError):
                time.sleep(0.25)
        else:
            sys.exit(f"No reply from the ScanTable on {port} - is the laser "
                     "firmware flashed, with USB CDC On Boot enabled?")
        self.pos = 0

    def cmd(self, line, timeout=15):
        self.s.reset_input_buffer()
        self.s.write((line + "\n").encode())
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.s.timeout = max(0.05, deadline - time.time())
            r = self.s.readline().decode(errors="replace").strip()
            if r.startswith("ok"):
                return r[2:].strip()
            if r.startswith("err"):
                raise RuntimeError(f"{line}: {r}")
            # anything else is the firmware's own logging (BLE etc.) - skip it
        raise TimeoutError(line)

    def preload(self):
        self.cmd("PRELOAD")
        self.pos = 0

    def step(self, n):
        if n > 0:
            self.pos = int(self.cmd(f"STEP {n}"))

    def laser(self, mask):
        self.cmd(f"LASER {mask}")

    def release(self):
        try:
            self.cmd("RELEASE", timeout=3)
        except Exception:
            pass


# ── camera (OpenCV frames, uvc-util controls) ────────────────

def find_uvc():
    for cand in (os.environ.get("UVC_UTIL"), shutil.which("uvc-util"), REPO / "bin" / "uvc-util"):
        if cand and Path(cand).is_file():
            return str(cand)
    sys.exit("uvc-util not found (needed to lock exposure/focus). Build it as "
             "described in scanner_rig/README.md and put it at bin/uvc-util.")


class Camera:
    def __init__(self, name="brio", settings=None):
        self.uvc_bin = find_uvc()
        self.usb_id = CAMERAS.get(name, name)
        self.settings = {**DEFAULT_SETTINGS, **(settings or {})}
        self.flush = self.settings.get("flush", 4)
        self.cap = self._open()
        self.lock()
        self.size = self.grab().shape[1::-1]

    def uvc(self, *args):
        return subprocess.run([self.uvc_bin, "-V", self.usb_id, "-k", *args],
                              capture_output=True, text=True).stdout

    def lock(self, exposure=None):
        """Manual everything. macOS resets controls when a stream starts, so
        this runs after opening, and again whenever settings change."""
        s = self.settings
        self.uvc("-s", "auto-exposure-mode=1", "-s", "auto-exposure-priority=0",
                 "-s", f"exposure-time-abs={exposure or s['exposure']}",
                 "-s", f"gain={s['gain']}", "-s", "auto-focus=false",
                 "-s", f"focus-abs={s['focus']}", "-s", "auto-white-balance-temp=false",
                 "-s", "backlight-compensation=0")

    def _open(self):
        caps = {}
        for idx in range(6):
            cap = cv2.VideoCapture(idx, cv2.CAP_AVFOUNDATION)
            if not cap.isOpened():
                continue
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
            if cap.read()[0]:
                caps[idx] = cap
            else:
                cap.release()
        if not caps:
            sys.exit("No camera frames. Run this from Terminal.app and allow it in "
                     "System Settings > Privacy & Security > Camera.")
        if len(caps) == 1:
            return next(iter(caps.values()))
        # Several cameras and OpenCV can't name them: the right one is the
        # stream whose brightness follows this camera's exposure control.
        def brightness():
            for c in caps.values():
                for _ in range(5):
                    c.read()
            return {i: c.read()[1].mean() for i, c in caps.items()}
        self.lock(exposure=20)
        time.sleep(0.5)
        dark = brightness()
        self.lock(exposure=300)
        time.sleep(0.5)
        bright = brightness()
        pick = max(caps, key=lambda i: bright[i] - dark[i])
        for i, c in caps.items():
            if i != pick:
                c.release()
        return caps[pick]

    def read(self):
        ok, f = self.cap.read()
        if not ok:
            raise RuntimeError("camera stopped delivering frames")
        return f

    def grab(self):
        """A frame captured after everything before this call: AVFoundation
        queues a few frames, so stale ones are discarded first."""
        for _ in range(self.flush):
            self.cap.grab()
        return self.read()


def measure_latency(cam, table):
    """Frames between switching a laser on and seeing it - sets the flush."""
    table.laser(0)
    base = cam.grab()[:, :, 2].astype(np.int16)
    table.laser(LEFT | RIGHT)
    n = None
    for i in range(1, 15):
        red = cam.read()[:, :, 2].astype(np.int16)
        if np.count_nonzero(red - base > 40) > 300:
            n = i
            break
    table.laser(0)
    if n is None:
        print("! couldn't see the lasers switch on - keeping flush =", cam.flush)
    else:
        cam.flush = n + 1
    return cam.flush


# ── laser line extraction and triangulation ──────────────────

def extract_line(on, off, mask=None, thresh=15, win=6):
    """Sub-pixel laser column per image row, from a laser-on/laser-off pair.
    Subtracting the off frame cancels ambient light and texture, leaving the
    laser. Returns (rows, cols) for rows where the line was found."""
    d = on[:, :, 2].astype(np.float32) - off[:, :, 2].astype(np.float32)
    np.maximum(d, 0, out=d)
    d = cv2.GaussianBlur(d, (5, 1), 0)              # smooth across the line only
    if mask is not None:
        d[~mask] = 0
    h, w = d.shape
    cols = d.argmax(axis=1)
    rows = np.arange(h)
    peak = d[rows, cols]
    ok = (peak > thresh) & (cols >= win) & (cols < w - win)
    rows, cols, peak = rows[ok], cols[ok], peak[ok]
    idx = cols[:, None] + np.arange(-win, win + 1)
    wgt = np.maximum(d[rows[:, None], idx] - peak[:, None] / 2, 0)   # top half only
    sub = (wgt * idx).sum(axis=1) / np.maximum(wgt.sum(axis=1), 1e-6)
    return rows.astype(np.float64), sub


def pixel_rays(rows, cols, K, dist):
    pts = np.stack([cols, rows], axis=-1).reshape(-1, 1, 2).astype(np.float64)
    xy = cv2.undistortPoints(pts, K, dist).reshape(-1, 2)
    return np.column_stack([xy, np.ones(len(xy))])


def intersect(rays, normal, d):
    """Points where camera rays meet the plane normal·X + d = 0."""
    s = -d / (rays @ normal)
    return rays * s[:, None]


def fit_plane(pts):
    m = pts.mean(axis=0)
    _, sv, vt = np.linalg.svd(pts - m, full_matrices=False)
    n = vt[2]
    return n, -n @ m, np.sqrt(sv[2] ** 2 / len(pts)), sv


class Rig:
    """Calibrated geometry: lens model, laser planes, turntable axis."""

    def __init__(self, data):
        self.K = np.array(data["K"])
        self.dist = np.array(data["dist"])
        self.planes = {int(k): (np.array(v[:3]), v[3]) for k, v in data["planes"].items()}
        self.deg_per_step = data["deg_per_step"]
        a = np.array(data["axis_dir"])           # forward steps turn positively about a
        c = np.array(data["axis_point"])
        self.sgn = 1.0 if a @ np.array([0.0, -1.0, 0.0]) > 0 else -1.0   # camera -y ~ up
        z = self.sgn * a
        x = -c - (-c @ z) * z                    # from the axis toward the camera
        x /= np.linalg.norm(x)
        self.R = np.stack([x, np.cross(z, x), z])
        self.c = c

    def to_table(self, X):
        return (X - self.c) @ self.R.T

    def to_object(self, X, steps):
        """Camera-frame points seen after `steps` -> fixed object frame."""
        phi = math.radians(-self.sgn * steps * self.deg_per_step)
        cz, sz = math.cos(phi), math.sin(phi)
        Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
        return self.to_table(X) @ Rz.T

    def roi(self, size):
        """Image mask covering the cylinder over the platter - rejects laser
        light on the background either side of it. The table frame's origin
        sits at calibration-board height, not on the platter, so the cylinder
        runs generously both ways; height is trimmed later, in make_mesh."""
        a = np.linspace(0, 2 * np.pi, 72)
        ring = np.column_stack([PLATTER_R * np.cos(a), PLATTER_R * np.sin(a)])
        pts = np.vstack([np.column_stack([ring, np.full(72, z)]) for z in (-200.0, 250.0)])
        cam_pts = pts @ self.R + self.c                  # table -> camera frame
        img, _ = cv2.projectPoints(cam_pts, np.zeros(3), np.zeros(3), self.K, self.dist)
        mask = np.zeros(size[::-1], np.uint8)
        cv2.fillConvexPoly(mask, cv2.convexHull(img.reshape(-1, 2).astype(np.int32)), 1)
        return mask.astype(bool)


# ── board detection ──────────────────────────────────────────

def board_points():
    objp = np.zeros((PATTERN[0] * PATTERN[1], 3), np.float32)
    objp[:, :2] = np.mgrid[0:PATTERN[0], 0:PATTERN[1]].T.reshape(-1, 2) * SQUARE_MM
    return objp


def find_board(frame, fast=False):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    if fast:   # live preview: quick check on a half-size image
        small = cv2.resize(gray, None, fx=0.5, fy=0.5)
        ok, c = cv2.findChessboardCorners(small, PATTERN, flags=cv2.CALIB_CB_FAST_CHECK)
        return c * 2 if ok else None
    ok, c = cv2.findChessboardCornersSB(gray, PATTERN, flags=cv2.CALIB_CB_ACCURACY)
    return c if ok else None


def fit_axis(poses):
    """Turntable axis and degrees/step from board poses [(steps, R, t)].
    Each pose pair differs by a rotation Q about the axis: R_i = Q R_ref, and
    the board origin moves as t_i = Q(t_ref - c) + c."""
    s0, R0, t0 = poses[len(poses) // 2]
    axes, ds, angs, A, b = [], [], [], [], []
    for s, R, t in poses:
        if s == s0 or abs(s - s0) * NOMINAL_DEG_PER_STEP > 150:
            continue
        Q = R @ R0.T
        rv = cv2.Rodrigues(Q)[0].ravel()
        axes.append(rv / np.linalg.norm(rv) * np.sign(s - s0))
        ds.append(s - s0)
        angs.append(np.linalg.norm(rv) * np.sign(s - s0))
        A.append(np.eye(3) - Q)
        b.append(t - Q @ t0)
    axis = np.mean(axes, axis=0)
    axis /= np.linalg.norm(axis)
    spread = np.degrees(np.mean([math.acos(min(1, abs(a @ axis))) for a in axes]))
    c = np.linalg.lstsq(np.vstack(A), np.concatenate(b), rcond=None)[0]
    c = c + ((t0 - c) @ axis) * axis          # axis point level with the board
    ds, angs = np.array(ds, float), np.degrees(angs)
    return axis, c, float(ds @ angs / (ds @ ds)), spread


# ── commands ─────────────────────────────────────────────────

def cmd_board(args):
    cols, rows = BOARD_SQUARES
    s, m = SQUARE_MM, SQUARE_MM
    W, H = cols * s + 2 * m, rows * s + 2 * m + 22
    sq = "".join(f'<rect x="{m + c * s}" y="{m + r * s}" width="{s}" height="{s}"/>'
                 for r in range(rows) for c in range(cols) if (r + c) % 2 == 0)
    by = rows * s + 2 * m + 6
    ticks = "".join(f'<line x1="{m + t}" y1="{by}" x2="{m + t}" y2="{by + (4 if t % 50 else 6)}" '
                    f'stroke="black" stroke-width="0.3"/>' for t in range(0, 101, 10))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}mm" height="{H}mm" '
           f'viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="white"/>{sq}'
           f'<line x1="{m}" y1="{by}" x2="{m + 100}" y2="{by}" stroke="black" stroke-width="0.3"/>'
           f'{ticks}<text x="{m + 104}" y="{by + 4}" font-size="4" font-family="sans-serif">'
           f'100 mm. Print at 100 %; squares must measure {s} mm.</text></svg>')
    out = Path(args.out)
    out.write_text(svg)
    print(f"wrote {out} - print at 100 % (no fit-to-page), check the 100 mm bar, "
          f"and glue it flat to stiff card or foam board.")


def open_rig_devices(args, need_table=True):
    cam = Camera(args.camera, load_json("camera.json"))
    table = None
    try:
        table = Table(args.port)
    except SystemExit as e:
        if need_table:
            raise
        print(f"(no turntable: {e})")
    return cam, table


def cmd_preview(args):
    cam, table = open_rig_devices(args, need_table=False)
    s = cam.settings
    mask, off = 0, None
    print("keys: 0-3 lasers (0 off, 1 left, 2 right, 3 both)  e/E exposure  "
          "f/F focus  d diff view  r rotate 30°  s save  q quit")
    win = "laser_scan preview"
    while True:
        f = cam.read()
        view = f
        if off is not None and mask:
            d = np.clip(f[:, :, 2].astype(np.int16) - off[:, :, 2], 0, 255).astype(np.uint8)
            view = cv2.applyColorMap(cv2.convertScaleAbs(d, alpha=3), cv2.COLORMAP_INFERNO)
        sat = np.count_nonzero(f[:, :, 2] == 255)
        cv2.putText(view, f"exposure {s['exposure'] / 10:.1f} ms  focus {s['focus']}  lasers {mask}"
                    f"  saturated px {sat}", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        cv2.imshow(win, cv2.resize(view, None, fx=0.5, fy=0.5))
        k = cv2.waitKey(1) & 0xFF
        if k == ord("q"):
            break
        if k in map(ord, "0123") and table:
            mask = k - ord("0")
            table.laser(mask)
        elif k in (ord("e"), ord("E")):
            s["exposure"] = int(np.clip(s["exposure"] * (1.25 if k == ord("E") else 0.8), 3, 2047))
            cam.lock()
        elif k in (ord("f"), ord("F")):
            s["focus"] = int(np.clip(s["focus"] + (5 if k == ord("F") else -5), 0, 255))
            cam.lock()
        elif k == ord("d") and table:
            if off is None:
                table.laser(0)
                off = cam.grab()
                table.laser(mask)
            else:
                off = None
        elif k == ord("r") and table:
            table.step(round(30 / NOMINAL_DEG_PER_STEP))
        elif k == ord("s"):
            save_json("camera.json", {k2: s[k2] for k2 in ("exposure", "focus", "gain")})
    if table:
        table.release()
    cv2.destroyAllWindows()


def cmd_intrinsics(args):
    cam = Camera(args.camera, load_json("camera.json"))
    objp = board_points()
    obj, img = [], []
    print("Hold the board 15-35 cm from the camera. Cover the whole frame - corners "
          "and edges too - with the board tilted different ways.\n"
          "space = capture (when corners show), c = calibrate (needs 12+), q = quit")
    win = "laser_scan intrinsics"
    while True:
        f = cam.read()
        c = find_board(f, fast=True)
        view = f.copy()
        if c is not None:
            cv2.drawChessboardCorners(view, PATTERN, c, True)
        for pts in img:   # show coverage so far
            cv2.polylines(view, [cv2.convexHull(pts.reshape(-1, 2).astype(np.int32))], True, (255, 160, 0), 2)
        cv2.putText(view, f"captured {len(img)}", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        cv2.imshow(win, cv2.resize(view, None, fx=0.5, fy=0.5))
        k = cv2.waitKey(1) & 0xFF
        if k == ord("q"):
            return
        if k == ord(" ") and c is not None:
            full = find_board(f)
            if full is not None:
                obj.append(objp)
                img.append(full)
                print(f"  captured {len(img)}")
        if k == ord("c") and len(img) >= 12:
            break
    cv2.destroyAllWindows()
    rms, K, dist, _, _ = cv2.calibrateCamera(obj, img, cam.size, None, None)
    print(f"reprojection error {rms:.3f} px over {len(img)} views "
          f"({'good' if rms < 0.5 else 'usable' if rms < 1 else 'poor - recapture'})")
    save_json("intrinsics.json", {"K": K.tolist(), "dist": dist.ravel().tolist(),
                                  "size": list(cam.size), "rms": rms,
                                  "focus": cam.settings["focus"]})


def cmd_calibrate(args):
    intr = need("intrinsics.json", "intrinsics")
    cam, table = open_rig_devices(args)
    if intr["focus"] != cam.settings["focus"]:
        sys.exit(f"Focus is {cam.settings['focus']} but intrinsics were taken at "
                 f"{intr['focus']} - rerun intrinsics at this focus.")
    K, dist = np.array(intr["K"]), np.array(intr["dist"])
    objp = board_points()
    print("Board standing upright on the platter, facing the camera, 3-6 cm off "
          "the centre. One revolution in 10° steps follows.")
    flush = measure_latency(cam, table)
    poses, laser_pts = [], {LEFT: [], RIGHT: []}
    n = 36
    table.preload()
    try:
        for i, inc in enumerate(distribute(round(360 / NOMINAL_DEG_PER_STEP), n)):
            off = cam.grab()
            c = find_board(off)
            if c is not None:
                c = c.reshape(-1, 2)
                if c[0, 1] > c[-1, 1]:          # canonical order: first corner on top
                    c = c[::-1].copy()
                ok, rvec, tvec = cv2.solvePnP(objp, c, K, dist)
                R = cv2.Rodrigues(rvec)[0]
                t = tvec.ravel()
                poses.append((table.pos, R, t))
                inner = np.zeros(off.shape[:2], np.uint8)
                cv2.fillConvexPoly(inner, cv2.convexHull(c.astype(np.int32)), 1)
                got = []
                for m in (LEFT, RIGHT):
                    table.laser(m)
                    rows, cols = extract_line(cam.grab(), off, inner.astype(bool))
                    n_board = R[:, 2]
                    X = intersect(pixel_rays(rows, cols, K, dist), n_board, -n_board @ t)
                    if len(X) > 30:
                        laser_pts[m].append(X)
                    got.append(f"{LASERS[m]} {len(X)}")
                table.laser(0)
                print(f"  {i + 1:2d}/{n}  board at {np.linalg.norm(t):.0f} mm, laser pts: {', '.join(got)}")
            else:
                print(f"  {i + 1:2d}/{n}  -")
            table.step(inc)
    finally:
        table.release()

    if len(poses) < 4:
        sys.exit(f"Board seen in only {len(poses)} positions - need 4+. Check it's in "
                 "frame, lit, and facing the camera at the start.")

    axis, c, dps, spread = fit_axis(poses)
    if abs(dps / NOMINAL_DEG_PER_STEP - 1) > 0.03:
        print(f"! measured {dps:.5f}°/step is >3 % off the gear ratio's "
              f"{NOMINAL_DEG_PER_STEP:.5f} - using the nominal value. Check for slip.")
        dps = NOMINAL_DEG_PER_STEP

    planes, report = {}, []
    for m, chunks in laser_pts.items():
        if len(chunks) < 2:
            sys.exit(f"The {LASERS[m]} laser hit the board in only {len(chunks)} "
                     "positions - need 2+. Is it on, aimed at the platter centre, "
                     "and is its line vertical?")
        pts = np.vstack(chunks)
        nrm, d, rms, sv = fit_plane(pts)
        planes[m] = nrm.tolist() + [float(d)]
        report.append(f"  {LASERS[m]} laser plane: {len(pts)} pts from {len(chunks)} "
                      f"views, fit error {rms:.3f} mm")
    data = {"K": intr["K"], "dist": intr["dist"], "planes": planes,
            "axis_dir": axis.tolist(), "axis_point": c.tolist(), "deg_per_step": dps,
            "flush": flush}
    rig = Rig(data)
    cam_dist = np.linalg.norm(rig.to_table(np.zeros(3))[:2])
    print(f"\n  board seen in {len(poses)} of {n} positions")
    print(f"  turntable axis: {cam_dist:.1f} mm from the lens (design: 200), "
          f"axis estimates agree to {spread:.2f}°")
    print(f"  {dps:.5f}°/step measured vs {NOMINAL_DEG_PER_STEP:.5f} from the gear ratio")
    print("\n".join(report))
    save_json("rig.json", data)


def cmd_scan(args):
    rig = Rig(need("rig.json", "calibrate"))
    cam, table = open_rig_devices(args)
    roi = rig.roi(cam.size)
    measure_latency(cam, table)
    n = round(360 / args.step_deg)
    total = round(360 / rig.deg_per_step)
    pts, cols, cams = [], [], []
    cam_center = np.zeros((1, 3))
    print(f"Scanning: {n} positions x 2 lasers ({360 / n:.2f}° apart)...")
    t0 = time.time()
    table.preload()
    try:
        for i, inc in enumerate(distribute(total, n)):
            off = cam.grab()
            for m in (LEFT, RIGHT):
                table.laser(m)
                rows, c = extract_line(cam.grab(), off, roi, thresh=args.threshold)
                if len(rows):
                    X = intersect(pixel_rays(rows, c, rig.K, rig.dist), *rig.planes[m])
                    P = rig.to_object(X, table.pos)
                    pts.append(P)
                    ri, ci = rows.astype(int), np.clip(np.round(c).astype(int), 0, off.shape[1] - 1)
                    cols.append(off[ri, ci, ::-1])
                    cams.append(np.repeat(rig.to_object(cam_center, table.pos), len(P), axis=0))
            table.laser(0)
            if (i + 1) % 20 == 0:
                left = (time.time() - t0) / (i + 1) * (n - i - 1)
                print(f"  {i + 1}/{n}  {sum(map(len, pts))} points  ~{left / 60:.1f} min left")
            table.step(inc)
    finally:
        table.release()
    if not pts:
        sys.exit("No laser points at all - check the lasers light the object in preview.")
    P, C, V = np.vstack(pts), np.vstack(cols), np.vstack(cams)
    keep = np.hypot(P[:, 0], P[:, 1]) < PLATTER_R          # drop anything off the platter
    P, C, V = P[keep], C[keep], V[keep]
    SCANS.mkdir(exist_ok=True)
    base = SCANS / args.name
    np.savez_compressed(base.with_suffix(".npz"), points=P, colors=C, cams=V)
    import open3d as o3d
    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(P))
    pcd.colors = o3d.utility.Vector3dVector(C / 255.0)
    o3d.io.write_point_cloud(str(base.with_suffix(".ply")), pcd)
    print(f"{len(P)} points in {(time.time() - t0) / 60:.1f} min -> {base}.ply / .npz")
    if not args.no_mesh:
        make_mesh(P, V, base.with_suffix(".stl"), args.depth)


def cmd_mesh(args):
    d = np.load(args.npz)
    out = Path(args.out) if args.out else Path(args.npz).with_suffix(".stl")
    make_mesh(d["points"], d["cams"], out, args.depth)


def make_mesh(P, V, out, depth=9, floor=0.8):
    """Points -> watertight STL. Removes the platter, closes the base flat,
    and Poisson-meshes with normals facing the camera that saw each point."""
    import open3d as o3d
    # The platter shows up as a dense height: laser light on it beside the
    # object in every profile. A flat object top can be dense too, so take the
    # LOWEST strong peak rather than the strongest.
    hist, edges = np.histogram(P[:, 2], bins=np.arange(P[:, 2].min(), P[:, 2].max() + 0.2, 0.2))
    z0 = edges[np.nonzero(hist > 0.3 * hist.max())[0][0]] + 0.1
    P, V = P.copy(), V.copy()
    P[:, 2] -= z0
    V[:, 2] -= z0
    keep = P[:, 2] > floor
    P, V = P[keep], V[keep]
    if len(P) < 1000:
        sys.exit(f"Only {len(P)} points above the platter - nothing to mesh.")

    # Voxel-average in numpy so each point keeps the mean viewpoint of what it
    # merged (Open3D's own downsampler would normalise anything stored as a normal).
    vox = 0.25
    _, inv, cnt = np.unique(np.floor(P / vox).astype(np.int64), axis=0,
                            return_inverse=True, return_counts=True)
    inv = inv.ravel()
    P = np.stack([np.bincount(inv, P[:, k]) for k in range(3)], axis=1) / cnt[:, None]
    V = np.stack([np.bincount(inv, V[:, k]) for k in range(3)], axis=1) / cnt[:, None]
    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(P))
    _, ind = pcd.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)
    P, V = P[ind], V[ind]

    # Close the bottom: the object's footprint at the platter, filled with
    # points facing down, so Poisson builds a flat base instead of ballooning
    # out of an open end. Added after the outlier filter, and on the same grid
    # as the scan, or the filter would see the whole cap as sparse outliers.
    band = P[P[:, 2] < floor + 2.5]
    if len(band) > 50:
        lo = band[:, :2].min(axis=0) - 5
        ij = ((band[:, :2] - lo) / vox).astype(int)
        img = np.zeros(ij.max(axis=0)[::-1] + 24, np.uint8)
        img[ij[:, 1], ij[:, 0]] = 255
        img = cv2.morphologyEx(img, cv2.MORPH_CLOSE, np.ones((17, 17), np.uint8))
        cnts, _ = cv2.findContours(img, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(img, cnts, -1, 255, cv2.FILLED)
        yy, xx = np.nonzero(img)
        cap = np.column_stack([xx * vox + lo[0], yy * vox + lo[1], np.zeros(len(xx))])
        P = np.vstack([P, cap])
        V = np.vstack([V, cap - [0, 0, 50]])       # "seen" from below -> normals down

    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(P))
    pcd.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=2.0, max_nn=30))
    N = np.asarray(pcd.normals)
    flip = np.einsum("ij,ij->i", N, V - P) < 0
    N[flip] *= -1
    pcd.normals = o3d.utility.Vector3dVector(N)

    # No density trimming: with the base capped the cloud is closed, and the
    # surface Poisson bridges across unseen pockets is what makes it printable.
    # Trimming low-density vertices would punch holes and break watertightness.
    mesh, _ = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=depth)
    # Poisson can leave detached blobs where the data is thin; keep the object.
    tri, ntri, _ = mesh.cluster_connected_triangles()
    mesh.remove_triangles_by_mask(np.asarray(tri) != np.asarray(ntri).argmax())
    mesh.remove_unreferenced_vertices()
    bb = mesh.get_axis_aligned_bounding_box()
    mesh.compute_triangle_normals()
    o3d.io.write_triangle_mesh(str(out), mesh)
    ext = bb.get_extent()
    # Open edges, not mesh.is_watertight(): that also runs a self-intersection
    # test which takes minutes on a mesh this size.
    open_edges = len(np.asarray(mesh.get_non_manifold_edges(allow_boundary_edges=False)))
    print(f"mesh: {len(mesh.triangles)} triangles, {ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm, "
          f"{'closed' if open_edges == 0 else f'{open_edges} open/non-manifold edges'} -> {out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--camera", default="brio", help="brio, c920, or a USB vid:pid")
    ap.add_argument("--port", help="ScanTable serial port (auto-detected)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("board")
    p.add_argument("out", nargs="?", default="calib-board.svg")
    sub.add_parser("preview")
    sub.add_parser("intrinsics")
    sub.add_parser("calibrate")
    p = sub.add_parser("scan")
    p.add_argument("name")
    p.add_argument("--step-deg", type=float, default=0.7, help="turntable increment (default 0.7°)")
    p.add_argument("--threshold", type=float, default=15, help="laser detection threshold")
    p.add_argument("--depth", type=int, default=9, help="Poisson depth (10 = finer, slower)")
    p.add_argument("--no-mesh", action="store_true")
    p = sub.add_parser("mesh")
    p.add_argument("npz")
    p.add_argument("out", nargs="?")
    p.add_argument("--depth", type=int, default=9)
    args = ap.parse_args()
    {"board": cmd_board, "preview": cmd_preview, "intrinsics": cmd_intrinsics,
     "calibrate": cmd_calibrate, "scan": cmd_scan, "mesh": cmd_mesh}[args.cmd](args)


if __name__ == "__main__":
    main()
