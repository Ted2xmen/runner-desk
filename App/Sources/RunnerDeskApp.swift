import AppKit
import SwiftUI

@main
struct RunnerDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Runner Desk", id: "main") {
            ShellView(model: AppModel.shared)
                .frame(minWidth: Theme.Metrics.minWindowWidth, minHeight: Theme.Metrics.minWindowHeight)
                .enableFolderSheet(AppModel.shared, origin: .link)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Theme.Metrics.defaultWindowWidth, height: Theme.Metrics.defaultWindowHeight)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session\u{2026}") { AppModel.shared.showsNewSession = true }
                    .keyboardShortcut("n")
                    .disabled(AppModel.shared.deskServer == nil)
            }
        }

        Settings { SettingsView(model: AppModel.shared) }
    }
}

/// URLs (`runnerdesk://job/<id>`, `runnerdesk://enable?path=…`) and the app's life. One window: closing it quits Desk, and
/// quitting closes every tmux view Desk opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The saved light or dark choice lands before the first window draws.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Appearance.applyStored() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            #if DEBUG
            DebugSnapshot.startIfAsked()
            #endif
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.forEach(AppModel.shared.open) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.becameActive() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.closeAllViewsNow() }
    }
}
