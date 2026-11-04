from driftwall_scraper.models import Wallpaper


def make(id_: str, category: str = "Nature", rank: int = 0, uploaded: str = "2025-01-01") -> Wallpaper:
    return Wallpaper(
        id=id_,
        title=f"Title {id_}",
        description="",
        category=category,
        tags=(),
        source="esa",
        source_page_url=f"https://esawebb.org/videos/{id_}/",
        preview_url=f"https://github.com/shorielol/driftwall/releases/download/loops-v1/{id_}-720.mp4",
        video_url=f"https://github.com/shorielol/driftwall/releases/download/loops-v1/{id_}-2160.mp4",
        poster_url=f"https://github.com/shorielol/driftwall/releases/download/loops-v1/{id_}.jpg",
        author="ESA/Webb",
        license_name="CC BY 4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        duration_seconds=12,
        width=3840,
        height=2160,
        file_size_mb=40.0,
        uploaded_at=uploaded,
        source_rank=rank,
    )
