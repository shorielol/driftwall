"""Link validation. Only a definitive 404/410 counts as dead; network trouble is 'unknown'."""

from __future__ import annotations

import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor

from .models import Wallpaper

log = logging.getLogger(__name__)

# True = alive, False = definitively dead, None = unknown (timeout, 429, 5xx...)
LinkCheck = Callable[[str], bool | None]

TIMEOUT_SECONDS = 20
DEFAULT_WORKERS = 8
ATTEMPTS = 2
RETRY_DELAY_SECONDS = 2.0
DEAD_STATUSES = frozenset({404, 410})
HEAD_REFUSED_STATUSES = frozenset({403, 405, 501})
ALLOWED_HOSTS = frozenset({
    # Loops are GitHub Release assets; downloads redirect to GitHub's asset CDN.
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
})


def is_allowed_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme == "https" and (parsed.hostname or "") in ALLOWED_HOSTS


class _SafeRedirects(urllib.request.HTTPRedirectHandler):
    """Follow redirects only to https URLs on allow-listed hosts."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        if not is_allowed_url(newurl):
            raise urllib.error.HTTPError(newurl, 403, "redirect to disallowed host", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_SafeRedirects)


def _open(request: urllib.request.Request) -> int:
    with _OPENER.open(request, timeout=TIMEOUT_SECONDS) as response:
        return int(response.status)


def _probe(url: str) -> bool | None:
    for method, extra in (("HEAD", {}), ("GET", {"Range": "bytes=0-0"})):
        request = urllib.request.Request(url, method=method, headers={"User-Agent": "DriftwallValidator/1.0", **extra})
        try:
            if 200 <= _open(request) < 400:
                return True
        except urllib.error.HTTPError as error:
            if error.code in DEAD_STATUSES:
                return False
            if method == "HEAD" and error.code in HEAD_REFUSED_STATUSES:
                continue
            return None
        except Exception as error:  # noqa: BLE001 network boundary: timeouts, DNS, resets
            log.debug("%s %s failed: %s", method, url, error)
            return None
    return None


def check_url(url: str) -> bool | None:
    if not is_allowed_url(url):
        return False
    result: bool | None = None
    for attempt in range(ATTEMPTS):
        result = _probe(url)
        if result is not None:
            return result
        if attempt + 1 < ATTEMPTS:
            time.sleep(RETRY_DELAY_SECONDS)
    return result


def _entry_status(wallpaper: Wallpaper, check: LinkCheck) -> bool | None:
    results = [check(url) for url in (wallpaper.video_url, wallpaper.preview_url, wallpaper.poster_url)]
    if any(r is False for r in results):
        return False
    if any(r is None for r in results):
        return None
    return True


def check_links(
    wallpapers: Iterable[Wallpaper], check: LinkCheck = check_url, workers: int = DEFAULT_WORKERS
) -> tuple[set[str], set[str]]:
    """Return (dead ids, unknown ids)."""
    items = list(wallpapers)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        statuses = list(pool.map(lambda w: _entry_status(w, check), items))
    dead = {w.id for w, status in zip(items, statuses, strict=True) if status is False}
    unknown = {w.id for w, status in zip(items, statuses, strict=True) if status is None}
    if dead:
        log.warning("dead entries: %s", sorted(dead))
    if unknown:
        log.warning("unverifiable entries (kept): %s", sorted(unknown))
    return dead, unknown


def find_dead(wallpapers: Iterable[Wallpaper], head: LinkCheck = check_url, workers: int = DEFAULT_WORKERS) -> set[str]:
    return check_links(wallpapers, head, workers)[0]
