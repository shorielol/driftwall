"""Cut seamless 4K wallpaper loops from public-domain and Creative Commons sources.

Usage:
    python3 tools/loops/make_loops.py tools/loops/manifests/*.json

Each manifest names one source file (in dist/sources by default), its licence and credit,
and the segments to cut from it. For every segment the script:
  1. cuts the segment and crops it to 16:9 (never upscales; 4K and taller is scaled to 3840x2160),
  2. makes it loop without a seam, either
       - "crossfade": the clip's tail dissolves into its head (good for ambient motion), or
       - "pingpong": the clip plays forward then backward (good for slow camera drifts),
  3. encodes a 4K-class HEVC master, a 720p H.264 preview and a poster frame,
and merges catalog entries into catalog/loops.json, pointing at a GitHub Release.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RELEASE_TAG = "loops-v1"
RELEASE_BASE = f"https://github.com/shorielol/driftwall/releases/download/{RELEASE_TAG}"
CROSSFADE_SECONDS = 1.0
REVERSE_CHUNK_SECONDS = 1.0
MIN_HEIGHT = 1080
UHD_WIDTH, UHD_HEIGHT = 3840, 2160
MODES = ("crossfade", "pingpong")


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-2000:])
        raise SystemExit(f"command failed: {' '.join(cmd[:8])} …")


def probe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height:format=duration", "-of", "json", str(path)],
        capture_output=True, text=True, check=True).stdout
    data = json.loads(out)
    stream = data["streams"][0]
    return {"width": int(stream["width"]), "height": int(stream["height"]),
            "duration": float(data["format"]["duration"])}


# VideoToolbox quality scale is 1-100. 62 starves calm, dark scenes (about 1 Mbps at 4K, visibly
# smeared fog); 80 keeps them near-lossless (SSIM 0.999) at a few Mbps and busy pans at 20-40 Mbps.
VT_QUALITY = 80


def hevc() -> list[str]:
    """A wallpaper is watched full screen for hours, so favour detail over file size."""
    encoders = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    if "hevc_videotoolbox" in encoders:
        return ["-c:v", "hevc_videotoolbox", "-q:v", str(VT_QUALITY), "-tag:v", "hvc1"]
    return ["-c:v", "libx265", "-crf", "18", "-preset", "slow", "-tag:v", "hvc1"]


INTERMEDIATE = ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le", "-an"]


def frame_filter(width: int, height: int, crop_x: float) -> str:
    """Crop to 16:9 around crop_x (0 = left edge, 1 = right edge), then fit 4K without upscaling."""
    if width * 9 > height * 16:  # wider than 16:9: trim the sides
        out_w, out_h = (height * 16 // 9) // 2 * 2, height
    else:  # taller: trim top and bottom
        out_w, out_h = width, (width * 9 // 16) // 2 * 2
    if out_h < MIN_HEIGHT:
        raise SystemExit(f"source crops to {out_w}x{out_h}, below the {MIN_HEIGHT}p floor")
    x = int((width - out_w) * min(max(crop_x, 0.0), 1.0))
    y = (height - out_h) // 2
    chain = f"crop={out_w}:{out_h}:{x}:{y}"
    if out_h > UHD_HEIGHT:
        chain += f",scale={UHD_WIDTH}:{UHD_HEIGHT}:flags=lanczos"
    return chain


def cut(source: Path, start: float, length: float, vf: str, dest: Path) -> None:
    run(["ffmpeg", "-y", "-ss", f"{start}", "-t", f"{length}", "-i", str(source), "-vf", vf, *INTERMEDIATE, str(dest)])


def crossfade_loop(clip: Path, duration: float, dest: Path) -> None:
    """Loop of length D: the first F seconds blend the tail (D..D+F) into the head (0..F)."""
    fade = CROSSFADE_SECONDS
    graph = (
        f"[0:v]split=3[a][b][c];"
        f"[a]trim=0:{fade},setpts=PTS-STARTPTS[head];"
        f"[b]trim={fade}:{duration},setpts=PTS-STARTPTS[rest];"
        f"[c]trim={duration}:{duration + fade},setpts=PTS-STARTPTS[tail];"
        f"[tail][head]xfade=transition=fade:duration={fade}:offset=0[blend];"
        f"[blend][rest]concat=n=2:v=1:a=0,format=yuv420p[v]"
    )
    run(["ffmpeg", "-y", "-i", str(clip), "-filter_complex", graph, "-map", "[v]", "-an", *hevc(),
         "-movflags", "+faststart", str(dest)])


def pingpong_loop(clip: Path, duration: float, work: Path, dest: Path) -> None:
    """Forward then backward. Reverses in short chunks so 4K never has to fit in memory at once."""
    chunks: list[Path] = []
    start = 0.0
    index = 0
    while start < duration - 1e-3:
        length = min(REVERSE_CHUNK_SECONDS, duration - start)
        chunk = work / f"rev{index:03d}.mov"
        run(["ffmpeg", "-y", "-ss", f"{start}", "-t", f"{length}", "-i", str(clip), "-vf", "reverse",
             *INTERMEDIATE, str(chunk)])
        chunks.append(chunk)
        start += length
        index += 1
    listing = work / "reverse.txt"
    listing.write_text("".join(f"file '{c.name}'\n" for c in reversed(chunks)))
    backward = work / "backward.mov"
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(backward)])
    # Drop the repeated frame at each turn (first and last of the backward half) so motion never stalls.
    frames = int(subprocess.run(
        ["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries",
         "stream=nb_read_packets", "-of", "csv=p=0", str(backward)], capture_output=True, text=True).stdout.strip() or 0)
    graph = (
        f"[1:v]trim=start_frame=1:end_frame={max(frames - 1, 2)},setpts=PTS-STARTPTS[back];"
        "[0:v][back]concat=n=2:v=1:a=0,format=yuv420p[v]"
    )
    run(["ffmpeg", "-y", "-i", str(clip), "-i", str(backward), "-filter_complex", graph, "-map", "[v]", "-an",
         *hevc(), "-movflags", "+faststart", str(dest)])


def make_loop(manifest: dict, seg: dict, sources: Path, out: Path) -> dict:
    slug = seg["slug"]
    mode = seg.get("mode", "crossfade")
    if mode not in MODES:
        raise SystemExit(f"{slug}: mode must be one of {MODES}")
    source = sources / manifest["file"]
    if not source.exists():
        raise SystemExit(f"missing source {source}; download it from {manifest.get('url', 'its source page')}")
    info = probe(source)
    vf = frame_filter(info["width"], info["height"], float(seg.get("cropX", 0.5)))
    start, duration = float(seg["start"]), float(seg["duration"])
    master, preview, poster = out / f"{slug}-2160.mp4", out / f"{slug}-720.mp4", out / f"{slug}.jpg"

    with tempfile.TemporaryDirectory(dir=out) as tmp:
        work = Path(tmp)
        clip = work / "clip.mov"
        extra = CROSSFADE_SECONDS + 0.5 if mode == "crossfade" else 0.0
        cut(source, start, duration + extra, vf, clip)
        if mode == "crossfade":
            crossfade_loop(clip, duration, master)
        else:
            pingpong_loop(clip, duration, work, master)

    run(["ffmpeg", "-y", "-i", str(master), "-vf", "scale=-2:720", "-an", "-c:v", "libx264", "-crf", "24",
         "-preset", "medium", "-movflags", "+faststart", str(preview)])
    poster_at = float(seg.get("posterAt", min(2.0, duration / 2)))
    run(["ffmpeg", "-y", "-ss", f"{poster_at}", "-i", str(master), "-frames:v", "1",
         "-vf", "scale=1280:-2,format=yuvj420p", "-q:v", "3", str(poster)])
    final = probe(master)
    return {
        "id": f"loop-{slug}",
        "title": seg["title"],
        "description": seg.get("description", ""),
        "category": seg.get("category", manifest["category"]),
        "tags": seg.get("tags", []),
        "source": manifest["source"],
        "sourcePageUrl": manifest["sourcePageUrl"],
        "previewUrl": f"{RELEASE_BASE}/{preview.name}",
        "videoUrl": f"{RELEASE_BASE}/{master.name}",
        "posterUrl": f"{RELEASE_BASE}/{poster.name}",
        "author": manifest["author"],
        "license": manifest["license"],
        "licenseUrl": manifest["licenseUrl"],
        "durationSeconds": max(1, int(round(final["duration"]))),
        "width": final["width"],
        "height": final["height"],
        "fileSizeMB": round(master.stat().st_size / 1_000_000, 1),
        "uploadedAt": "",
        "sourceRank": int(seg.get("rank", 0)),
        "addedInDrop": "",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--sources", type=Path, default=Path("dist/sources"))
    parser.add_argument("--out", type=Path, default=Path("dist/loops"))
    parser.add_argument("--catalog", type=Path, default=Path("catalog/loops.json"))
    parser.add_argument("--only", help="comma-separated slugs to (re)build")
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required (brew install ffmpeg)")
    args.out.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None

    entries = []
    for path in args.manifests:
        manifest = json.loads(path.read_text())
        for seg in manifest["segments"]:
            if only and seg["slug"] not in only:
                continue
            print(f"• {seg['slug']} ({seg.get('mode', 'crossfade')})", flush=True)
            entries.append(make_loop(manifest, seg, args.sources, args.out))

    existing = json.loads(args.catalog.read_text()) if args.catalog.exists() else []
    by_id = {e["id"]: e for e in existing} | {e["id"]: e for e in entries}
    args.catalog.parent.mkdir(parents=True, exist_ok=True)
    args.catalog.write_text(json.dumps(sorted(by_id.values(), key=lambda e: e["sourceRank"]), indent=2) + "\n")
    print(f"{len(entries)} loops written to {args.out}; {len(by_id)} entries in {args.catalog}")


if __name__ == "__main__":
    main()
