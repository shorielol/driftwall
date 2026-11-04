"""Immutable data models shared by the scraper, catalog builder and validator."""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any

SCHEMA_VERSION = 1


@dataclass(frozen=True)
class Wallpaper:
    """One live wallpaper entry. Only metadata and links; media stays at the source."""

    id: str
    title: str
    description: str
    category: str
    tags: tuple[str, ...]
    source: str
    source_page_url: str
    preview_url: str
    video_url: str
    poster_url: str
    author: str
    license_name: str
    license_url: str
    duration_seconds: int
    width: int
    height: int
    file_size_mb: float
    uploaded_at: str
    source_rank: int = 0
    added_in_drop: str = ""

    def with_changes(self, **changes: Any) -> Wallpaper:
        return replace(self, **changes)

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "category": self.category,
            "tags": list(self.tags),
            "source": self.source,
            "sourcePageUrl": self.source_page_url,
            "previewUrl": self.preview_url,
            "videoUrl": self.video_url,
            "posterUrl": self.poster_url,
            "author": self.author,
            "license": self.license_name,
            "licenseUrl": self.license_url,
            "durationSeconds": self.duration_seconds,
            "width": self.width,
            "height": self.height,
            "fileSizeMB": self.file_size_mb,
            "uploadedAt": self.uploaded_at,
            "sourceRank": self.source_rank,
            "addedInDrop": self.added_in_drop,
        }

    @staticmethod
    def from_json(data: dict[str, Any]) -> Wallpaper:
        return Wallpaper(
            id=str(data["id"]),
            title=str(data["title"]),
            description=str(data.get("description", "")),
            category=str(data["category"]),
            tags=tuple(str(t) for t in data.get("tags", [])),
            source=str(data["source"]),
            source_page_url=str(data["sourcePageUrl"]),
            preview_url=str(data["previewUrl"]),
            video_url=str(data["videoUrl"]),
            poster_url=str(data["posterUrl"]),
            author=str(data.get("author", "")),
            license_name=str(data["license"]),
            license_url=str(data.get("licenseUrl", "")),
            duration_seconds=int(data["durationSeconds"]),
            width=int(data["width"]),
            height=int(data["height"]),
            file_size_mb=float(data.get("fileSizeMB", 0.0)),
            uploaded_at=str(data.get("uploadedAt", "")),
            source_rank=int(data.get("sourceRank", 0)),
            added_in_drop=str(data.get("addedInDrop", "")),
        )


@dataclass(frozen=True)
class Drop:
    drop_id: str
    date: str
    ids: tuple[str, ...]

    def to_json(self) -> dict[str, Any]:
        return {"dropId": self.drop_id, "date": self.date, "ids": list(self.ids)}

    @staticmethod
    def from_json(data: dict[str, Any]) -> Drop:
        return Drop(drop_id=str(data["dropId"]), date=str(data["date"]), ids=tuple(data["ids"]))


@dataclass(frozen=True)
class Catalog:
    schema_version: int
    generated_at: str
    drop_id: str
    next_drop_at: str
    featured: tuple[str, ...]
    drops: tuple[Drop, ...]
    wallpapers: tuple[Wallpaper, ...]

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "generatedAt": self.generated_at,
            "dropId": self.drop_id,
            "nextDropAt": self.next_drop_at,
            "featured": list(self.featured),
            "drops": [d.to_json() for d in self.drops],
            "wallpapers": [w.to_json() for w in self.wallpapers],
        }

    @staticmethod
    def from_json(data: dict[str, Any]) -> Catalog:
        return Catalog(
            schema_version=int(data["schemaVersion"]),
            generated_at=str(data["generatedAt"]),
            drop_id=str(data["dropId"]),
            next_drop_at=str(data["nextDropAt"]),
            featured=tuple(data.get("featured", [])),
            drops=tuple(Drop.from_json(d) for d in data.get("drops", [])),
            wallpapers=tuple(Wallpaper.from_json(w) for w in data.get("wallpapers", [])),
        )

    @staticmethod
    def empty() -> Catalog:
        return Catalog(
            schema_version=SCHEMA_VERSION,
            generated_at="",
            drop_id="",
            next_drop_at="",
            featured=(),
            drops=(),
            wallpapers=(),
        )
