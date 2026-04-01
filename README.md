# Recast

A native macOS app that turns YouTube channels and one-off YouTube episodes into a podcast feed. Add sources, fetch new talks, and subscribe in any podcast app on your phone.

## Quick Start

```bash
./setup.sh
```

This generates the Xcode project, builds a Release app, and copies `Recast.app` into the repo root so it is obvious where to find it.

From there you can:

1. Drag `Recast.app` into `/Applications`
2. Double-click it to run

If you also want the Xcode project opened for development, run:

```bash
./setup.sh --open-xcode
```

**Requirements:** macOS 14+, Xcode 15+. The app automatically downloads `yt-dlp` and `ffmpeg` on first launch — no terminal setup needed.

For day-to-day development, the repo-root `./setup.sh` is the intended entry point. It delegates to `Recast/setup.sh`, regenerates the Xcode project, builds a fresh Release app bundle, and reveals `Recast.app` in Finder.

## How It Works

1. **Add sources** — Press `+` and paste a YouTube channel, playlist, or direct episode URL
2. **Refresh sources** — Select one or more sidebar sources, then press Refresh to discover episodes
3. **Download what you want** — Download individual episodes, or multi-select episodes with standard macOS selection for batch download/delete
4. **Subscribe** — Start the built-in podcast server and scan the QR code from your phone

## Subscribe on Your Phone

1. Click the server toggle in the toolbar to start serving
2. Click the **QR code** button in the toolbar
3. Scan the QR code with your phone — it contains the feed URL with your Mac's local IP
4. The URL opens directly in your podcast app:
   - **iOS:** Apple Podcasts > Library > Edit > Add a Show by URL
   - **Android:** Pocket Casts > Search > "Add by URL" / AntennaPod > + > Add podcast > RSS URL

You can also manually add the feed URL shown in the status bar or Settings.

## Features

### Core
- **Source management** — Add/remove YouTube channels, playlists, and one-off episode links
- **Direct episode capture** — Paste a `watch`, `youtu.be`, or `shorts` URL to save just that episode without subscribing to the full channel
- **Episode discovery** — Refresh finds new episodes without downloading; you choose what to grab
- **Responsive refresh** — Discovery uses YouTube playlist metadata for fast first-pass episode detection
- **Selective download** — Download individual episodes or selected episodes
- **Download progress** — Per-episode progress weighted toward the final MP3 becoming available
- **Stop controls** — Stop an individual download from the row/context menu or stop all active downloads from the toolbar when downloads are running
- **Podcast feed** — Standard RSS 2.0 with iTunes extensions, compatible with all podcast apps
- **Built-in server** — HTTP server hosts your feed on the local network

### Search & Browse
- **All Episodes view** — See every episode across all saved sources in one list
- **Search** — Filter episodes by title across all saved sources
- **Episode filters** — Quick-filter by All, Downloaded, New (found in the latest fetch for the current scope), or Unplayed
- **Native multi-selection** — Click, Shift-click, and Command-click work like Finder for sources and episodes
- **Selection-aware actions** — Toolbar and right-click menus expose Refresh, Download, and Delete for the current selection
- **Played/Unplayed** — Mark episodes to track what you've listened to

### Automation
- **Auto-fetch** — Automatically check for new episodes every 6, 12, or 24 hours
- **Auto-start server** — Optionally start the podcast server when the app launches

### Convenience
- **QR code** — One-tap QR code with your feed URL for instant phone setup
- **Reveal in Finder** — Right-click any downloaded episode to open it in Finder
- **Source-organised storage** — Downloaded audio lives under `episodes/<Channel Name [id]>` inside the chosen output folder, including one-off episode sources
- **Channel monograms** — Visual channel identity with colour-coded initials
- **Episode deletion** — Remove episodes (and their audio files) from within the app
- **Diagnostics log** — File-backed logs live at `~/Library/Application Support/Recast/logs/recast.log`

## Settings

Open **Recast > Settings** (Cmd+,) to configure:
- **Episodes folder** — where MP3 files and the feed are stored (default: `~/Music/Recast`)
  Downloaded episodes are organised under `episodes/<Channel Name [id]>` inside that folder.
- **Server port** — change the HTTP server port
- **Auto-start server** — launch the podcast server when the app opens
- **Auto-fetch interval** — check for new episodes on a schedule
- **Dependency status** — confirm whether `yt-dlp` and `ffmpeg` are installed
- **Reset App to Defaults** — clears saved sources, episode state, Recast-managed downloads and feeds, and installed tools while keeping diagnostic logs
  The next launch will re-download `yt-dlp` and `ffmpeg` as needed.

## Running Tests

```bash
./setup.sh --open-xcode
# Then Cmd+U in Xcode
```

Or from the command line:

```bash
cd Recast
xcodebuild test -scheme Recast -destination 'platform=macOS'
```

The test suite currently covers reset safety, episode models, RSS feed generation, XML escaping, store logic, search filtering, source-organised output paths, episode management, downloader parsing/cleanup helpers, and persistence hygiene. See `RecastTests/` for details.

## CLI Alternative

A standalone Python script is also included for quick command-line use:

```bash
pip install -r requirements.txt
python cosmic_podcast.py --serve
```

See `cosmic_podcast.py --help` for options.

## Project Structure

```
Recast/               macOS SwiftUI app
├── Recast/           Source files
│   ├── RecastApp.swift       App entry point
│   ├── AppLogger.swift       File-backed app diagnostics
│   ├── Models.swift          Channel & Episode data models
│   ├── Store.swift           App state, persistence, business logic
│   ├── ContentView.swift     Main split view, selection-aware toolbar, QR code, status bar
│   ├── EpisodeListView.swift Episode list, native multi-selection, context menus, progress
│   ├── AddChannelSheet.swift Add-source modal
│   ├── SettingsView.swift    Preferences window
│   ├── Downloader.swift      yt-dlp/ffmpeg wrapper with progress/cancellation
│   ├── FeedGenerator.swift   RSS feed builder
│   ├── PodcastServer.swift   HTTP server (NWListener)
│   └── Paths.swift           File path management
├── RecastTests/      XCTest unit tests
├── project.yml       XcodeGen config
└── setup.sh          Generates the project and builds the app bundle
cosmic_podcast.py     Standalone CLI tool
setup.sh              Repo-root wrapper that leaves Recast.app at the top level
```
