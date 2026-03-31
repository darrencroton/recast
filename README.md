# Cosmic AI Podcast Tool

Automatically downloads talks from the [NSF-Simons Cosmic AI](https://cosmicai.org) YouTube channel and generates a podcast RSS feed you can subscribe to on your phone.

## Setup

**Requirements:** Python 3.10+, ffmpeg

```bash
# Install Python dependency
pip install -r requirements.txt

# Install ffmpeg (if not already installed)
# macOS:
brew install ffmpeg
# Ubuntu/Debian:
sudo apt install ffmpeg
# Windows:
winget install ffmpeg
```

## Usage

```bash
# Download latest talks and generate the podcast feed
python cosmic_podcast.py

# Only grab the 5 most recent talks
python cosmic_podcast.py --max 5

# Download and immediately start serving the feed
python cosmic_podcast.py --serve

# Use a custom port
python cosmic_podcast.py --serve --port 9000
```

## Subscribe on Your Phone

1. Run with `--serve` to start the podcast server
2. Find your computer's local IP (e.g. `192.168.1.100`)
3. Add `http://192.168.1.100:8888/feed.xml` to your podcast app:
   - **iOS:** Apple Podcasts > Library > Edit > Add a Show by URL
   - **Android:** Pocket Casts > Search > "Add by URL" / AntennaPod > + > Add podcast > RSS URL
4. Episodes will appear as a regular podcast

## Hosting Publicly

To make the feed available outside your local network, you can:

- **ngrok:** `ngrok http 8888` then use the generated URL as `--base-url`
- **Cloud server:** Copy the `output/` folder to a web server and set `--base-url` to its public URL
- **Tailscale:** Access via your Tailscale IP on your phone

```bash
# Example with a public base URL
python cosmic_podcast.py --base-url https://my-server.example.com/podcast
```

## How It Works

1. Uses `yt-dlp` to list recent videos from the Cosmic AI YouTube channel
2. Downloads audio as MP3 (skipping already-downloaded episodes)
3. Generates a standard podcast RSS feed (`feed.xml`)
4. Optionally serves the feed and audio files over HTTP

Downloaded episodes and feed are stored in the `output/` directory.

## Updating

Run the script again to check for new talks. It tracks what's already been downloaded and only fetches new episodes.

```bash
# Cron job to check for new talks daily at 6 AM
0 6 * * * cd /path/to/podcast && python cosmic_podcast.py
```
