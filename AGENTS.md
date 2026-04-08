# Recast Agent Guide

## Project Overview

Recast converts YouTube sources into standard RSS podcast feeds. A source can be a YouTube channel, playlist, or a one-off direct episode link. It is a macOS SwiftUI app (`Recast/`) that discovers, downloads, and serves YouTube content as MP3 podcast episodes via a local HTTP server.

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
│   ├── RecastTests/            XCTest unit tests
│   │   ├── EpisodeTests.swift
│   │   ├── FeedGeneratorTests.swift
│   │   ├── ModelTests.swift
│   │   └── StoreTests.swift
│   └── scripts/
│       └── render_app_icon.swift
├── Recast.app                  Generated Release app bundle after setup
└── README.md
```

## Architecture

- **MVVM**: `AppStore` (@Observable) holds all state; views read from it via `@Environment`
- **Downloader** (actor): thread-safe yt-dlp/ffmpeg subprocess execution
- **Discovery**: collection-source refresh uses yt-dlp playlist metadata for a faster first-pass episode listing
- **PodcastServer**: HTTP server using Apple's Network framework, binds to `0.0.0.0` on a configurable port (default 8888)
- **FeedGenerator**: produces RSS 2.0 with iTunes podcast extensions
- **Server address**: `serverHost` (persisted, default empty) overrides the auto-detected local IP. `resolvedHost` returns `serverHost` if set, otherwise falls back to `localIPAddress ?? "localhost"`. All feed URLs and the generated feed XML use `resolvedHost`. This allows users to configure a Tailscale IP or other custom address.
- **Local state** (machine-specific settings: server port/host, auto-fetch interval, episodes directory path) persists to `~/Library/Application Support/Recast/state.json`
- **Shared state** (channels and episodes — the data that should be the same on every machine) persists to `<episodesDirectory>/.recast/shared-state.json`. Downloaded episode artwork persists alongside it under `<episodesDirectory>/.recast/artwork/`. Because `episodesDirectory` can point to a cloud-synced folder (iCloud Drive, Dropbox, etc.), these shared artifacts sync automatically between Macs without any additional infrastructure.
- Diagnostics log at `~/Library/Application Support/Recast/logs/recast.log`
- Feed/server artifacts live under `~/Library/Application Support/Recast/server/` and are regenerated locally from the shared state, shared artwork, and shared MP3 files
- Audio files are saved to the configured episodes folder directly, under `<Channel Name [id]>/` at that root (default root: `~/Music/Recast/`)
- The `.recast/` hidden directory inside the episodes folder is system-managed; it holds synced metadata and artwork, and users should not need to manage it directly

## Setup & Build

```bash
./setup.sh              # Generate project, build Release app
./setup.sh --open-xcode # Same, then open Recast.xcodeproj
```

Requirements: macOS 14.0+, Xcode 15+, XcodeGen (`brew install xcodegen`).

## Key Patterns

- Use `@Observable` macro (not `ObservableObject`) for state
- Main-thread UI state in `AppStore` should be mutated from `@MainActor` methods
- Use `actor` for thread-safe I/O and subprocess management
- Use `async/await` and `Task {}` for concurrency
- Error types conform to `LocalizedError`
- Keep one unified saved-source model. Prefer extending existing source/channel flows over creating separate ad-hoc paths for direct episode URLs.
- Keep episode ordering newest-first unless a feature explicitly calls for a different presentation
- The `New` filter means "found in the most recent fetch for the current scope", not "all undownloaded episodes"
- Auto-fetch should download only newly discovered episodes, never an older undownloaded backlog, and it should keep retrying scheduled-download failures until a download succeeds
- Adding a direct episode URL should stay consistent with Recast's existing explicit-download model: add/save first, then download via normal download controls
- Source and episode multi-selection are shared across `ContentView` and `EpisodeListView`; preserve standard macOS click, Shift-click, and Command-click behaviour
- Toolbar actions split into global (server, QR code, add source) and selection-scoped (refresh, download, delete); right-click menus follow the same selection rules
- Reset only removes Recast-managed output artifacts and installed tools; diagnostic logs are intentionally preserved

## Running Tests

```bash
cd Recast
xcodebuild test -scheme Recast -destination 'platform=macOS'
```

The suite covers reset safety, episode models, RSS feed generation, XML escaping, store logic, search filtering, auto-fetch candidate selection and retry state, source-organised output paths, episode management, downloader parsing/cleanup helpers, and persistence. `FeedGenerator.xmlEscape/rfc2822/formatDuration`, `Store.normalizeYouTubeURL`, `Store.autoFetchDownloadTargets`, and several downloader helpers are intentionally not `private` so `@testable import` can reach them.

Live yt-dlp/ffmpeg subprocess execution and `PodcastServer` on real network ports are not unit tested.

## Code Style (Swift)

- PascalCase for types, camelCase for properties/methods
- `MARK:` comments to separate logical sections within files
- Prefer `struct` over `class` for models; use `actor` for shared mutable state
