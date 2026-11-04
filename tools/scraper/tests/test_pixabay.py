from driftwall_scraper.pixabay import parse_search

PAYLOAD = {
    "hits": [
        {
            "id": 7001,
            "pageURL": "https://pixabay.com/videos/anime-city-night-7001/",
            "tags": "anime, city, night",
            "duration": 18,
            "user": "studio",
            "videos": {
                "large": {"url": "https://cdn.pixabay.com/video/7001_large.mp4", "width": 3840, "height": 2160,
                          "size": 50_000_000, "thumbnail": "https://cdn.pixabay.com/video/7001_large.jpg"},
                "medium": {"url": "https://cdn.pixabay.com/video/7001_medium.mp4", "width": 1920, "height": 1080,
                           "size": 9_000_000, "thumbnail": "https://cdn.pixabay.com/video/7001_medium.jpg"},
                "small": {"url": "https://cdn.pixabay.com/video/7001_small.mp4", "width": 1280, "height": 720,
                          "size": 4_000_000, "thumbnail": "https://cdn.pixabay.com/video/7001_small.jpg"},
            },
        },
        {
            "id": 7002,
            "pageURL": "https://pixabay.com/videos/cartoon-7002/",
            "tags": "cartoon",
            "duration": 9,
            "user": "x",
            "videos": {"medium": {"url": "https://cdn.pixabay.com/video/7002_medium.mp4", "width": 1280, "height": 720,
                                  "size": 1, "thumbnail": "https://cdn.pixabay.com/video/7002.jpg"}},
        },
        {"id": "broken", "videos": None},
    ]
}


def test_parse_pixabay_picks_highest_rendition_and_skips_below_1080():
    results = parse_search(PAYLOAD, category="Anime", rank_offset=0)

    assert [w.id for w in results] == ["pixabay-7001"]
    item = results[0]
    assert (item.width, item.height) == (3840, 2160)
    assert item.video_url.endswith("7001_large.mp4")
    assert item.preview_url.endswith("7001_small.mp4")
    assert item.poster_url.endswith("7001_large.jpg")
    assert item.title == "Anime City Night"
    assert item.license_name == "Pixabay Content License"
    assert item.category == "Anime"
