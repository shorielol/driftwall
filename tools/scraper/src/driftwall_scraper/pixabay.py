"""Optional source: Pixabay official Videos API (needs PIXABAY_API_KEY). Best for anime-style and
illustrated loops. Keeps landscape renditions of at least 1080p, highest first."""

from __future__ import annotations

import json
import logging
import urllib.parse
import urllib.request
from typing import Any

from .mixkit import is_wallpaper_worthy
from .models import Wallpaper

log = logging.getLogger(__name__)

API_URL = "https://pixabay.com/api/videos/"
LICENSE_NAME = "Pixabay Content License"
LICENSE_URL = "https://pixabay.com/service/license-summary/"
MIN_HEIGHT = 1080
PER_PAGE = 50
TIMEOUT_SECONDS = 30
RENDITIONS = ("large", "medium", "small", "tiny")


def _renditions(video: dict[str, Any]) -> list[dict[str, Any]]:
    found = []
    for name in RENDITIONS:
        item = (video.get("videos") or {}).get(name)
        if isinstance(item, dict) and item.get("url"):
            found.append({**item, "width": int(item["width"]), "height": int(item["height"])})
    return found


def _title(tags: str) -> str:
    words = [t.strip() for t in tags.split(",") if t.strip()][:4]
    return " ".join(w.title() for w in words) or "Untitled"


def _parse_video(video: dict[str, Any], category: str, rank: int) -> Wallpaper | None:
    try:
        renditions = _renditions(video)
        video_id = int(video["id"])
        page_url = str(video["pageURL"])
        title = _title(str(video.get("tags", "")))
        duration = int(video.get("duration") or 0)
        author = str(video.get("user") or "Pixabay")
    except (KeyError, TypeError, ValueError, AttributeError):
        return None
    if category != "Anime" and not is_wallpaper_worthy(title, "", ()):
        return None
    eligible = [r for r in renditions if r["height"] >= MIN_HEIGHT and r["width"] > r["height"]]
    if not eligible:
        return None
    best = max(eligible, key=lambda r: r["width"] * r["height"])
    preview = min((r for r in renditions if r["width"] > r["height"]), key=lambda r: abs(r["height"] - 720))
    poster = str(best.get("thumbnail") or preview.get("thumbnail") or "")
    if not poster.startswith("https://"):
        return None
    return Wallpaper(
        id=f"pixabay-{video_id}",
        title=title,
        description="",
        category=category,
        tags=tuple(t.strip() for t in str(video.get("tags", "")).split(",") if t.strip()),
        source="pixabay",
        source_page_url=page_url,
        preview_url=str(preview["url"]),
        video_url=str(best["url"]),
        poster_url=poster,
        author=author,
        license_name=LICENSE_NAME,
        license_url=LICENSE_URL,
        duration_seconds=duration,
        width=best["width"],
        height=best["height"],
        file_size_mb=round(float(best.get("size") or 0) / 1_000_000, 2),
        uploaded_at="",
        source_rank=rank,
    )


def parse_search(payload: dict[str, Any], category: str, rank_offset: int) -> list[Wallpaper]:
    results: list[Wallpaper] = []
    for index, video in enumerate(payload.get("hits", []) or []):
        if isinstance(video, dict):
            item = _parse_video(video, category, rank_offset + index)
            if item is not None:
                results.append(item)
    return results


def search_pixabay(query: str, category: str, api_key: str, rank_offset: int = 0) -> list[Wallpaper]:
    params = urllib.parse.urlencode(
        {"key": api_key, "q": query, "per_page": PER_PAGE, "safesearch": "true", "order": "popular"}
    )
    try:
        with urllib.request.urlopen(f"{API_URL}?{params}", timeout=TIMEOUT_SECONDS) as response:  # noqa: S310 fixed https host
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as error:  # network boundary
        log.warning("pixabay search failed for %r: %s", query, type(error).__name__)
        return []
    return parse_search(payload, category, rank_offset)
