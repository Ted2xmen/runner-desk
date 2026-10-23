import AppKit
import DeskCore
import Foundation
import ShelfRunnerCore

/// Desk's own folder and what it reads of the runner's (read only: Desk never writes there,
/// Desk never writes there).
enum DeskFiles {
    /// `~/Library/Application Support/Runner Desk/`.
    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Runner Desk", isDirectory: true)
    }

    /// Open in Terminal's scripts: never the runner's `attach` folder, which it sweeps.
    static var attachDir: URL { supportDir.appendingPathComponent("attach", isDirectory: true) }

    static func attachFile(id: String) -> URL { attachDir.appendingPathComponent("\(id).command") }

    /// The runner's `heartbeat.json`.
    static func heartbeat(_ paths: Paths) -> URL { paths.stateDir.appendingPathComponent("heartbeat.json") }

    /// Removes the scripts of jobs no longer live; at launch (`keep` empty) all of them.
    static func sweepAttachScripts(keep: Set<String>) {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: attachDir, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "command" && !keep.contains(url.deletingPathExtension().lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }
}

/// "Open in Terminal" and "Copy tmux command": both open a fresh grouped view
/// `term-<id>-<hex>`, the same argv the embedded terminal runs, so the user's other clients of
/// `shelf-*` keep their window.
enum TerminalHandoff {
    static func shellLine(_ tmux: TmuxCommands, target: TmuxTarget) -> String {
        var g = SystemRandomNumberGenerator()
        let name = ViewName.terminal(target.window, suffix: ViewName.suffix(using: &g))
        return tmux.shellLine(tmux.openView(target, name: name, statusBar: true))
    }

    static func copy(_ tmux: TmuxCommands, target: TmuxTarget) {
        copy(text: shellLine(tmux, target: target))
    }

    static func copy(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes a 0700 `.command` (rewritten on every click) and opens it with Terminal. Not deleted
    /// right away: Terminal reads it later; the sweep removes it when the job ends.
    @discardableResult
    static func openInTerminal(_ tmux: TmuxCommands, target: TmuxTarget) -> Bool {
        var g = SystemRandomNumberGenerator()
        let name = ViewName.terminal(target.window, suffix: ViewName.suffix(using: &g))
        let script = tmux.commandScript(tmux.openView(target, name: name, statusBar: true))
        let fm = FileManager.default
        let file = DeskFiles.attachFile(id: target.window)
        do {
            try fm.createDirectory(at: DeskFiles.attachDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.removeItem(at: file)
            guard fm.createFile(atPath: file.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else { return false }
        } catch {
            return false
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return false }
        NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

/// An ended job's log: read off the main thread, the file's last `FinishedLog.maxBytes`.
enum LogReader {
    static func load(id: String, attended: Bool, paths: Paths = .current()) async -> FinishedLog.Lines? {
        await Task.detached(priority: .userInitiated) {
            for source in FinishedLog.sources(attended: attended) {
                let url = source == .screen ? paths.screenFile(id: id) : paths.logFile(id: id)
                guard let (text, truncated) = tail(url) else { continue }
                return FinishedLog.lines(text, source: source, truncated: truncated)
            }
            return nil
        }.value
    }

    private static func tail(_ url: URL) -> (String, Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(FinishedLog.maxBytes) ? size - UInt64(FinishedLog.maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        return (String(decoding: data, as: UTF8.self), start > 0)
    }
}
