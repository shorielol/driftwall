"""Pure catalog logic: 3-week drop cadence, fresh-drop selection, featured rotation, pruning."""

from __future__ import annotations

from collections import OrderedDict
from collections.abc import Iterable
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

from .models import SCHEMA_VERSION, Catalog, Drop, Wallpaper

DROP_INTERVAL_DAYS = 21
DEFAULT_DROP_SIZE = 40
DEFAULT_FEATURED_COUNT = 6


def should_drop(today: date, anchor: date) -> bool:
    """True during every third week counted from the anchor week."""
    if today < anchor:
        return False
    weeks = (today - anchor).days // 7
    return weeks % (DROP_INTERVAL_DAYS // 7) == 0


def drop_week_start(today: date, anchor: date) -> date:
    """The anchor weekday on or before `today`; drops are keyed by this date."""
    return today - timedelta(days=(today - anchor).days % 7)


def refill_featured(catalog: Catalog, count: int = DEFAULT_FEATURED_COUNT) -> Catalog:
    """Top the featured rotation back up (after pruning) from the latest drop, then the rest."""
    if len(catalog.featured) >= count:
        return catalog
    by_id = {w.id: w for w in catalog.wallpapers}
    latest = next((d for d in reversed(catalog.drops) if d.ids), None)
    pool = [by_id[i] for i in (latest.ids if latest else ()) if i in by_id] + list(catalog.wallpapers)
    kept = [i for i in catalog.featured if i in by_id]
    remaining = [w for w in pool if w.id not in kept]
    extra = [i for i in _featured(remaining, count) if i not in kept][: count - len(kept)]
    return replace(catalog, featured=tuple(kept + extra))


def _fresh_candidates(candidates: Iterable[Wallpaper], excluded: frozenset[str]) -> list[Wallpaper]:
    unique: OrderedDict[str, Wallpaper] = OrderedDict()
    for wallpaper in candidates:
        if wallpaper.id not in excluded and wallpaper.id not in unique:
            unique[wallpaper.id] = wallpaper
    # 4K first, then 2K, then 1080p; source popularity breaks ties.
    return sorted(unique.values(), key=lambda w: (-min(w.height, 2160), w.source_rank, w.id))


def _round_robin(wallpapers: list[Wallpaper], size: int) -> list[Wallpaper]:
    buckets: OrderedDict[str, list[Wallpaper]] = OrderedDict()
    for wallpaper in wallpapers:
        buckets.setdefault(wallpaper.category, []).append(wallpaper)
    queues = [list(bucket) for bucket in buckets.values()]
    picked: list[Wallpaper] = []
    while len(picked) < size and any(queues):
        for queue in queues:
            if queue and len(picked) < size:
                picked.append(queue.pop(0))
    return picked


def _featured(wallpapers: list[Wallpaper], count: int) -> tuple[str, ...]:
    chosen: list[str] = []
    used_categories: set[str] = set()
    for wallpaper in wallpapers:
        if len(chosen) < count and wallpaper.category not in used_categories:
            chosen.append(wallpaper.id)
            used_categories.add(wallpaper.category)
    for wallpaper in wallpapers:
        if len(chosen) < count and wallpaper.id not in chosen:
            chosen.append(wallpaper.id)
    return tuple(chosen)


def _merge_drops(drops: tuple[Drop, ...], new_drop: Drop) -> tuple[Drop, ...]:
    existing = next((d for d in drops if d.drop_id == new_drop.drop_id), None)
    if existing is None:
        return drops + (new_drop,)
    merged = Drop(drop_id=existing.drop_id, date=existing.date, ids=existing.ids + new_drop.ids)
    return tuple(merged if d.drop_id == new_drop.drop_id else d for d in drops)


def build_drop(
    catalog: Catalog,
    candidates: Iterable[Wallpaper],
    seen: frozenset[str],
    today: date,
    size: int = DEFAULT_DROP_SIZE,
    featured_count: int = DEFAULT_FEATURED_COUNT,
    now: datetime | None = None,
) -> tuple[Catalog, frozenset[str]]:
    """Return a new catalog with a fresh drop appended, plus the updated seen-ID ledger."""
    existing_ids = frozenset(w.id for w in catalog.wallpapers)
    fresh = _fresh_candidates(candidates, seen | existing_ids)
    picked = _round_robin(fresh, size)
    if not picked:
        return catalog, seen | existing_ids

    drop_id = today.isoformat()
    new_wallpapers = [w.with_changes(added_in_drop=drop_id) for w in picked]
    new_drop = Drop(drop_id=drop_id, date=drop_id, ids=tuple(w.id for w in new_wallpapers))
    timestamp = (now or datetime.now(UTC)).replace(microsecond=0).isoformat()

    updated = Catalog(
        schema_version=SCHEMA_VERSION,
        generated_at=timestamp,
        drop_id=drop_id,
        next_drop_at=(today + timedelta(days=DROP_INTERVAL_DAYS)).isoformat(),
        featured=_featured(new_wallpapers, featured_count),
        drops=_merge_drops(catalog.drops, new_drop),
        wallpapers=catalog.wallpapers + tuple(new_wallpapers),
    )
    return updated, seen | existing_ids | frozenset(new_drop.ids)


def prune(catalog: Catalog, dead_ids: set[str] | frozenset[str]) -> Catalog:
    """Drop entries whose media is gone, everywhere they are referenced."""
    if not dead_ids:
        return catalog
    return Catalog(
        schema_version=catalog.schema_version,
        generated_at=catalog.generated_at,
        drop_id=catalog.drop_id,
        next_drop_at=catalog.next_drop_at,
        featured=tuple(i for i in catalog.featured if i not in dead_ids),
        drops=tuple(
            Drop(drop_id=d.drop_id, date=d.date, ids=tuple(i for i in d.ids if i not in dead_ids))
            for d in catalog.drops
        ),
        wallpapers=tuple(w for w in catalog.wallpapers if w.id not in dead_ids),
    )
