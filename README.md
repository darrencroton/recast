# Recast

A native macOS app that turns YouTube channels and one-off YouTube episodes into a podcast feed. Add sources, fetch new talks, and subscribe in any podcast app on your phone.

## Quick Start

```bash
./setup.sh
```

Generates the Xcode project, builds a Release app, and places `Recast.app` in the repo root. Drag it to `/Applications` and run.

For development, open the project in Xcode:

```bash
./setup.sh --open-xcode
```

**Requirements:** macOS 14+, Xcode 15+. The app automatically downloads `yt-dlp` and `ffmpeg` on first launch.

## How It Works

1. **Add sources** — Press `+` and paste a YouTube channel, playlist, or direct episode URL
2. **Refresh sources** — Select one or more sidebar sources, then press Refresh to discover episodes
3. **Download what you want** — Download individual episodes, or multi-select for batch download/delete
4. **Subscribe** — Start the built-in podcast server and scan the QR code from your phone

## Subscribe on Your Phone

1. Click the server toggle in the toolbar to start serving
2. Click the **QR code** button in the toolbar
3. Scan the QR code — it contains the feed URL
4. Add the URL in your podcast app:
   - **iOS:** Apple Podcasts > Library > Edit > Add a Show by URL
   - **Android:** Pocket Casts > Search > "Add by URL" / AntennaPod > + > Add podcast > RSS URL

You can also copy the feed URL shown in Settings or the status bar.

**On a different network (e.g. Tailscale):** set a custom host address in Settings so the QR code and feed URLs use the correct address for your phone to reach.

## Features

- **Source management** — YouTube channels, playlists, and one-off episode links
- **Episode discovery** — Refresh finds new episodes without downloading; you choose what to grab
- **Selective download** — Download individual episodes or a multi-selection; stop any download mid-flight
- **Podcast feed** — Standard RSS 2.0 with iTunes extensions, compatible with all podcast apps
- **Built-in server** — HTTP server hosts your feed; configurable address and port
- **Search & filters** — Filter by All, Downloaded, New, or Unplayed across all sources
- **Played/Unplayed tracking** — Mark episodes to track what you've listened to
- **Auto-fetch** — Check for new episodes every 6, 12, or 24 hours
- **Auto-start server** — Start the podcast server when the app launches
- **QR code** — One-tap setup for your phone
- **Multi-Mac sync** — Point two Macs at the same cloud episodes folder and subscriptions, episode state, and download history stay in sync automatically
- **Reveal in Finder** — Right-click any downloaded episode to open it in Finder

## Settings

Open **Recast > Settings** (Cmd+,) to configure:

- **Episodes folder** — where downloaded MP3s are stored (default: `~/Music/Recast`). Recast writes channel folders directly inside the selected folder. A hidden `.recast/` subfolder stores your subscriptions and episode list; because it lives alongside your episodes, pointing two Macs at the same cloud folder (iCloud Drive, Dropbox, etc.) keeps them in sync automatically. Feed/server files, local settings, logs, and installed tools stay under `~/Library/Application Support/Recast/`.
- **Address** — host and port for the podcast server (default: auto-detected local IP, port 8888). Set a custom host (e.g. a Tailscale IP) to reach the server from outside your local network.
- **Auto-start server** — launch the podcast server when the app opens
- **Auto-fetch interval** — check for new episodes on a schedule
- **Dependency status** — confirms `yt-dlp` and `ffmpeg` are installed
- **Reset App to Defaults** — clears saved sources, episode state, Recast-managed downloads, generated feeds, and installed tools (diagnostic logs are kept)

## Running Tests

```bash
cd Recast
xcodebuild test -scheme Recast -destination 'platform=macOS'
```

Or open in Xcode (`./setup.sh --open-xcode`) and press Cmd+U.

## Project Structure

```
Recast/               macOS SwiftUI app
├── Recast/           Source files
│   ├── RecastApp.swift       App entry point
│   ├── AppLogger.swift       File-backed diagnostics
│   ├── Models.swift          Channel & Episode data models
│   ├── Store.swift           App state, persistence, business logic
│   ├── ContentView.swift     Main split view, toolbar, QR code, status bar
│   ├── EpisodeListView.swift Episode list, multi-selection, context menus, progress
│   ├── AddChannelSheet.swift Add-source modal
│   ├── SettingsView.swift    Preferences window
│   ├── Downloader.swift      yt-dlp/ffmpeg wrapper with progress/cancellation
│   ├── FeedGenerator.swift   RSS feed builder
│   ├── PodcastServer.swift   HTTP server (NWListener)
│   └── Paths.swift           File path management
├── RecastTests/      XCTest unit tests
├── project.yml       XcodeGen config
└── setup.sh          Generates the project and builds the app bundle
setup.sh              Repo-root wrapper that leaves Recast.app at the top level
```
