.PHONY: project build run test test-core test-scraper release catalog loops discover clean

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

# Render seamless 4K loops from the manifests (sources go in dist/sources): make loops
loops:
	python3 tools/loops/make_loops.py tools/loops/manifests/*.json

# List new 4K ESA/Webb and ESA/Hubble pans worth curating into manifests
discover:
	uv run --project tools/scraper python -m driftwall_scraper --catalog-dir catalog discover

release: build
	mkdir -p dist
	ditto -c -k --keepParent $(APP) dist/Driftwall.zip
	@echo "dist/Driftwall.zip"

clean:
	rm -rf .build dist Driftwall.xcodeproj
