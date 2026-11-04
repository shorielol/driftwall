.PHONY: project build run test test-core test-scraper release catalog films clean

DERIVED := .build/xcode
APP := $(DERIVED)/Build/Products/Release/Driftwall.app

project:
	xcodegen generate

build: project
	xcodebuild -project Driftwall.xcodeproj -scheme Driftwall -configuration Release -derivedDataPath $(DERIVED) build

run: build
	open $(APP)

test: test-core test-scraper

test-core:
	cd Packages/DriftwallCore && swift test --enable-code-coverage

test-scraper:
	cd tools/scraper && uv run pytest -q

# Rebuild the catalog locally (ignores the 3-week schedule).
catalog:
	uv run --project tools/scraper python -m driftwall_scraper --catalog-dir catalog drop --force

# Cut CC-BY film loops: make films SOURCE=/path/to/film.mp4 SEGMENTS=tools/loops/segments.bbb.json
films:
	python3 tools/loops/make_loops.py --source "$(SOURCE)" --segments "$(SEGMENTS)" --out dist/films

release: build
	mkdir -p dist
	ditto -c -k --keepParent $(APP) dist/Driftwall.zip
	@echo "dist/Driftwall.zip"

clean:
	rm -rf .build dist Driftwall.xcodeproj
