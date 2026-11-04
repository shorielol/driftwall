from driftwall_scraper.models import Wallpaper


def make(id_: str, category: str = "Nature", rank: int = 0, uploaded: str = "2025-01-01") -> Wallpaper:
    return Wallpaper(
        id=id_,
        title=f"Title {id_}",
        description="",
        category=category,
        tags=(),
        source="mixkit",
        source_page_url=f"https://mixkit.co/free-stock-video/x-{id_}/",
        preview_url=f"https://assets.mixkit.co/{id_}-720.mp4",
        video_url=f"https://assets.mixkit.co/{id_}-2160.mp4",
        poster_url=f"https://assets.mixkit.co/{id_}.jpg",
        author="Mixkit",
        license_name="Mixkit Stock Video Free License",
        license_url="https://mixkit.co/license/#videoFree",
        duration_seconds=12,
        width=3840,
        height=2160,
        file_size_mb=40.0,
        uploaded_at=uploaded,
        source_rank=rank,
    )
