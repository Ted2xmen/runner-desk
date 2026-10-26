import Foundation
import ShelfRunnerCore

/// A runner job's tmux place, from the status `tmux` field = `<session>:<window name>`. The runner names
/// the window by the job id and the session `shelf-<folder>` with `[A-Za-z0-9_-]` only
/// (`Tmux.sessionName`); anything else is refused, so no target syntax reaches tmux.
public struct TmuxTarget: Equatable, Sendable, Hashable {
    public let session: String
    public let window: String

    public init?(status: String?, jobID: String) {
        guard let status, let colon = status.firstIndex(of: ":") else { return nil }
        let session = String(status[..<colon])
        let window = String(status[status.index(after: colon)...])
        guard TmuxTarget.isSafeName(session), window == jobID, JobID.isValid(jobID) else { return nil }
        self.session = session
        self.window = window
    }

    public static func isSafeName(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}

/// Names of the sessions Desk makes. Never `shelf-*`, never `desk` (reserved for Desk's own sessions).
public enum ViewName {
    /// The embedded terminal's grouped view.
    public static func view(_ jobID: String) -> String { "view-" + jobID }
    /// Another `view-<id>` is still there (an orphan last member): a suffixed name.
    public static func view(_ jobID: String, suffix: String) -> String { "view-\(jobID)-\(suffix)" }
    /// Open in Terminal and Copy tmux command: a fresh name each time, so a second
    /// click never hits "duplicate session".
    public static func terminal(_ jobID: String, suffix: String) -> String { "term-\(jobID)-\(suffix)" }
    /// Four lower-case hex digits.
    public static func suffix<G: RandomNumberGenerator>(using g: inout G) -> String {
        String(format: "%04x", Int.random(in: 0...0xffff, using: &g))
    }
}

/// tmux argv, exactly as verified against tmux: an argv array, never a shell
/// string; `=` on every session target; `'=name:'` where tmux wants a pane target.
public struct TmuxCommands: Equatable, Sendable {
    /// The absolute path Desk runs.
    public let executable: String
    public let socket: String?
    /// `config.toml [tmux] path` was set: the copied shell line names it; otherwise plain `tmux`.
    public let configuredPath: Bool

    public init(executable: String, socket: String?, configuredPath: Bool = false) {
        self.executable = executable
        self.socket = socket.flatMap { $0.isEmpty ? nil : $0 }
        self.configuredPath = configuredPath
    }

    /// `-L <socket>` when the runner's config names one (the same server as the runner).
    public var base: [String] { socket.map { ["-L", $0] } ?? [] }

    /// The verified one-liner, run by the pty client itself:
    /// `new-session -t '=shelf-X' -s view-<id> ; set-option destroy-unattached keep-group ;
    /// set-option detach-on-destroy on ; set-option status off ; select-window -t ':=<id>'`.
    /// `statusBar`: Terminal keeps tmux's bar (a person there wants it; local to that view).
    public func openView(_ target: TmuxTarget, name: String, statusBar: Bool = false) -> [String] {
        var args = base + ["new-session", "-t", "=" + target.session, "-s", name,
                           ";", "set-option", "destroy-unattached", "keep-group",
                           ";", "set-option", "detach-on-destroy", "on"]
        if !statusBar { args += [";", "set-option", "status", "off"] }
        return args + [";", "select-window", "-t", ":=" + target.window]
    }

    public func hasSession(_ name: String) -> [String] { base + ["has-session", "-t", "=" + name] }

    /// The view's group size; `kill-session` only when it is above 1.
    public func groupSize(_ view: String) -> [String] {
        base + ["display-message", "-p", "-t", "=" + view + ":", "#{session_group_size}"]
    }

    public func killSession(_ view: String) -> [String] { base + ["kill-session", "-t", "=" + view] }

    /// Every session's current window in one call, `<session>\t<window id> <window name>` per line
    /// (the runner's `windowAlive` probe for every open view): a view is torn down as soon as it
    /// no longer shows the job's window.
    public func currentWindows() -> [String] {
        base + ["list-sessions", "-F", "#{session_name}\t#{window_id} #{window_name}"]
    }

    /// The job's own window, before a view opens on it: a view on a closed window would land on
    /// another job's window.
    public func jobWindow(_ target: TmuxTarget) -> [String] {
        base + ["display-message", "-p", "-t", "=\(target.session):=\(target.window)", "#{window_id} #{window_name}"]
    }

    /// The copied command: the same argv as a shell line, `\;` separators, every word
    /// outside `[A-Za-z0-9_./-]` single-quoted (zsh expands a bare `=word`).
    public func shellLine(_ args: [String]) -> String {
        ([configuredPath ? Self.quoted(executable) : "tmux"] + args.map { $0 == ";" ? "\\;" : Self.quoted($0) })
            .joined(separator: " ")
    }

    /// Open in Terminal's `.command`: `unset TMUX`, then `exec` the absolute tmux path.
    public func commandScript(_ args: [String]) -> String {
        "#!/bin/sh\n# Runner Desk: Open in Terminal. Deleted when the job ends.\nunset TMUX\nexec "
            + ([Self.quoted(executable)] + args.map { $0 == ";" ? "\\;" : Self.quoted($0) }).joined(separator: " ") + "\n"
    }

    public static func quoted(_ s: String) -> String {
        let safe = !s.isEmpty && s.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_./-".unicodeScalars.contains($0))
        }
        return safe ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum TmuxReply {
    /// `#{session_group_size}`; nil when tmux printed nothing usable (tmux 3.6 exits 0 for a
    /// missing target with empty fields, runner `Tmux.windowAlive`).
    public static func groupSize(_ output: String) -> Int? {
        Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Kill a view only while another member holds the job windows: the last member's death
    /// takes the live job windows with it.
    public static func mayKill(groupSize: Int?) -> Bool { (groupSize ?? 0) > 1 }

    /// The probe still shows the job's window: `"@N <job id>"`.
    public static func showsJob(_ output: String, jobID: String) -> Bool {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
        return parts.count == 2 && parts[0].hasPrefix("@") && parts[1] == jobID
    }

    /// `currentWindows`' lines by session name, each value a `<window id> <window name>` answer for `showsJob`.
    public static func currentWindows(_ output: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// A failed call's output says no server is running on the socket (a stale socket, or none):
    /// it has no sessions. Any other failure says nothing about them.
    public static func noServer(_ output: String) -> Bool {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("no server running on ")
            || (text.hasPrefix("error connecting to ") && text.hasSuffix("(No such file or directory)"))
    }
}
