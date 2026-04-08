import AppKit
import SwiftUI

private let mainWindowID = "main-window"

private enum MenuBarIcon {
    static let image: NSImage = {
        if let image = NSImage(named: "AppIcon") {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        if let fallback = NSApplication.shared.applicationIconImage {
            fallback.size = NSSize(width: 18, height: 18)
            return fallback
        }

        return NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Recast") ?? NSImage()
    }()
}

@MainActor
struct AppLifecycleRuntime {
    var activateApp: () -> Void
    var terminate: () -> Void

    static let live = AppLifecycleRuntime(
        activateApp: {
            NSApp.activate(ignoringOtherApps: true)
        },
        terminate: {
            NSApp.terminate(nil)
        }
    )
}

@MainActor
final class AppLifecycleController {
    private let launchHandler: () -> Void
    private let runtime: AppLifecycleRuntime
    private var hasCompletedInitialLaunch = false

    init(launchHandler: @escaping () -> Void) {
        self.launchHandler = launchHandler
        self.runtime = .live
    }

    init(launchHandler: @escaping () -> Void, runtime: AppLifecycleRuntime) {
        self.launchHandler = launchHandler
        self.runtime = runtime
    }

    func handleMainWindowPresentation() {
        guard !hasCompletedInitialLaunch else { return }
        hasCompletedInitialLaunch = true
        launchHandler()
        runtime.activateApp()
    }

    func openRecast(openWindow: () -> Void) {
        openWindow()
        runtime.activateApp()
    }

    func quitRecast() {
        runtime.terminate()
    }
}

private struct MainWindowRootView: View {
    let store: AppStore
    let lifecycleController: AppLifecycleController

    var body: some View {
        ContentView()
            .environment(store)
            .frame(minWidth: 700, minHeight: 450)
            .onAppear {
                lifecycleController.handleMainWindowPresentation()
            }
    }
}

private struct RecastMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    let lifecycleController: AppLifecycleController

    var body: some View {
        Button("Open Recast") {
            lifecycleController.openRecast {
                openWindow(id: mainWindowID)
            }
        }

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Recast") {
            lifecycleController.quitRecast()
        }
    }
}

@main
struct RecastApp: App {
    @State private var store: AppStore
    @State private var lifecycleController: AppLifecycleController

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _lifecycleController = State(initialValue: AppLifecycleController(launchHandler: store.onLaunch))
    }

    var body: some Scene {
        Window("Recast", id: mainWindowID) {
            MainWindowRootView(store: store, lifecycleController: lifecycleController)
        }
        .defaultSize(width: 920, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra {
            RecastMenuBarMenu(lifecycleController: lifecycleController)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.original)
        }
        .menuBarExtraStyle(.menu)
    }
}
