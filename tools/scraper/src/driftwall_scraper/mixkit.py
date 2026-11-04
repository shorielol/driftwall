"""Pure HTML parsers for Mixkit listing and detail pages (no network here)."""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from typing import Any

from scrapling.parser import Selector

from .models import Wallpaper

log = logging.getLogger(__name__)

BASE_URL = "https://mixkit.co"
FREE_LICENSE_NAME = "Mixkit Stock Video Free License"
FREE_LICENSE_URL = "https://mixkit.co/license/#videoFree"
MIN_HEIGHT = 1080  # never publish below Full HD
UHD_HEIGHT = 2160
_ID_FROM_PATH = re.compile(r"-(\d+)/?$")
_DURATION = re.compile(r"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$")
_RESOLUTION = re.compile(r"(\d{3,5})\s*x\s*(\d{3,5})")
# Desktop wallpapers should be scenery, not people or office close-ups.
_PEOPLE_WORDS = (
    r"wom[ae]n|m[ae]n|people|persons?|girls?|boys?|guys?|lady|ladies|couples?|famil(?:y|ies)|"
    r"child(?:ren)?|kids?|bab(?:y|ies)|gentlem[ae]n|crowds?|hands?|fingers?|faces?|portraits?|selfies?|"
    r"typing|laptops?|keyboards?|(?:smart)?phones?|offices?|business\w*|doctors?|workers?|meetings?|"
    r"dancers?|dancing|models?|tourists?|athletes?|players?|friends?|gamers?|gaming|group|teams?|students?|dogs?|puppy|puppies|"
    r"artists?|painters?|djs?|dj's|musicians?|singers?|comics?|comic-book|poker|casino|cards|tablet|screens?|television|tv|"
    r"controller|turntables?|vinyl|records?|recorder|brushes|palette|easel"
)
# Hyphen-aware word boundaries, so "Man-made lake" and "Hand-held shot" stay in.
_UNSUITABLE = re.compile(rf"(?<![\w-])(?:{_PEOPLE_WORDS})(?![\w-])", re.IGNORECASE)
_UNSUITABLE_TAG = re.compile(rf"^(?:{_PEOPLE_WORDS})$", re.IGNORECASE)
MIN_DURATION_SECONDS = 6


@dataclass(frozen=True)
class ListingCard:
    item_id: str
    detail_path: str
    is_4k: bool
    rank: int


@dataclass(frozen=True)
class DownloadOption:
    label: str
    width: int
    height: int
    size_mb: float


def parse_listing(html: str) -> list[ListingCard]:
    page = Selector(html)
    cards: list[ListingCard] = []
    for rank, card in enumerate(page.css("div.item-grid-card")):
        player = card.css("div.item-grid-video-player").first
        link = card.css("a.item-grid-video-player__overlay-link").first
        if player is None or link is None:
            continue
        item_id = player.attrib.get("data-item-grid--video-player-item-id-value", "")
        href = link.attrib.get("href", "")
        if not item_id or not href:
            continue
        classes = player.attrib.get("class", "")
        cards.append(
            ListingCard(
                item_id=item_id,
                detail_path=href,
                is_4k="item-grid-video-player--4k" in classes,
                rank=rank,
            )
        )
    return cards


def parse_duration(value: str) -> int:
    match = _DURATION.match(value or "")
    if not match:
        return 0
    hours, minutes, seconds = (int(g) if g else 0 for g in match.groups())
    return hours * 3600 + minutes * 60 + seconds


def _video_object(page: Selector) -> dict[str, Any] | None:
    for script in page.css('script[type="application/ld+json"]'):
        try:
            data = json.loads(script.text or "")
        except json.JSONDecodeError:
            continue
        nodes = data.get("@graph", [data]) if isinstance(data, dict) else []
        for node in nodes:
            if isinstance(node, dict) and node.get("@type") == "VideoObject":
                return node
    return None


def _download_options(page: Selector) -> list[DownloadOption]:
    options: list[DownloadOption] = []
    for label in page.css("label.video-item__download-label"):
        radio = label.css("input.video-item__download-radio").first
        res = label.css("span.video-item__download-resolution").first
        if radio is None or res is None:
            continue
        match = _RESOLUTION.search(res.text or "")
        if not match:
            continue
        try:
            size = float(radio.attrib.get("data-size", "0") or 0)
        except ValueError:
            size = 0.0
        options.append(
            DownloadOption(
                label=radio.attrib.get("data-label", ""),
                width=int(match.group(1)),
                height=int(match.group(2)),
                size_mb=size,
            )
        )
    return options


def _tags(video: dict[str, Any]) -> tuple[str, ...]:
    refs = list(video.get("about", [])) + list(video.get("mentions", []))
    tags: list[str] = []
    for ref in refs:
        ref_id = ref.get("@id", "") if isinstance(ref, dict) else ""
        tag = ref_id.removeprefix("#stock_video_").replace("_", "-")
        if tag and tag not in tags:
            tags.append(tag)
    return tuple(tags)


def _is_free(video: dict[str, Any], page_html: str) -> bool:
    notice = str(video.get("copyrightNotice", "")).strip().lower()
    return notice == "free" and FREE_LICENSE_NAME in page_html


def _to_resolution_url(content_url: str, height: int) -> str | None:
    if not re.search(r"-\d{3,4}\.mp4$", content_url):
        return None
    return re.sub(r"-\d{3,4}\.mp4$", f"-{height}.mp4", content_url)


def is_wallpaper_worthy(title: str, description: str, tags: tuple[str, ...]) -> bool:
    """Reject clips centred on people or desks; those make poor looping desktops."""
    if _UNSUITABLE.search(title):
        return False
    return not any(_UNSUITABLE_TAG.match(part) for tag in tags for part in tag.split("-"))


def parse_detail(html: str, page_url: str, rank: int = 0) -> Wallpaper | None:
    """Return the highest landscape rendition (at least 1080p) of a free-licensed item."""
    page = Selector(html)
    video = _video_object(page)
    if video is None or not _is_free(video, html):
        return None

    eligible = [o for o in _download_options(page) if o.height >= MIN_HEIGHT and o.width > o.height]
    if not eligible:
        return None
    best = max(eligible, key=lambda o: o.width * o.height)

    content_url = str(video.get("contentUrl", ""))
    video_url = _to_resolution_url(content_url, UHD_HEIGHT if best.height >= UHD_HEIGHT else MIN_HEIGHT)
    preview_url = _to_resolution_url(content_url, 720)
    match = _ID_FROM_PATH.search(page_url)
    if not video_url or not preview_url or not match:
        return None
    title = str(video.get("name", "")).strip()
    poster_url = str(video.get("thumbnailUrl", "")).strip()
    if not title or not poster_url.startswith("https://"):
        return None
    tags = _tags(video)
    duration = parse_duration(str(video.get("duration", "")))
    if duration < MIN_DURATION_SECONDS or not is_wallpaper_worthy(title, "", tags):
        return None

    return Wallpaper(
        id=f"mixkit-{match.group(1)}",
        title=title,
        description=str(video.get("description", "")).strip(),
        category="",
        tags=tags,
        source="mixkit",
        source_page_url=page_url,
        preview_url=preview_url,
        video_url=video_url,
        poster_url=poster_url,
        author="Mixkit",
        license_name=FREE_LICENSE_NAME,
        license_url=FREE_LICENSE_URL,
        duration_seconds=duration,
        width=best.width,
        height=best.height,
        file_size_mb=best.size_mb,
        uploaded_at=str(video.get("uploadDate", "")),
        source_rank=rank,
    )
