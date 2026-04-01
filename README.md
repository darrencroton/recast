# Recast

A native macOS app that turns YouTube channels into a podcast feed. Add channels, fetch new talks, and subscribe in any podcast app on your phone.

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

## How It Works

1. **Add channels** — Press `+` and paste a YouTube channel or playlist URL
2. **Fetch episodes** — Press Fetch to discover new episodes across your channels
3. **Download what you want** — Download individual episodes or hit Download All
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
- **Channel management** — Add/remove YouTube channels and playlists
- **Episode discovery** — Fetch lists new episodes without downloading; you choose what to grab
- **Selective download** — Download individual episodes or all at once
- **Download progress** — Real-time percentage progress for each download
- **Podcast feed** — Standard RSS 2.0 with iTunes extensions, compatible with all podcast apps
- **Built-in server** — HTTP server hosts your feed on the local network

### Search & Browse
- **All Episodes view** — See every episode across all channels in one list
- **Search** — Filter episodes by title across all channels
- **Episode filters** — Quick-filter by All, Downloaded, New (undownloaded), or Unplayed
- **Played/Unplayed** — Mark episodes to track what you've listened to

### Automation
- **Auto-fetch** — Automatically check for new episodes every 6, 12, or 24 hours
- **Auto-start server** — Optionally start the podcast server when the app launches

### Convenience
- **QR code** — One-tap QR code with your feed URL for instant phone setup
- **Reveal in Finder** — Right-click any downloaded episode to open it in Finder
- **Channel monograms** — Visual channel identity with colour-coded initials
- **Episode deletion** — Remove episodes (and their audio files) from within the app

## Settings

Open **Recast > Settings** (Cmd+,) to configure:
- **Episodes folder** — where MP3 files and the feed are stored (default: `~/Music/Recast`)
- **Server port** — change the HTTP server port
- **Auto-start server** — launch the podcast server when the app opens
- **Auto-fetch interval** — check for new episodes on a schedule

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

The test suite covers episode models, RSS feed generation, XML escaping, store logic, search filtering, and episode management. See `RecastTests/` for details.

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
│   ├── Models.swift          Channel & Episode data models
│   ├── Store.swift           App state, persistence, business logic
│   ├── ContentView.swift     Main UI: sidebar, toolbar, QR code, status bar
│   ├── EpisodeListView.swift Episode list, filters, context menus, progress
│   ├── AddChannelSheet.swift Add-channel modal
│   ├── SettingsView.swift    Preferences window
│   ├── Downloader.swift      yt-dlp/ffmpeg wrapper with progress streaming
│   ├── FeedGenerator.swift   RSS feed builder
│   ├── PodcastServer.swift   HTTP server (NWListener)
│   └── Paths.swift           File path management
├── RecastTests/      XCTest unit tests
├── project.yml       XcodeGen config
└── setup.sh          Generates the project and builds the app bundle
cosmic_podcast.py     Standalone CLI tool
setup.sh              Repo-root wrapper that leaves Recast.app at the top level
```
