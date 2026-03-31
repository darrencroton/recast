# Recast — Claude Code Guide

## Project Overview

Recast converts YouTube channels into standard RSS podcast feeds. It has two implementations:

1. **macOS App** (`Recast/`) — A SwiftUI desktop app that discovers, downloads, and serves YouTube content as MP3 podcast episodes via a local HTTP server.
2. **Python CLI** (`cosmic_podcast.py`) — A standalone script originally built for the NSF-Simons Cosmic AI YouTube channel.

## Repository Structure

```
recast/
├── Recast/
│   ├── project.yml             XcodeGen project spec
│   ├── setup.sh                Dependency check + project generation
│   ├── Recast/                 Swift source files
│   │   ├── RecastApp.swift     App entry point
│   │   ├── Models.swift        Channel/Episode data models
│   │   ├── Store.swift         @Observable state + business logic
│   │   ├── ContentView.swift   Main UI (sidebar + episode list)
│   │   ├── AddChannelSheet.swift
│   │   ├── EpisodeListView.swift
│   │   ├── SettingsView.swift
│   │   ├── Downloader.swift    Actor: yt-dlp/ffmpeg process management
│   │   ├── FeedGenerator.swift RSS 2.0 feed generation
│   │   ├── PodcastServer.swift HTTP server (Network framework)
│   │   ├── Paths.swift         File path utilities
│   │   └── Recast.entitlements
│   └── RecastTests/            XCTest unit tests
│       ├── EpisodeTests.swift
│       ├── FeedGeneratorTests.swift
│       └── StoreTests.swift
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
cd Recast
./setup.sh          # Installs XcodeGen if needed, generates Recast.xcodeproj
open Recast.xcodeproj
# Then Cmd+R in Xcode to build and run
```

### Architecture
- **MVVM**: `AppStore` (@Observable) holds all state; views read from it via `@Environment`
- **Downloader** (actor): thread-safe yt-dlp/ffmpeg subprocess execution
- **PodcastServer**: HTTP server using Apple's Network framework on a configurable port (default 8888)
- **FeedGenerator**: Produces RSS 2.0 with iTunes podcast extensions
- State persists to `~/Library/Application Support/Recast/state.json`
- Audio files saved to `~/Music/Recast/` by default

### Key Patterns
- Use `@Observable` macro (not `ObservableObject`) for state
- Use `actor` for thread-safe I/O and subprocess management
- Use `async/await` and `Task {}` for concurrency
- Error types conform to `LocalizedError`

### Running Tests

```bash
cd Recast
./setup.sh          # Regenerate project if project.yml has changed
# Then Cmd+U in Xcode to run the full test suite
```

The `RecastTests` target uses XCTest with `@testable import Recast`. 50 tests cover:

- **`EpisodeTests`** — `isDownloaded` computed property; `formattedDuration` edge cases (zero, sub-minute, hour boundaries, padding)
- **`FeedGeneratorTests`** — `xmlEscape` (all five XML special chars); `formatDuration` (HH:MM:SS); `rfc2822` date format; `write()` end-to-end (file creation, episode inclusion/exclusion, enclosure URLs, GUIDs, XML escaping, input-order preservation)
- **`StoreTests`** — `normalizeYouTubeURL` (mobile→desktop, `/videos` suffix, playlist URLs, whitespace); `episodes(for:)` (filtering, sort order); `regenerateFeed()` (output file, filtering, sort order, port in URLs)

**What is not tested:** `Downloader` (tightly coupled to real `yt-dlp`/`ffmpeg` processes) and `PodcastServer` (requires live network ports). Both are integration-test territory.

**Testability note:** `FeedGenerator.xmlEscape/rfc2822/formatDuration` and `Store.normalizeYouTubeURL` are `internal` (not `private`) so that `@testable import` can reach them.

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
