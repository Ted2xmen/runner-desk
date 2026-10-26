import Foundation

/// How Bench stands with shelf-bridge (the opening rule).
public enum BridgeLink: Equatable, Sendable {
    /// The first seconds after launch, before anything was heard: skeleton rows, "Looking for shelf-bridge…".
    case looking
    /// No `heartbeat.json` and no status within `LinkRule.lookingSeconds`: Bench works without the
    /// Bridge (the non-blocking "no Bridge" footer).
    case absent
    /// Another protocol version.
    case unsupported(bridge: String?)
    /// `seen` older than `LinkRule.offlineSeconds`, or a heartbeat Bench cannot read.
    case offline(lastSeen: Date?)
    case connected(bridge: String, seen: Date)

    public var isOnline: Bool { if case .connected = self { true } else { false } }

    /// Bridge parts (jobs, This Mac, limits) are drawn: connected or offline (stale but known).
    public var hasBridge: Bool {
        switch self {
        case .connected, .offline: true
        case .looking, .absent, .unsupported: false
        }
    }
}

public enum LinkRule {
    /// No status file and no status within 5 s: no Bridge.
    public static let lookingSeconds: TimeInterval = 5
    /// `seen` older than 3 min: Offline.
    public static let offlineSeconds: TimeInterval = 180

    /// `latest`: the newest reading so far (`StatusReader.newer`); `heartbeatExists`: the file is
    /// on disk now; `launchedAt`: when Bench started looking.
    public static func derive(latest: StatusRead?, heartbeatExists: Bool, launchedAt: Date, now: Date) -> BridgeLink {
        switch latest {
        case .status(let s):
            guard let seen = BenchTime.parse(s.seen) else { return .offline(lastSeen: nil) }
            return now.timeIntervalSince(seen) > offlineSeconds ? .offline(lastSeen: seen) : .connected(bridge: s.bridge, seen: seen)
        case .unsupported(let bridge):
            return .unsupported(bridge: bridge)
        case .unreadable, .none:
            if now.timeIntervalSince(launchedAt) < lookingSeconds { return .looking }
            return heartbeatExists ? .offline(lastSeen: nil) : .absent
        }
    }
}
