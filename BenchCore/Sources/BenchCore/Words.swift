import Foundation

/// A color meaning (palette v2): running and done green; asking, approval,
/// not signed, stalled and missed amber; failures rose; waiting, queued, unknown neutral.
/// The accent is never a state.
public enum Tone: Sendable, Hashable {
    case plain
    case muted
    case green
    case amber
    case rose
}

/// A job's `state` (protocol v2) as Bench reads it.
public enum JobPhase: Equatable, Sendable, Hashable {
    case queued
    /// `waiting:<reason>`; the reason as Bridge wrote it.
    case waiting(String)
    case needsApproval
    case running
    case stalled
    case done
    /// `failed:<code>`: an exit code, `timeout` or `lost`.
    case failed(String)
    case cancelled
    case missed
    case unknown

    public init(state: String) {
        switch state {
        case "queued": self = .queued
        case "needs-approval": self = .needsApproval
        case "running": self = .running
        case "stalled": self = .stalled
        case "done": self = .done
        case "cancelled": self = .cancelled
        case "missed": self = .missed
        default:
            if state.hasPrefix("waiting:") { self = .waiting(String(state.dropFirst("waiting:".count))) }
            else if state.hasPrefix("failed:") { self = .failed(String(state.dropFirst("failed:".count))) }
            else { self = .unknown }
        }
    }

    /// Ended: a result, not a terminal.
    public var isEnded: Bool {
        switch self {
        case .done, .failed, .cancelled, .missed: true
        default: false
        }
    }

    /// Came from Shelf: Bridge runs only lines signed with the pairing key, and only Shelf
    /// signs them (Bridge's CLI does not). An unsigned line waits as `waiting:signature`.
    public var isFromShelf: Bool { self != .waiting("signature") }

    /// Has a tmux window Bridge still watches.
    public var isLive: Bool { self == .running || self == .stalled }
}

/// A short label and its tone.
public struct Label: Equatable, Sendable, Hashable {
    public let text: String
    public let tone: Tone

    public init(_ text: String, _ tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public static let unknown = Label("Unknown", .muted)
}

/// The words of protocol v2 and Shelf's app, exactly.
public enum Words {
    /// No agent badge, only the name.
    public static func agent(_ raw: String) -> String {
        switch raw {
        case "claude": "Claude"
        case "codex": "Codex"
        default: raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// Protocol v2's closed list of `waiting:` reasons; outside it "Waiting".
    public static func waiting(_ reason: String, agent: String) -> String {
        switch reason {
        case "memory": "Waits for memory"
        case "disk": "Waits for disk space"
        case "battery": "Waits for power"
        case "thermal": "Waits for the Mac to cool"
        case "limit":
            switch agent {
            case "claude": "Waits for the Claude limit"
            case "codex": "Waits for the Codex limit"
            default: "Waits for a limit"
            }
        case "slot": "Waits for a free slot"
        case "folder": "Waits for the folder"
        case "paused": "Paused"
        case "daily": "Daily limit: waits for tomorrow"
        case "signature": "Not signed"
        default: "Waiting"
        }
    }

    /// A job's label. `minutes`: since it started, for "Running N min" (nil: plain "Running").
    /// `online == false`: a job that has not ended is "Unknown"; an ended one keeps its word.
    public static func label(phase: JobPhase, asking: Bool, agent: String, minutes: Int?, online: Bool) -> Label {
        if !online && !phase.isEnded { return .unknown }
        switch phase {
        case .queued: return Label("Queued", .muted)
        case .waiting(let reason):
            return Label(waiting(reason, agent: agent), reason == "signature" ? .amber : .muted)
        case .needsApproval: return Label("First run: approve", .amber)
        case .running, .stalled:
            if asking { return Label("Asks you", .amber) }
            if phase == .stalled { return Label("May be stalled", .amber) }
            return Label(minutes.map { "Running \($0) min" } ?? "Running", .green)
        case .done: return Label("Done", .green)
        case .failed(let code): return Label(failure(code), .rose)
        case .cancelled: return Label("Cancelled", .muted)
        case .missed: return Label("Missed", .amber)
        case .unknown: return .unknown
        }
    }

    /// `failed:<code>`'s word: "Stopped: took too long", "Lost when Bridge restarted", else "Failed".
    public static func failure(_ code: String) -> String {
        switch code {
        case "timeout": "Stopped: took too long"
        case "lost": "Lost when Bridge restarted"
        default: "Failed"
        }
    }

    /// Shelf's "blocked" suffix: nil for null or 0.
    public static func blocked(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 action blocked" : "\(count) actions blocked"
    }
}
