#!/usr/bin/env python3
"""
Cosmic AI Podcast Tool

Downloads talks from the NSF-Simons Cosmic AI YouTube channel and generates
a podcast RSS feed you can subscribe to in any podcast app.

Usage:
    python cosmic_podcast.py                  # Download new talks, generate feed
    python cosmic_podcast.py --max 5          # Only grab the 5 latest talks
    python cosmic_podcast.py --serve          # Start a local podcast server
    python cosmic_podcast.py --serve --port 8080  # Serve on a custom port

Requirements:
    pip install yt-dlp

System dependencies:
    ffmpeg (for audio extraction)
"""

import argparse
import json
import hashlib
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from xml.sax.saxutils import escape

CHANNEL_URL = "https://www.youtube.com/@NSF-SimonsCosmicAI/videos"
DEFAULT_OUTPUT_DIR = Path(__file__).parent / "output"
EPISODES_DIR_NAME = "episodes"
FEED_FILENAME = "feed.xml"
STATE_FILENAME = "state.json"

PODCAST_TITLE = "Cosmic AI Talks"
PODCAST_DESCRIPTION = (
    "Talks from the NSF-Simons National Institute for Theory and Mathematics "
    "in Particle Physics (Cosmic AI), automatically extracted from their "
    "YouTube channel."
)
PODCAST_LINK = "https://cosmicai.org"
PODCAST_LANGUAGE = "en"


def check_dependencies():
    """Verify yt-dlp and ffmpeg are available."""
    for cmd in ("yt-dlp", "ffmpeg"):
        try:
            subprocess.run(
                [cmd, "--version"],
                capture_output=True,
                check=True,
            )
        except FileNotFoundError:
            print(f"Error: '{cmd}' is not installed. Please install it first.")
            sys.exit(1)


def load_state(output_dir: Path) -> dict:
    """Load the set of already-downloaded video IDs."""
    state_file = output_dir / STATE_FILENAME
    if state_file.exists():
        return json.loads(state_file.read_text())
    return {"downloaded": []}


def save_state(output_dir: Path, state: dict):
    state_file = output_dir / STATE_FILENAME
    state_file.write_text(json.dumps(state, indent=2))


def fetch_channel_videos(max_videos: int) -> list[dict]:
    """Use yt-dlp to list videos from the channel."""
    print(f"Fetching up to {max_videos} videos from channel...")
    cmd = [
        "yt-dlp",
        "--flat-playlist",
        "--no-warnings",
        "--print", "%(id)s\t%(title)s\t%(upload_date>%Y-%m-%d)s\t%(duration)s",
        "--playlist-end", str(max_videos),
        CHANNEL_URL,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error fetching channel listing:\n{result.stderr}")
        sys.exit(1)

    videos = []
    for line in result.stdout.strip().splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        video_id, title, upload_date, duration = parts[0], parts[1], parts[2], parts[3]
        try:
            duration_secs = int(duration)
        except (ValueError, TypeError):
            duration_secs = 0
        videos.append({
            "id": video_id,
            "title": title,
            "upload_date": upload_date,
            "duration": duration_secs,
        })
    return videos


def download_audio(video_id: str, episodes_dir: Path) -> Path | None:
    """Download audio for a single video as MP3."""
    output_template = str(episodes_dir / f"{video_id}.%(ext)s")
    mp3_path = episodes_dir / f"{video_id}.mp3"

    if mp3_path.exists():
        print(f"  Already downloaded: {mp3_path.name}")
        return mp3_path

    print(f"  Downloading audio for {video_id}...")
    cmd = [
        "yt-dlp",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "3",  # good balance of quality and size
        "--output", output_template,
        "--no-playlist",
        "--no-warnings",
        f"https://www.youtube.com/watch?v={video_id}",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Failed to download {video_id}: {result.stderr[:200]}")
        return None

    if mp3_path.exists():
        return mp3_path
    # yt-dlp may have kept the original extension
    for f in episodes_dir.glob(f"{video_id}.*"):
        if f.suffix != ".mp3":
            f.unlink()
    if not mp3_path.exists():
        print(f"  Warning: MP3 not found after download for {video_id}")
        return None
    return mp3_path


def file_size(path: Path) -> int:
    return path.stat().st_size if path.exists() else 0


def format_duration(seconds: int) -> str:
    """Format seconds as HH:MM:SS."""
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


def build_episode_xml(video: dict, mp3_path: Path, base_url: str) -> str:
    """Build an RSS <item> for one episode."""
    title = escape(video["title"])
    video_id = video["id"]
    pub_date = datetime.strptime(video["upload_date"], "%Y-%m-%d").replace(
        tzinfo=timezone.utc
    )
    rfc2822_date = pub_date.strftime("%a, %d %b %Y %H:%M:%S +0000")
    size = file_size(mp3_path)
    duration = format_duration(video["duration"])
    episode_url = f"{base_url}/{EPISODES_DIR_NAME}/{video_id}.mp3"
    guid = hashlib.sha256(video_id.encode()).hexdigest()[:16]
    yt_link = f"https://www.youtube.com/watch?v={video_id}"

    return f"""    <item>
      <title>{title}</title>
      <description>{escape(f'Talk from Cosmic AI. Watch the video: {yt_link}')}</description>
      <enclosure url="{escape(episode_url)}" length="{size}" type="audio/mpeg"/>
      <guid isPermaLink="false">{guid}</guid>
      <pubDate>{rfc2822_date}</pubDate>
      <itunes:duration>{duration}</itunes:duration>
      <link>{escape(yt_link)}</link>
    </item>"""


def generate_feed(output_dir: Path, videos: list[dict], base_url: str):
    """Generate the podcast RSS feed XML."""
    episodes_dir = output_dir / EPISODES_DIR_NAME
    now = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    items = []
    for video in videos:
        mp3_path = episodes_dir / f"{video['id']}.mp3"
        if mp3_path.exists():
            items.append(build_episode_xml(video, mp3_path, base_url))

    feed = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>{escape(PODCAST_TITLE)}</title>
    <description>{escape(PODCAST_DESCRIPTION)}</description>
    <link>{escape(PODCAST_LINK)}</link>
    <language>{PODCAST_LANGUAGE}</language>
    <lastBuildDate>{now}</lastBuildDate>
    <atom:link href="{escape(base_url)}/{FEED_FILENAME}" rel="self" type="application/rss+xml"/>
    <itunes:author>Cosmic AI</itunes:author>
    <itunes:category text="Science"/>
{chr(10).join(items)}
  </channel>
</rss>
"""
    feed_path = output_dir / FEED_FILENAME
    feed_path.write_text(feed)
    print(f"Feed written to {feed_path}")


def serve(output_dir: Path, port: int):
    """Serve the output directory over HTTP so podcast apps can subscribe."""
    os.chdir(output_dir)

    class Handler(SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            print(f"[server] {args[0]}")

    print(f"\nServing podcast at:\n  http://localhost:{port}/{FEED_FILENAME}")
    print(f"\nAdd this URL to your podcast app to subscribe.")
    print("Press Ctrl+C to stop.\n")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


def main():
    parser = argparse.ArgumentParser(
        description="Download Cosmic AI talks as a podcast feed."
    )
    parser.add_argument(
        "--max", type=int, default=20,
        help="Maximum number of recent videos to fetch (default: 20)",
    )
    parser.add_argument(
        "--output", type=str, default=str(DEFAULT_OUTPUT_DIR),
        help="Output directory for episodes and feed",
    )
    parser.add_argument(
        "--base-url", type=str, default=None,
        help="Base URL for the podcast feed (default: http://localhost:<port>)",
    )
    parser.add_argument(
        "--serve", action="store_true",
        help="Start an HTTP server to host the podcast feed",
    )
    parser.add_argument(
        "--port", type=int, default=8888,
        help="Port for the HTTP server (default: 8888)",
    )
    args = parser.parse_args()

    check_dependencies()

    output_dir = Path(args.output).resolve()
    episodes_dir = output_dir / EPISODES_DIR_NAME
    episodes_dir.mkdir(parents=True, exist_ok=True)

    base_url = args.base_url or f"http://localhost:{args.port}"

    # Fetch channel listing
    videos = fetch_channel_videos(args.max)
    if not videos:
        print("No videos found on the channel.")
        sys.exit(1)

    print(f"Found {len(videos)} videos.\n")

    # Load state and download new episodes
    state = load_state(output_dir)
    downloaded_ids = set(state["downloaded"])
    new_count = 0

    for video in videos:
        vid = video["id"]
        if vid in downloaded_ids:
            print(f"  Skipping (already have): {video['title'][:60]}")
            continue
        mp3 = download_audio(vid, episodes_dir)
        if mp3:
            downloaded_ids.add(vid)
            new_count += 1

    state["downloaded"] = list(downloaded_ids)
    save_state(output_dir, state)
    print(f"\nDownloaded {new_count} new episode(s).")

    # Build feed with all episodes we have on disk
    generate_feed(output_dir, videos, base_url)

    if args.serve:
        serve(output_dir, args.port)
    else:
        print(f"\nTo subscribe, serve the feed with:")
        print(f"  python {__file__} --serve")
        print(f"Then add http://localhost:{args.port}/{FEED_FILENAME} to your podcast app.")


if __name__ == "__main__":
    main()
