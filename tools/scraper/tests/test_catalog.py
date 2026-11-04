from datetime import date

from factories import make

from driftwall_scraper.catalog import (
    DROP_INTERVAL_DAYS,
    build_drop,
    prune,
    should_drop,
)
from driftwall_scraper.categories import categorize
from driftwall_scraper.models import Catalog


ANCHOR = date(2026, 11, 2)  # a Monday


def test_should_drop_every_third_week_from_anchor():
    assert should_drop(ANCHOR, ANCHOR) is True
    assert should_drop(date(2026, 11, 9), ANCHOR) is False
    assert should_drop(date(2026, 11, 16), ANCHOR) is False
    assert should_drop(date(2026, 11, 23), ANCHOR) is True
    assert should_drop(date(2026, 12, 14), ANCHOR) is True


def test_should_drop_false_before_anchor():
    assert should_drop(date(2026, 10, 12), ANCHOR) is False


def test_build_drop_excludes_seen_and_existing_ids():
    existing = build_drop(Catalog.empty(), [make("a")], seen=frozenset(), today=ANCHOR, size=10)[0]
    candidates = [make("a"), make("b"), make("c")]

    catalog, seen = build_drop(existing, candidates, seen=frozenset({"c"}), today=date(2026, 11, 23), size=10)

    new_drop = catalog.drops[-1]
    assert new_drop.ids == ("b",)
    assert {w.id for w in catalog.wallpapers} == {"a", "b"}
    assert seen == frozenset({"a", "b", "c"})


def test_build_drop_balances_categories_round_robin():
    candidates = [make(f"n{i}", "Nature", rank=i) for i in range(5)] + [make("s0", "Space"), make("c0", "City")]

    catalog, _ = build_drop(Catalog.empty(), candidates, seen=frozenset(), today=ANCHOR, size=4)

    ids = catalog.drops[-1].ids
    assert len(ids) == 4
    categories = {next(w.category for w in catalog.wallpapers if w.id == i) for i in ids}
    assert categories == {"Nature", "Space", "City"}


def test_build_drop_sets_metadata_and_does_not_mutate_input():
    original = make("a")
    catalog, _ = build_drop(Catalog.empty(), [original], seen=frozenset(), today=ANCHOR, size=5)

    assert original.added_in_drop == ""
    assert catalog.wallpapers[0].added_in_drop == "2026-11-02"
    assert catalog.drop_id == "2026-11-02"
    assert catalog.next_drop_at == "2026-11-23"
    assert DROP_INTERVAL_DAYS == 21
    assert catalog.featured == ("a",)


def test_build_drop_featured_prefers_distinct_categories():
    candidates = [make("n1", "Nature"), make("n2", "Nature"), make("s1", "Space"), make("c1", "City")]

    catalog, _ = build_drop(Catalog.empty(), candidates, seen=frozenset(), today=ANCHOR, size=10, featured_count=3)

    assert len(catalog.featured) == 3
    cats = [next(w.category for w in catalog.wallpapers if w.id == f) for f in catalog.featured]
    assert len(set(cats)) == 3


def test_build_drop_with_no_fresh_candidates_keeps_previous_drop():
    first, seen = build_drop(Catalog.empty(), [make("a")], seen=frozenset(), today=ANCHOR, size=5)

    second, _ = build_drop(first, [make("a")], seen=seen, today=date(2026, 11, 23), size=5)

    assert second.drop_id == first.drop_id
    assert len(second.drops) == 1


def test_prune_removes_dead_entries_everywhere():
    catalog, _ = build_drop(Catalog.empty(), [make("a"), make("b")], seen=frozenset(), today=ANCHOR, size=5)

    pruned = prune(catalog, dead_ids={"a"})

    assert [w.id for w in pruned.wallpapers] == ["b"]
    assert "a" not in pruned.featured
    assert all("a" not in d.ids for d in pruned.drops)
    assert len(catalog.wallpapers) == 2  # original untouched


def test_catalog_json_roundtrip():
    catalog, _ = build_drop(Catalog.empty(), [make("a")], seen=frozenset(), today=ANCHOR, size=5)
    assert Catalog.from_json(catalog.to_json()) == catalog


def test_categorize_uses_query_tag_then_item_tags():
    assert categorize(query_tag="galaxy", item_tags=()) == "Space"
    assert categorize(query_tag="unknown", item_tags=("zzz", "city")) == "City"
    assert categorize(query_tag="unknown", item_tags=("city", "cat")) == "Cats"  # specific beats generic
    assert categorize(query_tag="unknown", item_tags=("zzz",)) == "Abstract"


def test_drop_week_start_snaps_to_anchor_weekday():
    from driftwall_scraper.catalog import drop_week_start

    assert drop_week_start(date(2026, 11, 25), ANCHOR) == date(2026, 11, 23)
    assert drop_week_start(date(2026, 11, 23), ANCHOR) == date(2026, 11, 23)


def test_build_drop_same_day_twice_never_repeats_ids():
    first, seen = build_drop(Catalog.empty(), [make("a"), make("b")], seen=frozenset(), today=ANCHOR, size=1)
    second, _ = build_drop(first, [make("a"), make("b")], seen=seen, today=ANCHOR, size=1)

    ids = [i for d in second.drops for i in d.ids]
    assert len(ids) == len(set(ids))


def test_refill_featured_tops_up_after_prune():
    from driftwall_scraper.catalog import refill_featured

    catalog, _ = build_drop(Catalog.empty(), [make("a", "Nature"), make("b", "Space")], seen=frozenset(), today=ANCHOR, size=5)
    pruned = prune(catalog, dead_ids={"a"})

    assert refill_featured(pruned, count=2).featured == ("b",)
    assert pruned.featured == ("b",)
