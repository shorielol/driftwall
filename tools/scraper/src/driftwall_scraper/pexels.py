"""Optional source: Pexels official Videos API (needs PEXELS_API_KEY). Keeps landscape 4K only."""

from __future__ import annotations

import json
import logging
import re
import urllib.parse
import urllib.request
from typing import Any

from .mixkit import is_wallpaper_worthy
from .models import Wallpaper

log = logging.getLogger(__name__)

API_URL = "https://api.pexels.com/videos/search"
LICENSE_NAME = "Pexels License"
LICENSE_URL = "https://www.pexels.com/license/"
MIN_HEIGHT = 1080
PREVIEW_MAX_HEIGHT = 1080
PER_PAGE = 40
TIMEOUT_SECONDS = 30
_SLUG = re.compile(r"/video/([a-z0-9-]+?)-\d+/?$")


def _title_from_url(url: str) -> str:
    match = _SLUG.search(url)
    return match.group(1).replace("-", " ").title() if match else "Untitled"


def _parse_video(video: dict[str, Any], category: str, rank: int) -> Wallpaper | None:
    try:
        files = [
            {**f, "width": int(f["width"]), "height": int(f["height"])}
            for f in video["video_files"]
            if isinstance(f, dict) and f.get("link") and f.get("width") and f.get("height")
        ]
        width, height = int(video["width"]), int(video["height"])
        page_url = str(video["url"])
        video_id = int(video["id"])
        author = str((video.get("user") or {}).get("name") or "Pexels")
        duration = int(video.get("duration") or 0)
    except (KeyError, TypeError, ValueError, AttributeError):
        return None
    title = _title_from_url(page_url)
    if category != "Anime" and not is_wallpaper_worthy(title, "", ()):
        return None
    if width <= height:
        return None
    eligible = [f for f in files if f["height"] >= MIN_HEIGHT and f["width"] > f["height"]]
    previews = [f for f in files if f["height"] <= PREVIEW_MAX_HEIGHT and f["width"] > f["height"]]
    if not eligible or not previews:
        return None
    best = max(eligible, key=lambda f: f["width"] * f["height"])
    preview = min(previews, key=lambda f: abs(f["height"] - 720))
    return Wallpaper(
        id=f"pexels-{video_id}",
        title=title,
        description="",
        category=category,
        tags=(),
        source="pexels",
        source_page_url=page_url,
        preview_url=str(preview["link"]),
        video_url=str(best["link"]),
        poster_url=str(video.get("image", "")),
        author=author,
        license_name=LICENSE_NAME,
        license_url=LICENSE_URL,
        duration_seconds=duration,
        width=int(best["width"]),
        height=int(best["height"]),
        file_size_mb=0.0,
        uploaded_at="",
        source_rank=rank,
    )


def parse_search(payload: dict[str, Any], category: str, rank_offset: int) -> list[Wallpaper]:
    results: list[Wallpaper] = []
    for index, video in enumerate(payload.get("videos", []) or []):
        if isinstance(video, dict):
            item = _parse_video(video, category, rank_offset + index)
            if item is not None:
                results.append(item)
    return results


def search_pexels(query: str, category: str, api_key: str, rank_offset: int = 0) -> list[Wallpaper]:
    params = urllib.parse.urlencode(
        {"query": query, "orientation": "landscape", "size": "large", "per_page": PER_PAGE}
    )
    request = urllib.request.Request(f"{API_URL}?{params}", headers={"Authorization": api_key})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310 fixed https host
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as error:  # network boundary
        log.warning("pexels search failed for %r: %s", query, error)
        return []
    return parse_search(payload, category, rank_offset)
