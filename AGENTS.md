# Recast Agent Guide

## Project Overview

Recast converts YouTube channels into standard RSS podcast feeds. It has two implementations:

1. **macOS App** (`Recast/`) — A SwiftUI desktop app that discovers, downloads, and serves YouTube content as MP3 podcast episodes via a local HTTP server.
2. **Python CLI** (`cosmic_podcast.py`) — A standalone script originally built for the NSF-Simons Cosmic AI YouTube channel.

## Repository Structure

```
recast/
├── setup.sh                    Repo-root wrapper for build/dev setup
├── Recast/
│   ├── project.yml             XcodeGen project spec
│   ├── setup.sh                Generate project + build/reveal Release app bundle
│   ├── Recast/                 Swift source files
│   │   ├── RecastApp.swift     App entry point
│   │   ├── AppLogger.swift     File-backed diagnostics
│   │   ├── Models.swift        Channel/Episode data models
│   │   ├── Store.swift         @Observable state + business logic
│   │   ├── ContentView.swift   Main UI (sidebar + toolbar + status bar)
│   │   ├── AddChannelSheet.swift
│   │   ├── EpisodeListView.swift
│   │   ├── SettingsView.swift
│   │   ├── Downloader.swift    Actor: yt-dlp/ffmpeg download + progress/cancel flow
│   │   ├── FeedGenerator.swift RSS 2.0 feed generation
│   │   ├── PodcastServer.swift HTTP server (Network framework)
│   │   ├── Paths.swift         File path utilities
│   │   └── Recast.entitlements
│   └── RecastTests/            XCTest unit tests
│       ├── EpisodeTests.swift
│       ├── FeedGeneratorTests.swift
│       ├── ModelTests.swift
│       └── StoreTests.swift
├── Recast.app                  Generated Release app bundle after setup
├── cosmic_podcast.py           Python CLI tool
├── requirements.txt            Python deps (yt-dlp)
└── README.md
```

## macOS App

### Requirements
- macOS 14.0+
- Xcode 15+
- XcodeGen (`brew install xcodegen`)

### Setup & Build
```bash
./setup.sh              # Preferred: generate project, build Release app, reveal Recast.app
./setup.sh --open-xcode # Same, then open Recast.xcodeproj
```

The repo-root `setup.sh` delegates to `Recast/setup.sh`. The built app bundle is copied to `Recast.app` in the repo root for easy tester handoff.

### Architecture
- **MVVM**: `AppStore` (@Observable) holds all state; views read from it via `@Environment`
- **Downloader** (actor): thread-safe yt-dlp/ffmpeg subprocess execution
- **PodcastServer**: HTTP server using Apple's Network framework on a configurable port (default 8888)
- **FeedGenerator**: Produces RSS 2.0 with iTunes podcast extensions
- State persists to `~/Library/Application Support/Recast/state.json`
- Diagnostics log persists to `~/Library/Application Support/Recast/logs/recast.log`
- Audio files saved to `~/Music/Recast/` by default

### Key Patterns
- Use `@Observable` macro (not `ObservableObject`) for state
- Main-thread UI state in `AppStore` should be mutated from `@MainActor` methods
- Use `actor` for thread-safe I/O and subprocess management
- Use `async/await` and `Task {}` for concurrency
- Error types conform to `LocalizedError`
- Keep episode ordering newest-first unless a feature explicitly calls for a different presentation
- The `New` filter is "found in the most recent fetch for the current scope", not "all undownloaded episodes"
- Channel and episode multi-selection are shared across `ContentView` and `EpisodeListView`; preserve standard macOS click, Shift-click, and Command-click behavior
- Toolbar actions are split into global actions (server, QR code, add channel) and selection-scoped actions (refresh, download, delete); keep right-click menus aligned with the same selection rules
- Reset only removes Recast-managed output artifacts and installed tools; diagnostic logs are intentionally preserved

### Running Tests

```bash
./setup.sh --open-xcode
# Then Cmd+U in Xcode
```

Or from the command line:

```bash
cd Recast
xcodebuild test -scheme Recast -destination 'platform=macOS'
```

The `RecastTests` target uses XCTest with `@testable import Recast`. The suite currently covers:

- **`EpisodeTests`** — `isDownloaded` computed property; `formattedDuration` edge cases (zero, sub-minute, hour boundaries, padding)
- **`ModelTests`** — filename generation, backwards-compatible episode decoding, publish-date fallbacks, yt-dlp list parsing, downloader progress parsing, and progress weighting helpers
- **`FeedGeneratorTests`** — `xmlEscape` (all five XML special chars); `formatDuration` (HH:MM:SS); `rfc2822` date format; `write()` end-to-end (file creation, episode inclusion/exclusion, enclosure URLs, GUIDs, XML escaping, input-order preservation)
- **`StoreTests`** — `normalizeYouTubeURL` (mobile→desktop, `/videos` suffix, playlist URLs, whitespace); `episodes(for:)` (filtering, sort order); filtered counts; `regenerateFeed()` (output file, filtering, sort order, port in URLs); persistence hygiene; downloader artifact cleanup; reset safety for managed cleanup and preservation of unowned artifacts

**What is not tested:** live `yt-dlp`/`ffmpeg` subprocess execution, end-to-end media conversion timing, and `PodcastServer` on real network ports. Downloader parsing/cleanup helpers are unit tested, but real downloads remain integration-test territory.

**Testability note:** `FeedGenerator.xmlEscape/rfc2822/formatDuration`, `Store.normalizeYouTubeURL`, and several downloader parsing/cleanup helpers are intentionally not `private` so `@testable import` can reach them.

## Python CLI

### Requirements
- Python 3
- `ffmpeg` installed on PATH

### Setup & Run
```bash
pip install -r requirements.txt
python cosmic_podcast.py --help
python cosmic_podcast.py --serve       # Start local podcast server
python cosmic_podcast.py --max 5       # Fetch latest 5 episodes only
```

## External Dependencies (Auto-downloaded by macOS app)
- **yt-dlp** — fetched from GitHub releases on first launch
- **ffmpeg** — downloaded and cached in app support directory

## Code Style

**Swift:**
- PascalCase for types, camelCase for properties/methods
- `MARK:` comments to separate logical sections within files
- Prefer `struct` over `class` for models; use `actor` for shared mutable state

**Python:**
- PEP 8 conventions
- Type hints on function signatures
