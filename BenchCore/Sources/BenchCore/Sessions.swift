import Foundation
import ShelfBridgeCore

/// Bench's own sessions: attended agent sessions the user starts in a folder. They live on
/// Bench's own tmux server (`-L shelf-bench`, Bench's own `tmux.conf`), one single-window tmux
/// session each, so they survive Bench quitting. tmux stays invisible: no status line, no prefix
/// key; Bench is the only control. Bridge never sees this server.

/// The agent a session runs.
public enum BenchAgent: String, CaseIterable, Sendable, Hashable {
    case claude
    case codex
    case shell

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .shell: "Shell"
        }
    }
}

/// The mark a row shows for its agent: Claude's, Codex's, a terminal for a shell, or a plain
/// dot for an agent Bench does not know.
public enum AgentMark: Sendable, Hashable {
    case claude
    case codex
    case shell
    case other

    public init(raw: String) {
        switch raw {
        case "claude": self = .claude
        case "codex": self = .codex
        case "shell": self = .shell
        default: self = .other
        }
    }

    public init(_ agent: BenchAgent) { self.init(raw: agent.rawValue) }
}

/// `bench-` and 8 lower-case hex digits: the only names Bench makes, reads or kills on its server.
public enum BenchSessionName {
    public static let prefix = "bench-"

    public static func isValid(_ s: String) -> Bool {
        guard s.hasPrefix(prefix) else { return false }
        let hex = s.dropFirst(prefix.count)
        return hex.count == 8 && hex.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    public static func make<G: RandomNumberGenerator>(using g: inout G) -> String {
        prefix + String(format: "%08x", UInt32.random(in: 0...UInt32.max, using: &g))
    }
}

/// How an agent is started: through the user's login shell, so a Finder-launched Bench (whose
/// PATH is only the system's) finds `claude` and `codex` where the user's shell finds them. The
/// script is a constant (`exec "$@"`); the agent is a positional argument, never shell text.
public enum BenchLaunch {
    /// Shells that understand `-l -c 'exec "$@"'`; others (fish, nu) fall back to zsh.
    static let posixShells: Set<String> = ["zsh", "bash", "sh", "ksh"]
    public static let fallbackShell = "/bin/zsh"
    /// Exit code of a command the shell could not find.
    public static let notFound: Int32 = 127

    public static func shell(from environmentShell: String?) -> String {
        guard let s = environmentShell, s.hasPrefix("/"), posixShells.contains((s as NSString).lastPathComponent) else {
            return fallbackShell
        }
        return s
    }

    /// The pane's argv. Always two or more words: tmux runs a single word through `sh -c`.
    /// No permission-skip flag, no unattended mode, on any path.
    public static func argv(_ agent: BenchAgent, shell: String) -> [String] {
        switch agent {
        case .claude: [shell, "-l", "-c", "exec \"$@\"", "bench", "claude"]
        case .codex: [shell, "-l", "-c", "exec \"$@\"", "bench", "codex"]
        case .shell: [shell, "-l"]
        }
    }
}

/// Bench's tmux server: every argv starts with `-L shelf-bench -f <conf>`, so nothing here ever
/// reaches the user's own tmux server or Bridge's. `=` on every target.
public struct BenchServer: Equatable, Sendable {
    public static let socket = "shelf-bench"
    /// The `list-sessions` fields, tab-separated, in `BenchSessionInfo.parse`'s order.
    static let listFormat = ["#{session_name}", "#{@bench_agent}", "#{@bench_folder}", "#{session_created}", "#{pane_dead}",
                             "#{pane_dead_status}", "#{pane_current_command}", "#{window_activity}", "#{session_attached}"]
        .joined(separator: "\t")

    /// The absolute tmux path Bench runs.
    public let executable: String
    /// Bench's own `tmux.conf`.
    public let conf: String

    public init(executable: String, conf: String) {
        self.executable = executable
        self.conf = conf
    }

    public var base: [String] { ["-L", Self.socket, "-f", conf] }

    public func startServer() -> [String] { base + ["start-server"] }
    /// `-f` is read only when the server starts: a running server gets the conf again this way.
    public func sourceConf() -> [String] { base + ["source-file", conf] }

    public func newSession(name: String, folder: String, agent: BenchAgent, shell: String, columns: Int, rows: Int) -> [String] {
        let pane = "=\(name):"
        return base + ["new-session", "-d", "-s", name, "-c", folder, "-x", String(columns), "-y", String(rows), "--"]
            + BenchLaunch.argv(agent, shell: shell)
            + [";", "set-option", "-t", pane, "@bench_agent", agent.rawValue,
               ";", "set-option", "-t", pane, "@bench_folder", folder]
    }

    public func listSessions() -> [String] { base + ["list-sessions", "-F", Self.listFormat] }

    /// The embedded terminal's client (and Open in Terminal's).
    public func attach(_ name: String) -> [String] { base + ["attach-session", "-t", "=" + name] }

    /// Restart a session whose agent exited: the same argv in the same folder.
    public func respawn(_ name: String) -> [String] { base + ["respawn-pane", "-k", "-t", "=\(name):"] }

    public func kill(_ name: String) -> [String] { base + ["kill-session", "-t", "=" + name] }

    /// The last screen and a few history lines, joined, plain.
    public func capture(_ name: String) -> [String] { base + ["capture-pane", "-p", "-J", "-S", "-12", "-t", "=\(name):"] }

    /// Copy tmux command: the attach as one shell line.
    public func shellLine(_ args: [String]) -> String {
        (["tmux"] + args.map(TmuxCommands.quoted)).joined(separator: " ")
    }

    /// Open in Terminal's `.command`: no inherited tmux client state, then `exec` the absolute
    /// tmux path. Closing the Terminal window is how one leaves: there is no prefix key.
    public func commandScript(_ args: [String]) -> String {
        "#!/bin/sh\n# Shelf Bench: Open in Terminal. Close this window to leave; the session goes on.\nunset TMUX TMUX_PANE TMUX_TMPDIR\nexec "
            + ([TmuxCommands.quoted(executable)] + args.map(TmuxCommands.quoted)).joined(separator: " ") + "\n"
    }

    /// Bench's `tmux.conf`, written on every launch. Safe to source again (`unbind -q`, an
    /// indexed `terminal-features`). The root key table keeps tmux's mouse bindings (wheel
    /// scroll, drag to select); only the right-click menus go, they would show tmux.
    public static let confText = """
        # Shelf Bench's own tmux server. Shelf Bench rewrites this file on every launch.
        set -g @shelf_bench 1
        set -g status off
        set -g prefix None
        set -g prefix2 None
        unbind -q -a -T prefix
        unbind -q -n MouseDown3Pane
        unbind -q -n M-MouseDown3Pane
        unbind -q -n MouseDown3Status
        unbind -q -n M-MouseDown3Status
        unbind -q -n MouseDown3StatusLeft
        unbind -q -n M-MouseDown3StatusLeft
        set -g exit-empty off
        set -g remain-on-exit on
        set -g history-limit 50000
        set -g default-terminal tmux-256color
        set -g terminal-features[90] 'xterm*:RGB:extkeys:clipboard'
        set -g escape-time 0
        set -g focus-events on
        set -g extended-keys on
        set -g set-clipboard on
        set -g mouse on
        set -g copy-command pbcopy

        """
}

/// One Bench session as the server reports it.
public struct BenchSessionInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let agent: BenchAgent
    public let folder: String
    public let created: Date
    /// The agent (the pane's process) exited; the pane stays (`remain-on-exit`).
    public let isDead: Bool
    public let exitCode: Int32?
    /// The pane's foreground command ("claude", "node", "zsh"); meaningless once dead.
    public let currentCommand: String
    /// Last output or keystroke.
    public let activity: Date
    public let attachedClients: Int

    public init(id: String, agent: BenchAgent, folder: String, created: Date, isDead: Bool, exitCode: Int32?,
                currentCommand: String, activity: Date, attachedClients: Int) {
        self.id = id
        self.agent = agent
        self.folder = folder
        self.created = created
        self.isDead = isDead
        self.exitCode = exitCode
        self.currentCommand = currentCommand
        self.activity = activity
        self.attachedClients = attachedClients
    }

    /// `list-sessions` output. Lines whose name is not Bench's, or that lack Bench's options, are
    /// skipped (someone else's session on this socket is never shown, never killed).
    public static func parse(_ output: String) -> [BenchSessionInfo] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 9, BenchSessionName.isValid(f[0]), let agent = BenchAgent(rawValue: f[1]), f[2].hasPrefix("/"),
                  let created = TimeInterval(f[3]), let activity = TimeInterval(f[7]) else { return nil }
            let dead = f[4] == "1"
            return BenchSessionInfo(id: f[0], agent: agent, folder: f[2], created: Date(timeIntervalSince1970: created),
                                   isDead: dead, exitCode: dead ? Int32(f[5]) : nil, currentCommand: f[6],
                                   activity: Date(timeIntervalSince1970: activity), attachedClients: Int(f[8]) ?? 0)
        }
    }

    /// Something other than an idle shell runs: End session asks first.
    public func endNeedsConfirmation(shell: String) -> Bool {
        guard !isDead else { return false }
        let shells = BenchLaunch.posixShells.union(["fish", "nu", (shell as NSString).lastPathComponent])
        return !shells.contains(currentCommand.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
    }
}

/// When to look at a session's screen for a question, and what counts as one.
public enum SessionAsking {
    /// Bridge's rule needs 60 s of quiet; looking earlier is wasted work.
    public static let quiet: TimeInterval = 60

    /// Live, quiet long enough, and changed since the last look (nil: never looked).
    public static func shouldCapture(_ s: BenchSessionInfo, lastLookedAt: Date?, now: Date) -> Bool {
        guard !s.isDead, now.timeIntervalSince(s.activity) >= quiet else { return false }
        return lastLookedAt.map { s.activity > $0 } ?? true
    }

    /// Bridge's own approval-prompt rule, on the last 12 lines.
    public static func isAsking(_ capture: String, _ s: BenchSessionInfo, now: Date) -> Bool {
        guard !s.isDead, s.agent != .shell else { return false }
        let lines = capture.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let tail = Array(lines.reversed().drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }.reversed().suffix(12))
        return JobSummary.asking(mode: "attended", state: "running", lines: tail, quietFor: now.timeIntervalSince(s.activity))
    }
}

/// A session's row: "You · Claude", its time and its word.
public struct SessionRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let folder: String
    public let agent: BenchAgent
    /// "You · Claude".
    public let title: String
    /// "23 min".
    public let time: String
    public let label: Label
    public let isAsking: Bool
    public let isDead: Bool
    /// Output or keys in the last few seconds: the row spins.
    public let isWorking: Bool
    public var mark: AgentMark { AgentMark(agent) }

    /// Activity this recent counts as working (the poll runs every 2 s).
    public static let workingWindow: TimeInterval = 4

    public static func make(_ s: BenchSessionInfo, asking: Bool, now: Date) -> SessionRow {
        let label: Label = if s.isDead {
            Label(s.exitCode == BenchLaunch.notFound ? "Not found" : "Exited", .muted)
        } else if asking {
            Label("\(s.agent.title) asks", .amber)
        } else {
            Label("Session", .green)
        }
        return SessionRow(id: s.id, folder: s.folder, agent: s.agent, title: "You \u{00B7} \(s.agent.title)",
                          time: "\(BenchFormat.minutes(from: s.created, to: now)) min", label: label,
                          isAsking: asking && !s.isDead, isDead: s.isDead,
                          isWorking: !s.isDead && !asking && now.timeIntervalSince(s.activity) < workingWindow)
    }
}

/// The work area's lines for a session that has no terminal any more.
public enum SessionWords {
    public static func exited(_ s: BenchSessionInfo) -> (title: String, line: String) {
        if s.exitCode == BenchLaunch.notFound {
            return ("\(s.agent.title) not found", "\(s.agent.rawValue) was not found in your login shell's PATH.")
        }
        return ("Exited", "\(s.agent.title) exited with code \(s.exitCode.map(String.init) ?? "unknown"). Restart runs it again in the same folder.")
    }

    /// The amber note over a session: another session or a Bridge job works in its folder.
    public static func sharedFolder(otherSessions: Int, bridgeJob: String?) -> String? {
        if let bridgeJob { return "Bridge job running here: \(bridgeJob)." }
        return otherSessions > 0 ? "Another session is running here." : nil
    }
}
