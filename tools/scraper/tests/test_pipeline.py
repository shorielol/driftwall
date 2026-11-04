from pathlib import Path

from factories import make

from driftwall_scraper.crawl import crawl_mixkit
from driftwall_scraper.pexels import parse_search
from driftwall_scraper.validate import find_dead

FIXTURES = Path(__file__).parent / "fixtures"
LISTING = (FIXTURES / "mixkit_listing_night.html").read_text(encoding="utf-8")
DETAIL_4K = (FIXTURES / "mixkit_detail_4k_free.html").read_text(encoding="utf-8")


def fake_fetch(url: str) -> str:
    if url.endswith("/free-stock-video/cozy/"):
        return LISTING
    if "-100417/" in url:
        return DETAIL_4K
    return "<html></html>"


def test_crawl_mixkit_opens_every_card_and_assigns_category():
    fetched: list[str] = []

    def recording_fetch(url: str) -> str:
        fetched.append(url)
        return fake_fetch(url)

    results = crawl_mixkit(recording_fetch, tags=[("Cozy", "cozy")], max_pages=2, delay_seconds=0)

    assert [w.id for w in results] == ["mixkit-100417"]
    assert results[0].category == "Cozy"
    detail_fetches = [u for u in fetched if "/free-stock-video/cozy" not in u]
    assert len(detail_fetches) == 24  # every card; resolution is decided on the detail page


def test_crawl_mixkit_skips_lower_resolutions_once_category_has_enough_4k():
    fetched: list[str] = []

    def recording_fetch(url: str) -> str:
        fetched.append(url)
        return fake_fetch(url)

    crawl_mixkit(recording_fetch, tags=[("Cozy", "cozy")], max_pages=1, delay_seconds=0, fill_below=1)

    detail_fetches = [u for u in fetched if "/free-stock-video/cozy" not in u]
    # The first card is 4K and fills the quota, so only the remaining 4K cards are opened.
    assert len(detail_fetches) == 8


def test_crawl_mixkit_stops_paging_when_listing_is_empty():
    fetched: list[str] = []

    def recording_fetch(url: str) -> str:
        fetched.append(url)
        return "<html></html>"

    crawl_mixkit(recording_fetch, tags=[("Cozy", "cozy")], max_pages=5, delay_seconds=0)

    assert fetched == ["https://mixkit.co/free-stock-video/cozy/"]


def test_crawl_mixkit_survives_fetch_errors():
    def broken(url: str) -> str:
        raise TimeoutError("boom")

    assert crawl_mixkit(broken, tags=[("Cozy", "cozy")], max_pages=1, delay_seconds=0) == []


PEXELS_JSON = {
    "videos": [
        {
            "id": 111,
            "url": "https://www.pexels.com/video/foggy-forest-111/",
            "duration": 20,
            "width": 3840,
            "height": 2160,
            "image": "https://images.pexels.com/videos/111/poster.jpeg",
            "user": {"name": "Jane Doe"},
            "video_files": [
                {"quality": "hd", "width": 1280, "height": 720, "link": "https://videos.pexels.com/111-hd.mp4"},
                {"quality": "uhd", "width": 3840, "height": 2160, "link": "https://videos.pexels.com/111-uhd.mp4"},
            ],
        },
        {
            "id": 222,
            "url": "https://www.pexels.com/video/hd-only-222/",
            "duration": 15,
            "width": 1920,
            "height": 1080,
            "image": "https://images.pexels.com/videos/222/poster.jpeg",
            "user": {"name": "John"},
            "video_files": [
                {"quality": "hd", "width": 1920, "height": 1080, "link": "https://videos.pexels.com/222-hd.mp4"}
            ],
        },
        {
            "id": 333,
            "url": "https://www.pexels.com/video/vertical-333/",
            "duration": 15,
            "width": 2160,
            "height": 3840,
            "image": "https://images.pexels.com/videos/333/poster.jpeg",
            "user": {"name": "V"},
            "video_files": [
                {"quality": "uhd", "width": 2160, "height": 3840, "link": "https://videos.pexels.com/333-uhd.mp4"}
            ],
        },
    ]
}


def test_parse_pexels_keeps_landscape_1080p_and_up():
    results = parse_search(PEXELS_JSON, category="Nature", rank_offset=0)

    assert [w.id for w in results] == ["pexels-111", "pexels-222"]
    item = results[0]
    assert item.video_url.endswith("111-uhd.mp4")
    assert item.preview_url.endswith("111-hd.mp4")
    assert item.author == "Jane Doe"
    assert item.width == 3840 and item.height == 2160
    assert item.title == "Foggy Forest"
    assert item.license_name == "Pexels License"


def test_parse_pexels_tolerates_malformed_payload():
    assert parse_search({"videos": [{"id": 1}]}, category="Nature", rank_offset=0) == []
    assert parse_search({}, category="Nature", rank_offset=0) == []


def test_find_dead_reports_any_failing_url():
    ok = make("ok")
    bad = make("bad")

    def head(url: str) -> bool:
        return "bad" not in url

    assert find_dead([ok, bad], head=head, workers=2) == {"bad"}


def test_check_url_classifies_404_dead_and_timeouts_unknown(monkeypatch):
    import urllib.error

    from driftwall_scraper import validate

    def fake_open(request):
        url = request.full_url
        if "gone" in url:
            raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
        if "busy" in url:
            raise urllib.error.HTTPError(url, 429, "Too Many", {}, None)
        raise TimeoutError("slow")

    monkeypatch.setattr(validate, "_open", fake_open)
    monkeypatch.setattr(validate, "RETRY_DELAY_SECONDS", 0)

    assert validate.check_url("https://assets.mixkit.co/gone.mp4") is False
    assert validate.check_url("https://assets.mixkit.co/busy.mp4") is None
    assert validate.check_url("https://assets.mixkit.co/slow.mp4") is None
    assert validate.check_url("http://insecure.example/a.mp4") is False
    assert validate.check_url("https://evil.example/a.mp4") is False


def test_pexels_people_clips_and_bad_types_are_skipped():
    payload = {"videos": [
        {**PEXELS_JSON["videos"][0], "id": 5, "url": "https://www.pexels.com/video/woman-walking-5/"},
        {**PEXELS_JSON["videos"][0], "id": 6, "user": None, "width": "wide"},
    ]}
    assert parse_search(payload, category="Nature", rank_offset=0) == []
