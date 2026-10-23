import AppKit
import SwiftTerm
import SwiftUI

/// SwiftTerm's `LocalProcessTerminalView` running the tmux client of one grouped view session
/// in a pty. The command is an argv array, never a shell string. The
/// view stays dumb: the model decides the argv and reacts to `onExit`; tearing the view down
/// only ends the client (the model closes the session itself, with the group-size check).
struct TerminalPane: NSViewRepresentable {
    let executable: String
    let args: [String]
    let onExit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: Theme.Fonts.terminalSize, weight: .regular)
        applyColors(view, context: context)
        view.optionAsMetaKey = true
        view.setAccessibilityLabel("Terminal")
        view.startProcess(executable: executable, args: args, environment: Self.environment(), execName: "tmux")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) { applyColors(view, context: context) }

    /// The terminal follows the app's theme (light theme, light terminal).
    private func applyColors(_ view: LocalProcessTerminalView, context: Context) {
        let dark = context.environment.colorScheme == .dark
        guard context.coordinator.isDark != dark else { return }
        context.coordinator.isDark = dark
        let colors = Theme.terminalColors(dark: dark)
        view.nativeBackgroundColor = colors.background
        view.nativeForegroundColor = colors.foreground
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        view.terminate()
    }

    /// Desk's environment without `TMUX`, as a 256-color UTF-8 terminal.
    static func environment() -> [String] {
        var env = TmuxRunner.environment()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: @MainActor () -> Void
        var isDismantled = false
        var isDark: Bool?

        init(onExit: @escaping @MainActor () -> Void) { self.onExit = onExit }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard !isDismantled else { return }
            onExit()
        }
    }
}
