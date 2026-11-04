import json
from datetime import date
from pathlib import Path

import pytest
from factories import make

from driftwall_scraper import cli
from driftwall_scraper.models import Catalog


@pytest.fixture
def catalog_dir(tmp_path: Path) -> Path:
    return tmp_path / "catalog"


def run(catalog_dir: Path, *extra: str) -> int:
    return cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-02", *extra])


def read_catalog(catalog_dir: Path) -> Catalog:
    return Catalog.from_json(json.loads((catalog_dir / "catalog.json").read_text()))


def patch_sources(monkeypatch, candidates, dead=frozenset(), unknown=frozenset(), catalog_dir=None):
    """Stand the backlog (catalog/loops.json) up with `candidates` and fake link checks."""
    backlog = list(candidates)
    monkeypatch.setattr(cli, "_backlog", lambda _dir: backlog)
    monkeypatch.setattr(cli, "check_links", lambda items: ({w.id for w in items} & dead, {w.id for w in items} & unknown))


def test_first_run_publishes_drop_and_ledger(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("a"), make("b", "Space")])

    assert run(catalog_dir, "--initial-size", "5") == 0

    catalog = read_catalog(catalog_dir)
    assert {w.id for w in catalog.wallpapers} == {"a", "b"}
    assert json.loads((catalog_dir / "seen.json").read_text())["ids"] == ["a", "b"]
    assert (catalog_dir / "drops" / "2026-11-02.json").exists()


def test_rerun_in_same_drop_week_is_skipped(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("a")])
    run(catalog_dir)
    patch_sources(monkeypatch, [make("c")])

    assert cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-04"]) == 0
    assert {w.id for w in read_catalog(catalog_dir).wallpapers} == {"a"}


def test_empty_backlog_on_first_run_fails_loudly(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [])

    assert run(catalog_dir) == 1
    assert not (catalog_dir / "catalog.json").exists()


def test_network_outage_never_wipes_catalog(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("a"), make("b")])
    run(catalog_dir, "--initial-size", "5")
    patch_sources(monkeypatch, [make("c")], unknown=frozenset({"a", "b", "c"}))

    run_code = cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-23"])

    assert run_code == 0
    assert {"a", "b"} <= {w.id for w in read_catalog(catalog_dir).wallpapers}


def test_mass_dead_links_trip_circuit_breaker(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make(f"w{i}") for i in range(10)])
    run(catalog_dir, "--initial-size", "10")
    patch_sources(monkeypatch, [], dead=frozenset(f"w{i}" for i in range(10)))

    assert cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-23"]) == 1
    assert len(read_catalog(catalog_dir).wallpapers) == 10


def test_dead_fresh_candidates_are_not_blacklisted(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("a"), make("flaky")], dead=frozenset({"flaky"}))
    run(catalog_dir)

    assert "flaky" not in json.loads((catalog_dir / "seen.json").read_text())["ids"]


def test_validate_reports_dead_and_prunes(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("a"), make("b")])
    run(catalog_dir, "--initial-size", "5")
    monkeypatch.setattr(cli, "check_links", lambda items: ({"a"}, set()))

    assert cli.main(["--catalog-dir", str(catalog_dir), "validate"]) == 1
    assert cli.main(["--catalog-dir", str(catalog_dir), "validate", "--prune"]) == 0
    assert [w.id for w in read_catalog(catalog_dir).wallpapers] == ["b"]


def test_size_must_be_positive(catalog_dir):
    with pytest.raises(SystemExit):
        cli.main(["--catalog-dir", str(catalog_dir), "drop", "--size", "0"])


def test_today_is_not_used_when_overridden():
    assert date.fromisoformat("2026-11-02").weekday() == 0


def test_backlog_is_read_from_loops_json(catalog_dir):
    catalog_dir.mkdir(parents=True)
    (catalog_dir / "loops.json").write_text(json.dumps([make("loop-a").to_json(), make("loop-b", "Space").to_json()]))

    assert cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-02", "--skip-link-check"]) == 0
    assert {w.id for w in read_catalog(catalog_dir).wallpapers} == {"loop-a", "loop-b"}


def test_later_drop_releases_only_unpublished_loops(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make(f"w{i}") for i in range(6)])
    run(catalog_dir, "--initial-size", "4")

    assert cli.main(["--catalog-dir", str(catalog_dir), "drop", "--today", "2026-11-23", "--size", "8"]) == 0
    catalog = read_catalog(catalog_dir)
    assert len(catalog.wallpapers) == 6
    assert set(catalog.drops[-1].ids) == {"w4", "w5"}


def test_unreachable_backlog_entries_wait_for_their_release(monkeypatch, catalog_dir):
    patch_sources(monkeypatch, [make("up"), make("pending")], unknown=frozenset({"pending"}))
    run(catalog_dir)

    assert [w.id for w in read_catalog(catalog_dir).wallpapers] == ["up"]
    assert "pending" not in json.loads((catalog_dir / "seen.json").read_text())["ids"]
