"""Cut seamless wallpaper loops from Creative Commons films (Blender Studio open movies).

Usage:
    python3 make_loops.py --source /path/to/film.mp4 --segments segments.json --out dist/films

For each segment the script:
  1. cuts `duration + crossfade` seconds starting at `start`,
  2. crossfades the tail into the head so the loop has no visible seam,
  3. encodes a 4K master (HEVC via VideoToolbox when available) and a 720p H.264 preview,
  4. grabs a poster frame,
and writes catalog entries (catalog/open-films.json) that point at a GitHub Release.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

RELEASE_BASE = "https://github.com/shorielol/driftwall/releases/download/films-v1"
CROSSFADE_SECONDS = 1.0


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-2000:])
        raise SystemExit(f"command failed: {' '.join(cmd[:6])} …")


def encoder() -> list[str]:
    encoders = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    if "hevc_videotoolbox" in encoders:
        return ["-c:v", "hevc_videotoolbox", "-q:v", "62", "-tag:v", "hvc1"]
    return ["-c:v", "libx264", "-crf", "18", "-preset", "slow"]


def make_loop(source: Path, seg: dict, out: Path) -> dict:
    slug = seg["slug"]
    start, duration = float(seg["start"]), float(seg["duration"])
    fade = CROSSFADE_SECONDS
    master = out / f"{slug}-2160.mp4"
    preview = out / f"{slug}-720.mp4"
    poster = out / f"{slug}.jpg"
    # Loop of length D: the first F seconds blend the clip's tail (D..D+F) into its head (0..F),
    # then the rest (F..D) plays as-is, so the last frame flows straight into the first.
    loop_filter = (
        f"[0:v]split=3[a][b][c];"
        f"[a]trim=0:{fade},setpts=PTS-STARTPTS[head];"
        f"[b]trim={fade}:{duration},setpts=PTS-STARTPTS[rest];"
        f"[c]trim={duration}:{duration + fade},setpts=PTS-STARTPTS[tail];"
        f"[tail][head]xfade=transition=fade:duration={fade}:offset=0[blend];"
        f"[blend][rest]concat=n=2:v=1:a=0,format=yuv420p[v]"
    )
    run(["ffmpeg", "-y", "-ss", str(start), "-t", str(duration + fade + 0.5), "-i", str(source),
         "-filter_complex", loop_filter, "-map", "[v]", "-an", *encoder(), "-movflags", "+faststart", str(master)])
    run(["ffmpeg", "-y", "-i", str(master), "-vf", "scale=-2:720", "-an", "-c:v", "libx264", "-crf", "24",
         "-preset", "medium", "-movflags", "+faststart", str(preview)])
    run(["ffmpeg", "-y", "-ss", str(min(2.0, duration / 2)), "-i", str(master), "-frames:v", "1",
         "-vf", "scale=1280:-2,format=yuvj420p", "-q:v", "3", str(poster)])
    probe = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
         "-of", "json", str(master)], capture_output=True, text=True).stdout)["streams"][0]
    return {
        "id": f"film-{slug}",
        "title": seg["title"],
        "description": seg.get("description", ""),
        "category": seg.get("category", "Animated"),
        "tags": seg.get("tags", []),
        "source": "blender",
        "sourcePageUrl": seg["sourcePageUrl"],
        "previewUrl": f"{RELEASE_BASE}/{preview.name}",
        "videoUrl": f"{RELEASE_BASE}/{master.name}",
        "posterUrl": f"{RELEASE_BASE}/{poster.name}",
        "author": seg["author"],
        "license": seg["license"],
        "licenseUrl": seg["licenseUrl"],
        "durationSeconds": int(round(duration)),
        "width": int(probe["width"]),
        "height": int(probe["height"]),
        "fileSizeMB": round(master.stat().st_size / 1_000_000, 1),
        "uploadedAt": "",
        "sourceRank": int(seg.get("rank", 0)),
        "addedInDrop": "",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--segments", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("dist/films"))
    parser.add_argument("--catalog", type=Path, default=Path("catalog/open-films.json"))
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required (brew install ffmpeg)")
    args.out.mkdir(parents=True, exist_ok=True)
    segments = json.loads(args.segments.read_text())
    entries = [make_loop(args.source, seg, args.out) for seg in segments]
    existing = json.loads(args.catalog.read_text()) if args.catalog.exists() else []
    by_id = {e["id"]: e for e in existing} | {e["id"]: e for e in entries}
    args.catalog.parent.mkdir(parents=True, exist_ok=True)
    args.catalog.write_text(json.dumps(list(by_id.values()), indent=2) + "\n")
    print(f"{len(entries)} loops written to {args.out}; catalog entries in {args.catalog}")


if __name__ == "__main__":
    main()
