"""Find new 4K pan and zoom videos from ESA/Webb and ESA/Hubble (CC BY 4.0) for curation.

Discovery only proposes candidates. A person reviews them, picks the good ones and adds a
manifest under tools/loops/manifests, so nothing reaches the catalog without being looked at.
"""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Callable

log = logging.getLogger(__name__)

SITES = (
    ("esawebb.org", "https://cdn.esawebb.org/archives/videos/ultra_hd/{id}.mp4", "ESA/Webb"),
    ("esahubble.org", "https://cdn.esahubble.org/archives/videos/ultra_hd/{id}.mp4", "ESA/Hubble"),
)
# Slow camera moves across a single image make the best wallpapers; explainers and podcasts do not.
WANTED = re.compile(r"\b(pan|zoom|zooming|panning)\b", re.IGNORECASE)
REQUEST_DELAY_SECONDS = 1.0

Fetch = Callable[[str], str]


def _fetch(url: str) -> str:
    from scrapling.fetchers import Fetcher

    page = Fetcher.get(url, timeout=30, headers={"User-Agent": "DriftwallCatalogBot/1.0"})
    if page.status != 200:
        raise RuntimeError(f"HTTP {page.status} for {url}")
    return str(page.html_content)


def parse_listing(html: str) -> list[str]:
    ids: list[str] = []
    for video_id in re.findall(r'/videos/([a-z]+[0-9][a-z0-9_]*)/"', html):
        if video_id not in ids:
            ids.append(video_id)
    return ids


def parse_detail(html: str, video_id: str) -> dict[str, str] | None:
    titles = re.findall(r"<title>(.*?)</title>", html, flags=re.DOTALL)
    title = titles[0].split(" | ")[0].strip() if titles else ""
    has_uhd = re.search(rf"ultra_hd/{re.escape(video_id)}\.mp4", html) is not None
    if not title or not has_uhd or not WANTED.search(title):
        return None
    return {"id": video_id, "title": title}


def discover_space_videos(pages: int = 2, fetch: Fetch = _fetch) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    for host, uhd_template, credit in SITES:
        ids: list[str] = []
        for page in range(1, pages + 1):
            url = f"https://{host}/videos/" + (f"page/{page}/" if page > 1 else "")
            try:
                ids += [i for i in parse_listing(fetch(url)) if i not in ids]
            except Exception as error:  # noqa: BLE001 network boundary: skip this page, keep the rest
                log.warning("listing failed %s: %s", url, error)
            time.sleep(REQUEST_DELAY_SECONDS)
        for video_id in ids:
            try:
                detail = parse_detail(fetch(f"https://{host}/videos/{video_id}/"), video_id)
            except Exception as error:  # noqa: BLE001 network boundary
                log.warning("detail failed %s: %s", video_id, error)
                continue
            time.sleep(REQUEST_DELAY_SECONDS)
            if detail:
                found.append({**detail, "credit": credit, "page": f"https://{host}/videos/{video_id}/",
                              "video4k": uhd_template.format(id=video_id)})
    return found
