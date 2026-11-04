"""Command line entrypoint: `drop` builds a new 3-week drop, `validate` checks published links."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import tempfile
from dataclasses import replace
from datetime import date
from pathlib import Path
from typing import Any

from .catalog import DEFAULT_DROP_SIZE, build_drop, drop_week_start, prune, refill_featured, should_drop
from .categories import PEXELS_QUERIES, PIXABAY_QUERIES, crawl_tags
from .crawl import crawl_mixkit, scrapling_fetch
from .models import Catalog, Drop, Wallpaper
from .pexels import search_pexels
from .pixabay import search_pixabay
from .validate import check_links

log = logging.getLogger("driftwall_scraper")

DEFAULT_ANCHOR = date(2026, 11, 2)
DEFAULT_INITIAL_SIZE = 160
# If more than this share of published entries look dead at once, something is wrong upstream:
# refuse to prune rather than wipe the catalog.
MAX_DEAD_FRACTION = 0.3
MIN_DEAD_FOR_BREAKER = 3


class CatalogError(RuntimeError):
    pass


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise CatalogError(f"{path} is not valid JSON: {error}") from error


def _write_json(path: Path, data: Any) -> None:
    """Atomic write: temp file in the same directory, then rename."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as tmp:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.write("\n")
        temp_name = tmp.name
    os.replace(temp_name, path)


def _set_github_output(key: str, value: str) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")


def _load(catalog_dir: Path) -> tuple[Catalog, frozenset[str]]:
    catalog = Catalog.from_json(_read_json(catalog_dir / "catalog.json", Catalog.empty().to_json()))
    seen = frozenset(_read_json(catalog_dir / "seen.json", {"ids": []}).get("ids", []))
    return catalog, seen


def _write_drop_file(catalog_dir: Path, catalog: Catalog, drop: Drop) -> None:
    ids = set(drop.ids)
    items = [w.to_json() for w in catalog.wallpapers if w.id in ids]
    _write_json(catalog_dir / "drops" / f"{drop.drop_id}.json", {**drop.to_json(), "wallpapers": items})


def _publish(catalog_dir: Path, catalog: Catalog, seen: frozenset[str], drops: list[Drop]) -> None:
    """Ledger first (a superset is harmless), then drop files, catalog.json last."""
    _write_json(catalog_dir / "seen.json", {"ids": sorted(seen)})
    for drop in drops:
        _write_drop_file(catalog_dir, catalog, drop)
    _write_json(catalog_dir / "catalog.json", catalog.to_json())


def _gather_candidates(args: argparse.Namespace) -> list[Wallpaper]:
    candidates = crawl_mixkit(scrapling_fetch, crawl_tags(), max_pages=args.max_pages, delay_seconds=args.delay)
    api_key = os.environ.get("PEXELS_API_KEY", "").strip()
    if api_key:
        for offset, (category, query) in enumerate(PEXELS_QUERIES):
            candidates.extend(search_pexels(query, category, api_key, rank_offset=offset * 10))
    else:
        log.info("PEXELS_API_KEY not set; skipping Pexels source")
    pixabay_key = os.environ.get("PIXABAY_API_KEY", "").strip()
    if pixabay_key:
        for offset, (category, query) in enumerate(PIXABAY_QUERIES):
            candidates.extend(search_pixabay(query, category, pixabay_key, rank_offset=offset * 10))
    else:
        log.info("PIXABAY_API_KEY not set; skipping Pixabay source (anime-style loops)")
    log.info("gathered %d 4K candidates", len(candidates))
    return candidates


def _merge_pinned(catalog: Catalog, catalog_dir: Path) -> Catalog:
    """Add open-licence film loops (catalog/open-films.json) once their release files are live."""
    path = catalog_dir / "open-films.json"
    if not path.exists():
        return catalog
    pinned = [Wallpaper.from_json(item) for item in _read_json(path, [])]
    existing = {w.id for w in catalog.wallpapers}
    fresh = [w for w in pinned if w.id not in existing]
    if not fresh:
        return catalog
    dead, unknown = check_links(fresh)
    live = tuple(w for w in fresh if w.id not in dead | unknown)
    if not live:
        log.info("open-film loops not reachable yet; publish the films release first")
        return catalog
    log.info("adding %d open-film loops", len(live))
    return replace(catalog, wallpapers=live + catalog.wallpapers)


def _prune_dead(catalog: Catalog) -> Catalog:
    if not catalog.wallpapers:
        return catalog
    dead, _unknown = check_links(catalog.wallpapers)
    if len(dead) >= MIN_DEAD_FOR_BREAKER and len(dead) > MAX_DEAD_FRACTION * len(catalog.wallpapers):
        raise CatalogError(f"{len(dead)}/{len(catalog.wallpapers)} entries look dead; refusing to prune")
    return refill_featured(prune(catalog, dead)) if dead else catalog


def run_drop(args: argparse.Namespace) -> int:
    catalog_dir = Path(args.catalog_dir)
    today = date.fromisoformat(args.today) if args.today else date.today()
    anchor = date.fromisoformat(args.anchor)
    if not args.force and not should_drop(today, anchor):
        log.info("not a drop week (%s, anchor %s); nothing to do", today, anchor)
        _set_github_output("dropped", "false")
        return 0

    drop_day = drop_week_start(today, anchor) if today >= anchor else today
    catalog, seen = _load(catalog_dir)
    if not args.force and any(d.drop_id == drop_day.isoformat() for d in catalog.drops):
        log.info("drop %s already published; nothing to do", drop_day)
        _set_github_output("dropped", "false")
        return 0

    pruned = _merge_pinned(_prune_dead(catalog), catalog_dir)
    candidates = _gather_candidates(args)
    if not candidates:
        raise CatalogError("the crawl returned no candidates; the source may have changed")

    excluded = seen | {w.id for w in pruned.wallpapers}
    fresh = [w for w in candidates if w.id not in excluded]
    dead_fresh, unknown_fresh = check_links(fresh)
    fresh = [w for w in fresh if w.id not in dead_fresh | unknown_fresh]

    size = args.initial_size if not pruned.wallpapers else args.size
    updated, new_seen = build_drop(pruned, fresh, seen, today=drop_day, size=size)
    if updated is pruned:
        log.warning("no fresh wallpapers available; keeping the previous drop")
        if pruned is not catalog:
            _publish(catalog_dir, pruned, seen | {w.id for w in pruned.wallpapers}, list(pruned.drops))
        _set_github_output("dropped", "false")
        return 0

    drop = next(d for d in updated.drops if d.drop_id == drop_day.isoformat())
    changed_drops = list(updated.drops) if pruned is not catalog else [drop]
    _publish(catalog_dir, updated, new_seen, changed_drops)
    log.info("drop %s: %d new wallpapers, catalog total %d", drop.drop_id, len(drop.ids), len(updated.wallpapers))
    _set_github_output("dropped", "true")
    return 0


def run_curate(args: argparse.Namespace) -> int:
    """Re-apply the current content filters to a published catalog without re-crawling."""
    from .mixkit import is_wallpaper_worthy

    catalog_dir = Path(args.catalog_dir)
    catalog, seen = _load(catalog_dir)
    rejected = {
        w.id for w in catalog.wallpapers
        if w.source == "mixkit" and (w.category == "Anime" or not is_wallpaper_worthy(w.title, "", w.tags))
    }
    if not rejected:
        log.info("catalog already satisfies the filters (%d entries)", len(catalog.wallpapers))
        return 0
    curated = refill_featured(prune(catalog, rejected))
    _publish(catalog_dir, curated, seen, list(curated.drops))
    log.info("removed %d entries; %d remain", len(rejected), len(curated.wallpapers))
    return 0


def run_validate(args: argparse.Namespace) -> int:
    catalog_dir = Path(args.catalog_dir)
    catalog, seen = _load(catalog_dir)
    dead, unknown = check_links(catalog.wallpapers)
    too_small = {w.id for w in catalog.wallpapers if w.height < 1080 or w.width <= w.height}
    log.info("%d entries: %d dead, %d unverifiable, %d below landscape 1080p", len(catalog.wallpapers), len(dead), len(unknown), len(too_small))
    bad = dead | too_small
    if args.prune and bad:
        pruned = refill_featured(prune(catalog, bad))
        _publish(catalog_dir, pruned, seen, list(pruned.drops))
        return 0
    return 1 if bad else 0


def _positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="driftwall_scraper", description=__doc__)
    parser.add_argument("--catalog-dir", default="catalog", help="folder holding catalog.json, drops/, seen.json")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    drop = sub.add_parser("drop", help="build a new 3-week drop")
    drop.add_argument("--force", action="store_true", help="ignore the schedule and the already-published check")
    drop.add_argument("--today", help="override today's date (YYYY-MM-DD)")
    drop.add_argument("--anchor", default=DEFAULT_ANCHOR.isoformat(), help="first drop day (YYYY-MM-DD)")
    drop.add_argument("--size", type=_positive_int, default=DEFAULT_DROP_SIZE)
    drop.add_argument("--initial-size", type=_positive_int, default=DEFAULT_INITIAL_SIZE)
    drop.add_argument("--max-pages", type=_positive_int, default=4)
    drop.add_argument("--delay", type=float, default=1.0, help="seconds between requests")
    drop.set_defaults(handler=run_drop)

    curate = sub.add_parser("curate", help="re-apply content filters to the existing catalog")
    curate.set_defaults(handler=run_curate)

    validate = sub.add_parser("validate", help="check every published link")
    validate.add_argument("--prune", action="store_true", help="remove dead entries instead of failing")
    validate.set_defaults(handler=run_validate)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")
    try:
        return int(args.handler(args))
    except CatalogError as error:
        log.error("%s", error)
        _set_github_output("dropped", "false")
        return 1


if __name__ == "__main__":
    sys.exit(main())
