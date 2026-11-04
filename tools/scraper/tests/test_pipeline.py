from factories import make

from driftwall_scraper.discover import discover_space_videos, parse_detail, parse_listing
from driftwall_scraper.validate import find_dead, is_allowed_url

LISTING = '<a href="/videos/weic2411b/">x</a><a href="/videos/weic2411b/">dup</a><a href="/videos/potm2409a/">y</a>'
PAN = "<title>Pan: Horsehead Nebula (NIRCam image) | ESA/Webb</title> cdn/archives/videos/ultra_hd/weic2411b.mp4"
TALK = "<title>Webb science explained | ESA/Webb</title> archives/videos/ultra_hd/potm2409a.mp4"
NO_4K = "<title>Zoom into a cluster | ESA/Webb</title> archives/videos/hd_1080p25_screen/x1.mp4"


def test_parse_listing_dedupes_ids_in_order():
    assert parse_listing(LISTING) == ["weic2411b", "potm2409a"]


def test_parse_detail_keeps_only_4k_pans_and_zooms():
    assert parse_detail(PAN, "weic2411b") == {"id": "weic2411b", "title": "Pan: Horsehead Nebula (NIRCam image)"}
    assert parse_detail(TALK, "potm2409a") is None
    assert parse_detail(NO_4K, "x1") is None


def test_discover_builds_candidates_and_survives_errors(monkeypatch):
    from driftwall_scraper import discover

    monkeypatch.setattr(discover, "REQUEST_DELAY_SECONDS", 0)

    def fake_fetch(url: str) -> str:
        if "esahubble" in url:
            raise TimeoutError("down")
        if url.endswith("/videos/"):
            return LISTING
        return PAN if "weic2411b" in url else TALK

    found = discover_space_videos(pages=1, fetch=fake_fetch)
    assert [c["id"] for c in found] == ["weic2411b"]
    assert found[0]["video4k"] == "https://cdn.esawebb.org/archives/videos/ultra_hd/weic2411b.mp4"
    assert found[0]["credit"] == "ESA/Webb"


def test_release_asset_hosts_are_allowed():
    assert is_allowed_url("https://github.com/shorielol/driftwall/releases/download/loops-v1/a.mp4")
    assert is_allowed_url("https://objects.githubusercontent.com/x")
    assert not is_allowed_url("https://assets.mixkit.co/a.mp4")


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

    assert validate.check_url("https://github.com/gone.mp4") is False
    assert validate.check_url("https://github.com/busy.mp4") is None
    assert validate.check_url("https://github.com/slow.mp4") is None
    assert validate.check_url("http://insecure.example/a.mp4") is False
    assert validate.check_url("https://evil.example/a.mp4") is False
