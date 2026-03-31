# Recast

A native macOS app that turns YouTube channels into a podcast feed. Add channels, fetch new talks, and subscribe in any podcast app on your phone.

## Quick Start

```bash
cd Recast
./setup.sh
```

This generates the Xcode project and opens it. Press **Cmd+R** to build and run.

**Requirements:** macOS 14+, Xcode 15+. The app automatically downloads `yt-dlp` and `ffmpeg` on first launch — no terminal setup needed.

## How It Works

1. **Add channels** — Press `+` and paste a YouTube channel or playlist URL
2. **Fetch episodes** — Select channels and press the Fetch button to discover and download new talks as MP3
3. **Subscribe** — Start the built-in podcast server and add the feed URL to your podcast app

The app generates a standard RSS podcast feed served at `http://localhost:8888/feed.xml`.

## Subscribe on Your Phone

1. Click the server toggle in the toolbar to start serving
2. Find your Mac's local IP (System Settings > Wi-Fi > Details > IP Address)
3. Add `http://<your-ip>:8888/feed.xml` to your podcast app:
   - **iOS:** Apple Podcasts > Library > Edit > Add a Show by URL
   - **Android:** Pocket Casts > Search > "Add by URL" / AntennaPod > + > Add podcast > RSS URL

## Settings

Open **Recast > Settings** (Cmd+,) to configure:
- **Episodes folder** — where MP3 files and the feed are stored (default: `~/Music/Recast`)
- **Server port** — change the HTTP server port

## Running Tests

```bash
cd Recast
./setup.sh          # Regenerate project if needed
# Then Cmd+U in Xcode
```

The test suite has 50 unit tests covering episode models, RSS feed generation, XML escaping, and store logic. See `RecastTests/` for details.

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
│   ├── RecastApp.swift
│   ├── Models.swift
│   ├── Store.swift
│   ├── ContentView.swift
│   ├── EpisodeListView.swift
│   ├── AddChannelSheet.swift
│   ├── SettingsView.swift
│   ├── Downloader.swift
│   ├── FeedGenerator.swift
│   └── PodcastServer.swift
├── RecastTests/      XCTest unit tests
├── project.yml       XcodeGen config
└── setup.sh          Generates Xcode project
cosmic_podcast.py     Standalone CLI tool
```
