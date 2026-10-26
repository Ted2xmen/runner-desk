import Foundation
import ShelfRunnerCore

/// The Shelf segment of the status bar: whether shelf-runner holds a pairing key, whether Shelf
/// is open, and the newest job that came from Shelf. Desk cannot read Shelf's key, so a signed
/// job is the only proof that the two ends share one. The job's age is written at draw time
/// (`help(now:)`), so the model does not change every second.
public struct PairingLine: Equatable, Sendable {
    /// The newest job from Shelf in the status (the runner lists the last 24 hours).
    public enum LastJob: Equatable, Sendable {
        case none
        /// Signed, but with no time yet (waiting for its first-run approval, or queued again).
        case pending
        case at(Date)
    }

    /// The runner's `keyId` (protocol v1); nil: unpaired.
    public let keyId: String?
    public let lastJob: LastJob
    /// Lines waiting for a signature while the runner is paired: not written by Shelf, or Shelf
    /// signed them with another key.
    public let unsigned: Int
    public let shelfRunning: Bool

    public init(keyId: String?, lastJob: LastJob, unsigned: Int, shelfRunning: Bool) {
        self.keyId = keyId
        self.lastJob = lastJob
        self.unsigned = unsigned
        self.shelfRunning = shelfRunning
    }

    /// From the last status; nil without one (no runner, or another protocol version): there is
    /// nothing to be paired with, and the runner segment already says why.
    public static func derive(status: StatusV1?, link: RunnerLink, shelfRunning: Bool) -> PairingLine? {
        guard link.hasRunner, let status else { return nil }
        var newest: Date?
        var signed = false
        var unsigned = 0
        for job in status.jobs {
            let phase = JobPhase(state: job.state)
            guard phase.isFromShelf else {
                unsigned += 1
                continue
            }
            signed = true
            for date in [DeskTime.parse(job.started), DeskTime.parse(job.waitingSince)].compactMap({ $0 }) where date > newest ?? .distantPast {
                newest = date
            }
        }
        let lastJob: LastJob = newest.map { .at($0) } ?? (signed ? .pending : .none)
        let keyId = status.keyId.flatMap { $0.isEmpty ? nil : $0 }
        return PairingLine(keyId: keyId, lastJob: lastJob, unsigned: keyId == nil ? 0 : unsigned, shelfRunning: shelfRunning)
    }

    /// How far Desk can vouch for the pairing.
    public enum State: Equatable, Sendable {
        /// The runner holds a key and a signed job from Shelf is in the status.
        case paired
        /// The runner holds a key, but no signed job proves Shelf holds the same one.
        case keyOnly
        case unpaired
    }

    public var state: State {
        guard keyId != nil else { return .unpaired }
        return lastJob == .none ? .keyOnly : .paired
    }

    /// Only a proven pairing shows Shelf's mark in its own colors.
    public var isPaired: Bool { state == .paired }

    /// "Paired with Shelf", "Waiting for a job from Shelf", "Not paired with Shelf".
    public var text: String {
        switch state {
        case .paired: "Paired with Shelf"
        case .keyOnly: "Waiting for a job from Shelf"
        case .unpaired: "Not paired with Shelf"
        }
    }

    public var tone: Tone { isPaired ? .plain : .muted }

    static let about = "Pairing lets Shelf hand jobs to shelf-runner."
    static let proof = "Runner Desk can't read Shelf's key; a job from Shelf proves the pairing works."
    static let unproven = "Runner Desk can't see Shelf's key. Check Shelf > Settings > Agents, or hand a job to an agent from Shelf to confirm."
    /// The command that makes a new key and the code to paste into Shelf.
    public static let pairCommand = "shelf-runner pair"
    static let pairHint = "The runner has no pairing key. Run shelf-runner pair and paste the code in Shelf."

    /// "Shelf is open", "Shelf is not running".
    public var shelfLine: String { shelfRunning ? "Shelf is open" : "Shelf is not running" }

    /// "1 job waits for a signature: …"; nil when none does.
    public var unsignedLine: String? {
        guard unsigned > 0 else { return nil }
        return "\(unsigned) \(unsigned == 1 ? "job waits" : "jobs wait") for a signature: not from Shelf, or Shelf holds another key."
    }

    /// What Desk can and cannot tell: why a job is the proof, where to look without one, or how
    /// to pair.
    public var honestLine: String {
        switch state {
        case .paired: Self.proof
        case .keyOnly: Self.unproven
        case .unpaired: Self.pairHint
        }
    }

    /// "Last job from Shelf: 2 h ago".
    public func lastJobLine(now: Date) -> String {
        switch lastJob {
        case .none: "No job from Shelf in the last 24 hours"
        case .pending: "A job from Shelf is waiting to start"
        case .at(let date): "Last job from Shelf: " + DeskFormat.ago(now.timeIntervalSince(date))
        }
    }

    /// The tooltip: what pairing is, the runner's key, Shelf open or not, the newest job from
    /// Shelf, and why that job is the proof.
    public func help(now: Date) -> String {
        var lines = [Self.about]
        if let keyId { lines.append("Runner key: \(keyId)") }
        lines.append(shelfLine)
        lines.append(lastJobLine(now: now))
        if let unsignedLine { lines.append(unsignedLine) }
        lines.append(honestLine)
        return lines.joined(separator: "\n")
    }

    /// "Paired with Shelf, Shelf is open, last job from Shelf: 2 h ago".
    public func accessibilityLabel(now: Date) -> String {
        [text, shelfLine, lastJobLine(now: now).lowercasedFirst]
            .joined(separator: ", ")
    }

    /// The tooltip holds an age that moves with the clock.
    public var showsAge: Bool { if case .at = lastJob { true } else { false } }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
