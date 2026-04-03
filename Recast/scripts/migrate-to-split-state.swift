#!/usr/bin/env swift
//
// migrate-to-split-state.swift
//
// Run this ONCE before launching the new version of Recast for the first time.
// It splits the old combined state.json into:
//   - Local state  (machine-specific settings) → stays in Application Support/Recast/state.json
//   - Shared state (channels + episodes)       → <episodesDirectory>/.recast/shared-state.json
//
// Usage:
//   swift Recast/scripts/migrate-to-split-state.swift
//

import Foundation

let fm = FileManager.default

// MARK: - Locate old state file

let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("Recast")
let stateFileURL = appSupportURL.appendingPathComponent("state.json")

guard fm.fileExists(atPath: stateFileURL.path) else {
    print("No state file found at \(stateFileURL.path) — nothing to migrate.")
    exit(0)
}

guard
    let data = try? Data(contentsOf: stateFileURL),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
else {
    print("ERROR: Could not read \(stateFileURL.path) — aborting.")
    exit(1)
}

// MARK: - Determine episodes directory

let defaultEpisodesDir = (fm.urls(for: .musicDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser)
    .appendingPathComponent("Recast")
let episodesDirPath = (json["episodesDirectory"] as? String) ?? defaultEpisodesDir.path
let episodesDirURL = URL(fileURLWithPath: episodesDirPath)

// MARK: - Build local state (machine-specific, stays in App Support)

var localState: [String: Any] = ["serverPort": json["serverPort"] ?? 8888]
localState["episodesDirectory"] = episodesDirPath
if let v = json["serverHost"] as? String       { localState["serverHost"] = v }
if let v = json["autoFetchInterval"] as? Int   { localState["autoFetchInterval"] = v }
if let v = json["autoStartServer"] as? Bool    { localState["autoStartServer"] = v }

// MARK: - Build shared state (channels + episodes, goes into episodes directory for cloud sync)

let sharedState: [String: Any] = [
    "channels": json["channels"] ?? [],
    "episodes": json["episodes"] ?? [],
]

// MARK: - Write both state files
//
// Shared state is written first. If that step fails (e.g. the episodes directory is
// unavailable), the script exits before touching state.json, leaving the original
// combined file intact so no data is lost.

func writeJSON(_ dict: [String: Any], to url: URL, label: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
        print("ERROR: Could not encode \(label) — aborting.")
        exit(1)
    }
    do {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        print("Written \(label) → \(url.path)")
    } catch {
        print("ERROR: Could not write \(label): \(error.localizedDescription) — aborting.")
        exit(1)
    }
}

let syncDirURL = episodesDirURL.appendingPathComponent(".recast")
let sharedStateFileURL = syncDirURL.appendingPathComponent("shared-state.json")
writeJSON(sharedState, to: sharedStateFileURL, label: "shared state")

writeJSON(localState, to: stateFileURL, label: "local state")

// MARK: - Summary

let channelCount = (sharedState["channels"] as? [[String: Any]])?.count ?? 0
let episodeCount = (sharedState["episodes"] as? [[String: Any]])?.count ?? 0
print("""
Migration complete.
  \(channelCount) channel(s) and \(episodeCount) episode(s) moved to shared state.
  Episodes directory: \(episodesDirPath)
Open the new version of Recast to continue.
""")
