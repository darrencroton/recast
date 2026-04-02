import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder resolves the bundle icon correctly, but local runs can still show the
        // generic Dock tile. Setting the bundled icns explicitly keeps the running app
        // aligned with the bundle metadata.
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct RecastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 920, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
