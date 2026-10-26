import AppKit
import SwiftTerm
import SwiftUI

/// SwiftTerm's `LocalProcessTerminalView` running the tmux client of one grouped view session
/// in a pty. The command is an argv array, never a shell string. The
/// view stays dumb: the model decides the argv and reacts to `onExit`; tearing the view down
/// only ends the client (the model closes the session itself, with the group-size check).
///
/// The GeometryReader hands the laid-out size to the terminal before its process starts, so
/// the pty opens at its real grid: one size for tmux and the agent, no resize on first layout.
struct TerminalPane: View {
    let executable: String
    let args: [String]
    /// The client's environment; Desk sessions also drop `TMUX_TMPDIR`.
    var environment: [String] = TerminalPane.defaultEnvironment
    let onExit: @MainActor () -> Void

    var body: some View {
        GeometryReader { geo in
            TerminalSurface(initialSize: geo.size, executable: executable, args: args,
                            environment: environment, onExit: onExit)
        }
    }

    /// `environment()` computed once: the process environment does not change while Desk runs.
    static let defaultEnvironment: [String] = environment()

    /// Desk's environment without `TMUX`, as a 256-color UTF-8 terminal.
    static func environment() -> [String] {
        var env = TmuxRunner.environment()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }
}

private struct TerminalSurface: NSViewRepresentable {
    /// The size at creation only; later sizes reach the view through its frame.
    let initialSize: CGSize
    let executable: String
    let args: [String]
    let environment: [String]
    let onExit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let font = NSFont.monospacedSystemFont(ofSize: Theme.Fonts.terminalSize, weight: .regular)
        let hasSize = initialSize.width > 0 && initialSize.height > 0
        // A zero frame takes its grid from the options: the last size seen beats 80x25.
        var options = TerminalOptions.default
        if !hasSize, let last = DeskSessionSize.lastKnown {
            options.cols = last.columns
            options.rows = last.rows
        }
        let frame = CGRect(origin: .zero, size: hasSize ? initialSize : .zero)
        let view = LocalProcessTerminalView(frame: frame, font: font, options: options)
        view.processDelegate = context.coordinator
        applyColors(view, context: context)
        view.optionAsMetaKey = true
        view.setAccessibilityLabel("Terminal")
        if hasSize {
            let grid = view.terminalDimensions
            DeskSessionSize.record(columns: grid.cols, rows: grid.rows)
        }
        view.startProcess(executable: executable, args: args, environment: environment, execName: "tmux")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) { applyColors(view, context: context) }

    /// The terminal follows the app's theme (light theme, light terminal). Read from the app's
    /// effective appearance, which the Theme setting forces: the SwiftUI color scheme can lag it.
    /// The color scheme is still read so SwiftUI calls `updateNSView` when the theme changes.
    private func applyColors(_ view: LocalProcessTerminalView, context: Context) {
        _ = context.environment.colorScheme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard context.coordinator.isDark != dark else { return }
        context.coordinator.isDark = dark
        let colors = Theme.terminalColors(dark: dark)
        view.nativeBackgroundColor = colors.background
        view.nativeForegroundColor = colors.foreground
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        view.terminate()
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: @MainActor () -> Void
        var isDismantled = false
        var isDark: Bool?

        init(onExit: @escaping @MainActor () -> Void) { self.onExit = onExit }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            DeskSessionSize.record(columns: newCols, rows: newRows)
        }
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard !isDismantled else { return }
            onExit()
        }
    }
}
