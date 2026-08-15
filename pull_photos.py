#!/usr/bin/env python3
"""Pull the latest scan session out of the macOS Photos library.

The rig fires the iPhone's Camera app, so shots land in Photos and sync to
this Mac via iCloud. A scan session is a tight burst (48-144 shots, seconds
apart), so sessions are detected by clustering photo timestamps: any gap
longer than --gap minutes starts a new session.

Requires osxphotos (`uv tool install osxphotos`).

Usage:
  ./pull_photos.py                 # export latest session to ./photos-YYYYMMDD-HHMM/
  ./pull_photos.py ./photos        # export latest session to ./photos/
  ./pull_photos.py --list          # show sessions found in the window, export nothing
  ./pull_photos.py --session 2     # export the 2nd-most-recent session
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

GAP_MINUTES = 10
WINDOW_HOURS = 48


def find_osxphotos() -> str:
    exe = shutil.which("osxphotos") or shutil.which(
        "osxphotos", path=str(Path.home() / ".local/bin")
    )
    if not exe:
        sys.exit("osxphotos not found — install it with: uv tool install osxphotos")
    return exe


def query_window(exe: str, hours: int) -> list[dict]:
    since = (datetime.now() - timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%S")
    out = subprocess.run(
        [exe, "query", "--from-date", since, "--only-photos", "--json"],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out) if out.strip() else []


def scan_shots(photos: list[dict]) -> list[dict]:
    """Keep only real camera stills: shot on an iPhone, not a screenshot."""
    keep = []
    for p in photos:
        model = (p.get("exif_info") or {}).get("camera_model") or ""
        if p.get("screenshot") or not model.startswith("iPhone"):
            continue
        p["_dt"] = datetime.fromisoformat(p["date"])
        keep.append(p)
    keep.sort(key=lambda p: p["_dt"])
    return keep


def sessions_of(shots: list[dict], gap_minutes: int) -> list[list[dict]]:
    """Split time-sorted shots into sessions; newest session first."""
    sessions: list[list[dict]] = []
    for p in shots:
        if sessions and p["_dt"] - sessions[-1][-1]["_dt"] <= timedelta(minutes=gap_minutes):
            sessions[-1].append(p)
        else:
            sessions.append([p])
    sessions.reverse()
    return sessions


def describe(s: list[dict]) -> str:
    start, end = s[0]["_dt"], s[-1]["_dt"]
    phones = len({(p.get("exif_info") or {}).get("camera_model") for p in s})
    extra = f", {phones} phone models" if phones > 1 else ""
    return (f"{len(s):4d} photos  {start:%a %b %d %H:%M} – {end:%H:%M}"
            f"  ({s[0]['original_filename']} … {s[-1]['original_filename']}{extra})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dest", nargs="?", help="export directory (default photos-<session time>)")
    ap.add_argument("--hours", type=int, default=WINDOW_HOURS,
                    help=f"look-back window (default {WINDOW_HOURS})")
    ap.add_argument("--gap", type=int, default=GAP_MINUTES,
                    help=f"minutes of silence that separate sessions (default {GAP_MINUTES})")
    ap.add_argument("--session", type=int, default=1, metavar="N",
                    help="export the Nth most recent session (default 1)")
    ap.add_argument("--list", action="store_true", help="list sessions and exit")
    args = ap.parse_args()

    exe = find_osxphotos()
    shots = scan_shots(query_window(exe, args.hours))
    sessions = sessions_of(shots, args.gap)
    if not sessions:
        sys.exit(f"No iPhone photos in the last {args.hours} h. "
                 "If you just shot them, iCloud may still be syncing — retry in a minute, "
                 "or raise --hours.")

    if args.list:
        for i, s in enumerate(sessions, 1):
            print(f"[{i}] {describe(s)}")
        return

    if args.session > len(sessions):
        sys.exit(f"Only {len(sessions)} session(s) in the window — see --list.")
    session = sessions[args.session - 1]
    print(f"Session: {describe(session)}")

    dest = Path(args.dest) if args.dest else Path(f"photos-{session[0]['_dt']:%Y%m%d-%H%M}")
    dest.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write("\n".join(p["uuid"] for p in session))
        uuid_file = f.name
    try:
        subprocess.run(
            [exe, "export", str(dest), "--uuid-from-file", uuid_file,
             "--skip-live", "--download-missing", "--update", "--no-progress"],
            check=True,
        )
    finally:
        Path(uuid_file).unlink()

    n = sum(1 for f in dest.iterdir() if not f.name.startswith("."))
    print(f"\n{n} photos in {dest}/")
    print(f"Next: ./photogrammetry {dest} ./model.usdz -d medium  (coverage check)")


if __name__ == "__main__":
    main()
