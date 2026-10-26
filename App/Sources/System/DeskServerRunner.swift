import AppKit
import DeskCore
import Foundation
import os
import ShelfRunnerCore

/// Runs Desk's own tmux server (`-L runner-desk`, Desk's `tmux.conf`): every argv comes from
/// `DeskServer`, so nothing here reaches the user's tmux server or the runner's. Kills only
/// `desk-` + 8 hex names; never the server.
struct DeskServerRunner: Sendable {
    let server: DeskServer

    /// nil when tmux is not found: New session is then off.
    static func resolve(paths: Paths = .current()) -> DeskServerRunner? {
        guard let path = TmuxRunner.executable(paths: paths) else { return nil }
        return DeskServerRunner(server: DeskServer(executable: path, conf: DeskFiles.tmuxConf.path))
    }

    /// Desk's environment without inherited tmux client state. `TMUX_TMPDIR` too: the socket
    /// must be the same one Open in Terminal reaches.
    static func environment() -> [String: String] {
        var env = TmuxRunner.environment()
        env["TMUX_TMPDIR"] = nil
        return env
    }

    /// The embedded terminal's environment, computed once: Desk's environment does not change.
    static func terminalEnvironment() -> [String] { cachedTerminalEnvironment }

    private static let cachedTerminalEnvironment: [String] = {
        var env = environment()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }()

    /// The login shell agents start through.
    static var loginShell: String { DeskLaunch.shell(from: ProcessInfo.processInfo.environment["SHELL"]) }

    private func run(_ args: [String]) async -> TmuxRunner.Output {
        await TmuxRunner.run(executable: server.executable, args, environment: Self.environment())
    }

    /// Writes the conf, starts the server if needed, and applies the conf to a running one.
    func prepare() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: DeskFiles.supportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? Data(DeskServer.confText.utf8).write(to: DeskFiles.tmuxConf, options: .atomic)
        _ = await run(server.startServer())
        _ = await run(server.sourceConf())
    }

    /// Desk's sessions; empty when the server is not running; nil when tmux failed otherwise
    /// (the caller keeps what it had: a passing failure must not end the open terminal).
    func list() async -> [DeskSessionInfo]? {
        let out = await run(server.listSessions())
        if out.status == 0 { return DeskSessionInfo.parse(out.text) }
        return TmuxReply.noServer(out.text) ? [] : nil
    }

    func start(name: String, folder: String, agent: DeskAgent) async -> Bool {
        guard DeskSessionName.isValid(name) else { return false }
        await prepare()
        let size = DeskSessionSize.lastKnown ?? DeskSessionSize.fallback
        let args = server.newSession(name: name, folder: folder, agent: agent, shell: Self.loginShell,
                                     columns: size.columns, rows: size.rows)
        return await run(args).status == 0
    }

    func respawn(_ name: String) async {
        guard DeskSessionName.isValid(name) else { return }
        _ = await run(server.respawn(name))
    }

    func kill(_ name: String) async {
        guard DeskSessionName.isValid(name) else { return }
        _ = await run(server.kill(name))
    }

    func capture(_ name: String) async -> String? {
        guard DeskSessionName.isValid(name) else { return nil }
        let out = await run(server.capture(name))
        return out.status == 0 ? out.text : nil
    }

    func copyCommand(_ name: String) {
        TerminalHandoff.copy(text: server.shellLine(server.attach(name)))
    }

    /// A 0700 `.command` in Desk's own folder, opened with Terminal.
    @discardableResult
    func openInTerminal(_ name: String) -> Bool {
        guard DeskSessionName.isValid(name) else { return false }
        let fm = FileManager.default
        let file = DeskFiles.attachFile(id: name)
        do {
            try fm.createDirectory(at: DeskFiles.attachDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.removeItem(at: file)
            let script = server.commandScript(server.attach(name))
            guard fm.createFile(atPath: file.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else { return false }
        } catch {
            return false
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return false }
        NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

/// A new session's first size: the embedded terminal's last grid, so attaching does not resize
/// the window; 120x36 before any terminal was shown.
enum DeskSessionSize {
    struct Grid: Sendable, Equatable {
        let columns: Int
        let rows: Int
    }

    static let fallback = Grid(columns: 120, rows: 36)

    private static let store = OSAllocatedUnfairLock<Grid?>(initialState: nil)

    static var lastKnown: Grid? { store.withLock { $0 } }

    static func record(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        store.withLock { $0 = Grid(columns: columns, rows: rows) }
    }
}

/// The folders Desk opened sessions in, newest first: `recent.json` in Desk's own folder.
enum RecentFolders {
    static let limit = 10

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: DeskFiles.recentFile),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list.filter { $0.hasPrefix("/") }
    }

    static func adding(_ folder: String, to list: [String]) -> [String] {
        Array(([folder] + list.filter { $0 != folder }).prefix(limit))
    }

    static func save(_ list: [String]) {
        try? FileManager.default.createDirectory(at: DeskFiles.supportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: DeskFiles.recentFile, options: .atomic) }
    }
}
