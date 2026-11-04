"""Category taxonomy and the Mixkit tags crawled for each category."""

from __future__ import annotations

FALLBACK_CATEGORY = "Abstract"

# Ordered from most specific to most generic: the first match wins for item tags.
CATEGORY_TAGS: dict[str, tuple[str, ...]] = {
    # Anime comes only from the Pixabay/Pexels APIs; Mixkit's "anime" tag is vintage comics.
    "Anime": (),
    "Cats": ("cat", "cats", "kitten"),
    "Wildlife": ("wildlife", "birds", "bird", "butterfly", "fish", "jellyfish"),
    "Animated": ("animation", "illustration", "drawing", "cartoon", "motion-graphics", "gradient"),
    "Gaming": ("video-game", "game", "gaming", "retro", "lo-fi", "arcade", "neon-lights"),
    "Space": ("space", "galaxy", "stars", "aurora", "nebula", "planet", "night-sky", "moon"),
    "Ocean": ("ocean", "waves", "beach", "underwater", "sea"),
    "Drive": ("cars", "car", "driving", "road", "highway"),
    "Cozy": ("cozy", "fireplace", "fire", "rain", "candle", "candles", "storm", "lightning"),
    "Seasons": ("flowers", "flower", "spring", "autumn", "fall", "leaves", "garden", "christmas", "halloween", "lanterns"),
    "Sci-fi": ("futuristic", "technology", "cyberpunk", "hologram"),
    "Fantasy": ("fantasy", "magic", "dragon", "dreamy", "mystical", "glow", "fairy"),
    "City": ("city", "neon", "japan", "tokyo", "traffic", "skyline"),
    "Nature": ("nature", "forest", "mountain", "waterfall", "sunset", "clouds", "snow", "winter", "desert", "windmill"),
    "Abstract": ("abstract", "marble", "ink", "fluid", "liquid", "smoke", "particles", "bokeh", "bubbles", "3d"),
}

_TAG_TO_CATEGORY: dict[str, str] = {
    tag: category for category, tags in CATEGORY_TAGS.items() for tag in tags
}


def crawl_tags() -> list[tuple[str, str]]:
    """(category, tag) pairs to crawl, in taxonomy order."""
    return [(category, tag) for category, tags in CATEGORY_TAGS.items() for tag in tags]


def categorize(query_tag: str, item_tags: tuple[str, ...]) -> str:
    if query_tag in _TAG_TO_CATEGORY:
        return _TAG_TO_CATEGORY[query_tag]
    tag_set = set(item_tags)
    for category, tags in CATEGORY_TAGS.items():
        if tag_set.intersection(tags):
            return category
    return FALLBACK_CATEGORY

# Optional Pexels API queries (category, query). Seeded from the owner's taste:
# cozy illustrated scenes, dark marble/abstract, scenic evening drives, nature.
PEXELS_QUERIES: tuple[tuple[str, str], ...] = (
    ("Anime", "anime landscape"),
    ("Anime", "anime city night"),
    ("Cozy", "cozy cabin night"),
    ("Cozy", "rain window night"),
    ("Abstract", "dark marble"),
    ("Abstract", "ink in water"),
    ("Drive", "evening drive countryside"),
    ("Drive", "wind turbines road sunset"),
    ("Nature", "forest fog"),
    ("Nature", "mountain lake"),
    ("Space", "aurora borealis"),
    ("Space", "milky way timelapse"),
    ("City", "neon city night"),
    ("Ocean", "ocean waves aerial"),
    ("Cats", "cat sleeping"),
    ("Sci-fi", "futuristic tunnel"),
    ("Fantasy", "magical forest"),
)

# Optional Pixabay API queries: the richest licensed source of anime-style and illustrated loops.
PIXABAY_QUERIES: tuple[tuple[str, str], ...] = (
    ("Anime", "anime"),
    ("Anime", "anime landscape"),
    ("Anime", "anime city"),
    ("Anime", "anime night"),
    ("Anime", "lofi anime"),
    ("Anime", "anime rain"),
    ("Anime", "anime sky"),
    ("Anime", "anime sunset"),
    ("Animated", "cartoon"),
    ("Animated", "illustration loop"),
    ("Gaming", "pixel art"),
    ("Gaming", "synthwave"),
    ("Fantasy", "fantasy landscape"),
    ("Cozy", "cozy room rain"),
    ("Space", "galaxy loop"),
)
