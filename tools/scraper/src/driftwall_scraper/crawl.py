"""Network crawl of Mixkit tag pages using scrapling, polite and rate limited."""

from __future__ import annotations

import logging
import os
import time
from collections.abc import Callable, Sequence

from .categories import categorize
from .mixkit import BASE_URL, parse_detail, parse_listing
from .models import Wallpaper

log = logging.getLogger(__name__)

Fetch = Callable[[str], str]

USER_AGENT = os.environ.get("DRIFTWALL_USER_AGENT", "DriftwallCatalogBot/1.0")
REQUEST_TIMEOUT_SECONDS = 30
DEFAULT_DELAY_SECONDS = 1.0
RANK_PAGE_STRIDE = 100


class FetchError(RuntimeError):
    pass


def scrapling_fetch(url: str) -> str:
    """Fetch one page with scrapling's HTTP fetcher. Raises FetchError on non-200."""
    from scrapling.fetchers import Fetcher

    page = Fetcher.get(url, timeout=REQUEST_TIMEOUT_SECONDS, headers={"User-Agent": USER_AGENT})
    if page.status != 200:
        raise FetchError(f"HTTP {page.status} for {url}")
    body = page.body
    return body.decode("utf-8", errors="replace") if isinstance(body, bytes) else str(body)


def _listing_url(tag: str, page: int) -> str:
    base = f"{BASE_URL}/free-stock-video/{tag}/"
    return base if page == 1 else f"{base}?page={page}"


FETCH_ATTEMPTS = 2


def _safe_fetch(fetch: Fetch, url: str, retry_delay: float = 2.0) -> str | None:
    for attempt in range(FETCH_ATTEMPTS):
        try:
            return fetch(url)
        except Exception as error:  # network boundary: log, back off once, keep crawling other pages
            log.warning("fetch failed (%d/%d) %s: %s", attempt + 1, FETCH_ATTEMPTS, url, error)
            if attempt + 1 < FETCH_ATTEMPTS:
                time.sleep(retry_delay)
    return None


def crawl_mixkit(
    fetch: Fetch,
    tags: Sequence[tuple[str, str]],
    max_pages: int = 4,
    delay_seconds: float = DEFAULT_DELAY_SECONDS,
    fill_below: int = 25,
) -> list[Wallpaper]:
    """Crawl each tag's listing pages and return free wallpapers at 1080p or better (4K preferred later)."""
    results: dict[str, Wallpaper] = {}
    visited_details: set[str] = set()
    uhd_per_category: dict[str, int] = {}

    for category, tag in tags:
        for page_number in range(1, max_pages + 1):
            html = _safe_fetch(fetch, _listing_url(tag, page_number), retry_delay=delay_seconds * 2)
            time.sleep(delay_seconds)
            cards = parse_listing(html) if html else []
            if not cards:
                break
            for card in cards:
                if card.item_id in visited_details:
                    continue
                # Mainly 4K: lower resolutions only top up categories that are short on 4K.
                if not card.is_4k and uhd_per_category.get(category, 0) >= fill_below:
                    continue
                visited_details.add(card.item_id)
                detail_url = f"{BASE_URL}{card.detail_path}"
                detail_html = _safe_fetch(fetch, detail_url, retry_delay=delay_seconds * 2)
                time.sleep(delay_seconds)
                if not detail_html:
                    continue
                rank = (page_number - 1) * RANK_PAGE_STRIDE + card.rank
                item = parse_detail(detail_html, page_url=detail_url, rank=rank)
                if item is None:
                    continue
                results[item.id] = item.with_changes(category=categorize(tag, item.tags))
                if item.height >= 2160:
                    uhd_per_category[category] = uhd_per_category.get(category, 0) + 1
        log.info("tag %-12s total so far: %d", tag, len(results))

    return list(results.values())
