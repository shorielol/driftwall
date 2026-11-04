<p align="center">
  <img src="App/Driftwall/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Driftwall icon">
</p>

<h1 align="center">Driftwall</h1>

<p align="center">Live wallpapers for macOS, mostly 4K and never below 1080p. Native, quiet on battery, and refreshed with a new drop every three weeks.</p>

---

Driftwall plays looping high-resolution video behind your desktop icons, on every display, without getting in your way. Browse a hand-picked catalog, preview anything instantly, and set it with one click. A new batch lands every three weeks.

Built by **Shaurya** ([@shorielol](https://github.com/shorielol)).

## Features

- **Driftwall Originals.** Eight live scenes drawn by the app itself in Metal, each in a different medium: sumi-e ink wash, papercraft diorama, stained glass, two-ink risograph, impasto oil paint, Bauhaus geometry, iridescent liquid and 1-bit dithering. They render at your display's native resolution, so they're sharp on 4K, 5K and ultrawide, and they cost nothing to download.

- **Live wallpapers behind your icons.** A borderless window at desktop level on each display, on every Space. Video is muted, hardware-decoded and loops seamlessly (`AVQueuePlayer` + `AVPlayerLooper`).
- **Every display, your way.** Apply to all screens or one. Monitors are remembered by name and size, so replugging an external display restores its wallpaper.
- **Fresh drops every 3 weeks.** The catalog is rebuilt by a scheduled GitHub Action and published to GitHub Pages. The app picks it up with a conditional request, shows a *Fresh Drop* row and a *New* badge, and can notify you.
- **Preview first, download once.** Cards and previews stream a light 720p rendition. *Set as Wallpaper* downloads the 4K original into a size-capped cache, then cross-fades it in.
- **Mostly 4K, never below 1080p.** The scraper always takes the highest rendition available and prefers 4K, using 2K or 1080p clips only to fill categories that are short on 4K. Anything under landscape 1080p is rejected by both the scraper and the app.
- **Anime, illustrated and more.** Categories include Anime, Animated, Gaming & Retro, Space, Cozy, Drive, Nature, City, Ocean, Seasons, Fantasy, Sci-fi, Wildlife, Cats and Abstract.
- **Bring your Wallspace downloads.** Library → Imported finds videos you already downloaded with Wallspace on this Mac and imports them locally, titles included.
- **Playlists, Day & Night, Light & Dark.** Rotate favourites on a timer, switch at sunrise and sunset times you choose, or follow the system appearance.
- **Auto-pause.** Per display when an app is full screen, in Low Power Mode, below 20% battery, or (optionally) whenever you're on battery. Paused while the screen is locked or asleep.
- **Your own videos.** Drag any `.mp4`, `.mov` or `.m4v` onto the window, or use Library → Imported. Each import shows its resolution, and Driftwall warns you if it's below landscape 1080p. Imports stay on your Mac.
- **Lock screen match.** Sets a still frame of the current wallpaper as the system desktop picture, so the lock screen and Mission Control match (see *Limitations*).
- **Menu bar controls.** Pause, skip, and see what's on each display.
- **Liquid Glass UI.** SwiftUI with `glassEffect` on macOS 26+ (material fallback on macOS 15), a Metal topographic-flow background, prismatic buttons, and a fan gallery. Honours Reduce Motion and Reduce Transparency.
- **Private.** No accounts, no analytics. The only network calls fetch the catalog, posters and the videos you choose.

## Requirements

- macOS 15 Sequoia or later (Liquid Glass effects need macOS 26+)
- Building from source: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [uv](https://github.com/astral-sh/uv) for the scraper

## Build and run

```bash
brew install xcodegen
git clone https://github.com/shorielol/driftwall.git
cd driftwall
make run        # generates the Xcode project, builds Release and opens the app
```

Or open it in Xcode: `make project && open Driftwall.xcodeproj`.

Builds are ad-hoc signed. If macOS blocks a downloaded build, right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/Driftwall.app`.

## Tests

```bash
make test       # Swift package tests + scraper tests
```

`DriftwallCore` holds all the logic that can be tested without a screen (catalog validation, search and sort, playlists, day/night scheduling, auto-pause policy, display assignments, the video cache and catalog refresh) and sits at roughly 88% line coverage.

## How the catalog works

```
tools/scraper  ──(scrapling)──▶  catalog/catalog.json  ──(GitHub Pages)──▶  Driftwall.app
                                 catalog/drops/<date>.json
                                 catalog/seen.json
```

1. `.github/workflows/catalog-drop.yml` runs every Monday. A guard publishes only every third week (`--force` overrides it).
2. The scraper uses [scrapling](https://github.com/D4Vinci/Scrapling) to crawl Mixkit's public tag pages (robots.txt allows this) at about one request per second. It opens only cards flagged 4K and keeps items that:
   - carry the **Mixkit Stock Video Free License**,
   - have a landscape rendition of **1080p or better** (4K preferred),
   - run at least 6 seconds,
   - look like scenery rather than people or office close-ups.
3. Optional official APIs, enabled by repository secrets:
   - `PIXABAY_API_KEY`: the main source of anime-style and illustrated loops ([get a free key](https://pixabay.com/api/docs/)).
   - `PEXELS_API_KEY`: more scenery and some anime-style clips ([get a free key](https://www.pexels.com/api/)).
   Both keep only landscape renditions of 1080p or better, highest first.
4. Each drop adds about 40 wallpapers the catalog has never shown, balanced across categories, with a new featured rotation. Every link is checked before publishing, and dead entries are pruned.
5. The app ships the latest catalog as an offline seed, refreshes on launch and daily with `If-None-Match`, validates everything (schema, https only, allow-listed hosts, at least 1080p), and never replaces a good catalog with a bad one.

Run a drop locally with `make catalog`.

### Open-licence film loops

`tools/loops/make_loops.py` cuts seamless 4K loops from Creative Commons films, such as Blender Studio's open movies (CC BY). It crossfades each clip's tail into its head so there is no visible seam, encodes a 4K master and a 720p preview, and writes `catalog/open-films.json`. Upload the files in `dist/films/` to a GitHub Release tagged `films-v1` (`gh release create films-v1 dist/films/*`). The next catalog drop then adds every loop whose files are reachable, with attribution.

**Publishing the catalog:** in the GitHub repo settings, set *Pages → Source* to **GitHub Actions**. The URL the app reads is set by `DriftwallCatalogURL` in `project.yml`.

## Project layout

```
App/Driftwall/            SwiftUI + AppKit app
  Engine/                 desktop windows, looping player, system monitors, lock-screen still
  Model/                  AppModel (state + intents) and playback coordination
  Services/               paths, logging, poster cache, login item, notifications, import
  UI/                     theme, glass, effects (Metal), components, screens, onboarding
Packages/DriftwallCore/   testable logic (Swift Testing)
tools/scraper/            catalog builder (Python, scrapling, pytest)
catalog/                  published catalog and drop history
project.yml               XcodeGen spec
```

## Limitations

- **Lock screen animation.** macOS has no public API for animated lock screens. The only way third-party apps do it is by loading Apple's private `WallpaperExtensionKit`, which breaks between OS releases and requires Developer ID signing. Driftwall shows a matching still frame instead.
- Video playback uses some GPU time. Auto-pause keeps it near zero when you're in a full-screen app or on low battery.

## Credits and licensing

- Code: MIT, see [LICENSE](LICENSE).
- Videos: streamed and downloaded from their creators' sources and **not** covered by the MIT license. Mixkit clips are under the [Mixkit Stock Video Free License](https://mixkit.co/license/#videoFree), Pexels clips under the [Pexels License](https://www.pexels.com/license/), Pixabay clips under the [Pixabay Content License](https://pixabay.com/service/license-summary/). Every preview credits its source and links to the original. Driftwall is not affiliated with Mixkit, Envato, Pexels or Pixabay.
- The public catalog never includes copyrighted characters or franchises. Videos you import yourself stay on your Mac.
