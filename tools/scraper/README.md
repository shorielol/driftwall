# Driftwall catalog tools

Builds `catalog/catalog.json` for the Driftwall app from- **Backlog:** `catalog/loops.json`, written by `tools/loops/make_loops.py` from the shot manifests in `tools/loops/manifests/`. Only redistributable sources are used (NASA, ESA/Webb, ESA/Hubble, Blender open movies).
- **Drops:** each drop releases the next loops whose GitHub Release files are reachable (`--skip-link-check` trusts the backlog, for seeding before the release exists) and rotates the featured row.
- **Discovery:** `discover` uses [scrapling](https://github.com/D4Vinci/Scrapling) to list new 4K ESA/Webb and ESA/Hubble pans and zooms into `catalog/candidates.json` for a person to review.
pt from the people filter).
- **Cadence:** every third Monday (anchor `2026-11-02`), driven by `.github/workflows/catalog-drop.yml`.

```bash
uv run pytest -q                                                  # tests
uv run python -m driftwall_scraper --catalog-dir ../../catalog drop --force    # build a drop now
uv run python -m driftwall_scraper --catalog-dir ../../catalog validate        # check every link
uv run python -m driftwall_scraper --catalog-dir ../../catalog discover --manifests ../loops/manifests  # new candidates
```

Files written:

| File | Purpose |
| --- | --- |
| `catalog.json` | What the app reads: drops, featured rotation, wallpapers |
| `drops/<date>.json` | One file per drop, for history |
| `seen.json` | Every id ever published, so a drop never repeats old wallpapers |
