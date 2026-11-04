# Driftwall catalog scraper

Builds `catalog/catalog.json` for the Driftwall app.

- **Sources:** Mixkit public tag pages, crawled with [scrapling](https://github.com/D4Vinci/Scrapling) (robots.txt allows it; about 1 request per second). Optionally the official Pixabay and Pexels Videos APIs when `PIXABAY_API_KEY` / `PEXELS_API_KEY` are set; Pixabay is the main source of anime-style loops.
- **Kept only if:** free license, landscape and at least 1080p (the highest rendition is used; 4K is preferred and lower resolutions only fill categories short on 4K), at least 6 s long, and scenery rather than people or office close-ups (anime is exempt from the people filter).
- **Cadence:** every third Monday (anchor `2026-11-02`), driven by `.github/workflows/catalog-drop.yml`.

```bash
uv run pytest -q                                                  # tests
uv run python -m driftwall_scraper --catalog-dir ../../catalog drop --force    # build a drop now
uv run python -m driftwall_scraper --catalog-dir ../../catalog validate        # check every link
```

Files written:

| File | Purpose |
| --- | --- |
| `catalog.json` | What the app reads: drops, featured rotation, wallpapers |
| `drops/<date>.json` | One file per drop, for history |
| `seen.json` | Every id ever published, so a drop never repeats old wallpapers |
