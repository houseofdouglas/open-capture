# open-capture

A fully DIY object-scanning setup for turning real objects into 3D-printable
replicas — **no LiDAR, no NVIDIA GPU, no paid software**. A phone camera plus
a printed motorized turntable feed Apple's built-in photogrammetry engine,
and the result is cleaned up into a printable STL.

It has two halves:

1. **`photogrammetry`** — a tiny macOS command-line wrapper around Apple's
   RealityKit Object Capture. Point it at a folder of photos, get a 3D model.
2. **`scanner_rig/`** — a printable, motorized photogrammetry rig: a turntable
   driven by a 28BYJ-48 stepper and an iPhone cradle, with an ESP32 that
   rotates the table and fires the camera shutter over Bluetooth. One button
   press = one full revolution of evenly spaced photos, hands-free.

## Pipeline

```
object on turntable  ──►  ~144 photos (3 tilt orbits)  ──►  photogrammetry CLI
      ──►  .usdz mesh  ──►  Blender cleanup  ──►  STL  ──►  slice & print
```

## Quick start (software)

Build the photogrammetry CLI (macOS, Apple silicon, Xcode toolchain):

```bash
swiftc -O -parse-as-library -o photogrammetry photogrammetry.swift
```

Pull the latest scan session out of the Photos library (iCloud Photos brings
the iPhone shots over on its own; requires `uv tool install osxphotos`), then
reconstruct:

```bash
./pull_photos.py ./photos
./photogrammetry ./photos ./model.usdz -d full -f high
```

`pull_photos.py` clusters recent iPhone shots by timestamp, so one "session"
is one scan run; `--list` shows recent sessions, `--session N` picks an older
one. Note iCloud can sync a session tail-first — make sure the photo count
matches the run before reconstructing.

To get a printable STL without manual Blender work (drops floating debris,
voxel-remeshes watertight, exports in mm — scale to the object's measured
size in the slicer, since reconstruction scale is approximate):

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P usdz_to_stl.py -- model.usdz model.stl
```

`-d` detail: `preview | reduced | medium | full | raw`  ·  `-f` feature
sensitivity: `normal | high`. Run a quick `-d medium` pass first to check
photo coverage before committing to a long `full` run.

## The rig

See **[`scanner_rig/README.md`](scanner_rig/README.md)** for the bill of
materials (~$15 of electronics), print list, wiring, and assembly. All parts
are parametric OpenSCAD and print without supports. Firmware and the exact,
verified library versions are in
**[`scanner_rig/firmware/turntable_shutter/`](scanner_rig/firmware/turntable_shutter/)**
(see `LIBRARIES.md` there — the ESP32-C3 needs the NimBLE keyboard stack).

## Capture tips (these matter more than the software)

- Even, diffuse light; matte-coat shiny or featureless objects.
- A **plain, featureless backdrop** behind the turntable — if the software can
  see background texture, it concludes the object never moved and the
  reconstruction fails.
- Lots of overlapping photos from several heights (the cradle's tilt stops).
- Include a ruler in a couple of shots so you can scale the model correctly.

## Laser scanning (alternative)

The same turntable can also drive a laser-line scanner — a webcam, two line
lasers and `laser_scan.py` — that measures in real millimetres and needs no
photogrammetry. See **Laser scanner** in
[`scanner_rig/README.md`](scanner_rig/README.md).

## License

MIT — see [`LICENSE`](LICENSE).
