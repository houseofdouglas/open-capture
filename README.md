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

Reconstruct a model from a folder of photos:

```bash
./photogrammetry ./photos ./model.usdz -d full -f high
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

## License

MIT — see [`LICENSE`](LICENSE).
