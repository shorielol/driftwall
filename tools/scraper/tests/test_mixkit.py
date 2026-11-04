from pathlib import Path

import pytest

from driftwall_scraper.mixkit import (
    ListingCard,
    is_wallpaper_worthy,
    parse_detail,
    parse_listing,
)

FIXTURES = Path(__file__).parent / "fixtures"


def read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_parse_listing_returns_cards_with_4k_flag():
    cards = parse_listing(read("mixkit_listing_night.html"))

    assert len(cards) == 24
    assert all(isinstance(c, ListingCard) for c in cards)
    four_k = [c for c in cards if c.is_4k]
    assert len(four_k) == 8
    first = cards[0]
    assert first.item_id == "100417"
    assert first.detail_path == "/free-stock-video/nighttime-park-with-illuminated-streetlights-and-trees-100417/"
    assert first.is_4k is True


def test_parse_listing_on_empty_html_returns_empty_list():
    assert parse_listing("<html><body>nothing</body></html>") == []


def test_parse_detail_free_4k_item():
    item = parse_detail(
        read("mixkit_detail_4k_free.html"),
        page_url="https://mixkit.co/free-stock-video/nighttime-park-with-illuminated-streetlights-and-trees-100417/",
    )

    assert item is not None
    assert item.id == "mixkit-100417"
    assert item.title == "Nighttime park with illuminated streetlights and trees"
    assert item.width == 4096 and item.height == 2160
    assert item.duration_seconds == 7
    assert item.license_name == "Mixkit Stock Video Free License"
    assert item.video_url.endswith("100417-video-2160.mp4")
    assert item.preview_url.endswith("100417-video-720.mp4")
    assert item.poster_url.endswith("100417-video-thumb-720-0.jpg")
    assert item.file_size_mb == 33.43
    assert "rain" in item.tags
    assert item.uploaded_at.startswith("2024-12-15")


def test_parse_detail_rejects_restricted_or_non_4k_item():
    item = parse_detail(
        read("mixkit_detail_hd_restricted.html"),
        page_url="https://mixkit.co/free-stock-video/full-moon-on-halloween-night-loop-video-30605/",
    )

    assert item is None


def test_parse_detail_on_garbage_returns_none():
    assert parse_detail("<html></html>", page_url="https://mixkit.co/x-1/") is None



@pytest.mark.parametrize(
    ("title", "tags", "expected"),
    [
        ("Waterfall in forest", ("nature",), True),
        ("Black cat with yellow eyes", ("cat",), True),
        ("Typing on a laptop", ("technology",), False),
        ("Woman walking on the beach", ("beach",), False),
        ("Close-up of hands holding a phone", (), False),
        ("Aerial view of a city at night", ("city",), True),
        ("Businessman in the office", (), False),
    ],
)
def test_is_wallpaper_worthy_filters_people_and_office_shots(title, tags, expected):
    assert is_wallpaper_worthy(title, "", tags) is expected


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        ("Man-made lake at dusk", True),
        ("Manhattan skyline at night", True),
        ("Hand-held shot of waves", True),
        ("Girls on the beach", False),
        ("Tourists at sunset", False),
        ("Ladies walking in the park", False),
    ],
)
def test_scenery_filter_handles_hyphens_and_plurals(title, expected):
    assert is_wallpaper_worthy(title, "", ()) is expected


@pytest.mark.parametrize("title", ["Group of friends having fun", "Several gamers playing on computers", "Dog catches a ball"])
def test_scenery_filter_rejects_groups_gamers_and_dogs(title):
    assert is_wallpaper_worthy(title, "", ()) is False


def test_parse_detail_accepts_full_hd_when_no_4k():
    html = read("mixkit_detail_4k_free.html")
    start = html.index('data-label="4K"')
    label_start = html.rindex("<label", 0, start)
    label_end = html.index("</label>", start) + len("</label>")
    full_hd_only = html[:label_start] + html[label_end:]

    item = parse_detail(full_hd_only, page_url="https://mixkit.co/free-stock-video/x-100417/")

    assert item is not None
    assert (item.width, item.height) == (1920, 1080)
    assert item.video_url.endswith("100417-video-1080.mp4")


@pytest.mark.parametrize(
    "title",
    ["Artist painting a still life", "DJ playing music at a nightclub", "Covers of three vintage comics", "Poker Game Setting", "Video game controller"],
)
def test_scenery_filter_rejects_artists_djs_comics_and_props(title):
    assert is_wallpaper_worthy(title, "", ()) is False
