import Foundation

/// How Desk stands with shelf-runner (the opening rule).
public enum RunnerLink: Equatable, Sendable {
    /// The first seconds after launch, before anything was heard: skeleton rows, "Looking for shelf-runner…".
    case looking
    /// No `heartbeat.json` and no status within `LinkRule.lookingSeconds`: Desk works without the
    /// runner (the non-blocking "no runner" footer).
    case absent
    /// Another protocol version.
    case unsupported(runner: String?)
    /// `seen` older than `LinkRule.offlineSeconds`, or a heartbeat Desk cannot read.
    case offline(lastSeen: Date?)
    case connected(runner: String, seen: Date)

    public var isOnline: Bool { if case .connected = self { true } else { false } }

    /// Runner parts (jobs, This Mac, limits) are drawn: connected or offline (stale but known).
    public var hasRunner: Bool {
        switch self {
        case .connected, .offline: true
        case .looking, .absent, .unsupported: false
        }
    }
}

public enum LinkRule {
    /// No status file and no status within 5 s: no runner.
    public static let lookingSeconds: TimeInterval = 5
    /// `seen` older than 3 min: Offline.
    public static let offlineSeconds: TimeInterval = 180

    /// `latest`: the newest reading so far (`StatusReader.newer`); `heartbeatExists`: the file is
    /// on disk now; `launchedAt`: when Desk started looking.
    public static func derive(latest: StatusRead?, heartbeatExists: Bool, launchedAt: Date, now: Date) -> RunnerLink {
        switch latest {
        case .status(let s):
            guard let seen = DeskTime.parse(s.seen) else { return .offline(lastSeen: nil) }
            return now.timeIntervalSince(seen) > offlineSeconds ? .offline(lastSeen: seen) : .connected(runner: s.runner, seen: seen)
        case .unsupported(let runner):
            return .unsupported(runner: runner)
        case .unreadable, .none:
            if now.timeIntervalSince(launchedAt) < lookingSeconds { return .looking }
            return heartbeatExists ? .offline(lastSeen: nil) : .absent
        }
    }
}
