import Foundation
import ShelfRunnerCore

/// The work area for one runner job, D1: no actions (Stop, Run, Retry come later).
public struct JobDetail: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        /// A live job: the embedded terminal on a grouped view session.
        case terminal(TmuxTarget)
        /// Live by its state but without a usable tmux target.
        case noTarget
        /// An ended job: the result card and the log.
        case result(ResultCard)
        /// `DeskOnay-D1`: "Approve it in Shelf."
        case approval(line: String)
        /// `waiting:signature` (not signed): Shelf's buttons, no action here.
        case notSigned
        /// Waiting, without "Run anyway" (comes later).
        case waiting(reason: String, soFar: String?, since: String?)
        case queued
        /// Offline and not live: the last known state, "Unknown".
        case unknown
    }

    public struct ResultCard: Equatable, Sendable {
        /// "Done", "Failed", "Stopped: took too long", …
        public let title: String
        public let tone: Tone
        /// "Finished at 09:14 after 6 min.", "Stopped with exit code 1 at 08:41."
        public let line: String?
        /// "The last lines of the log usually say why." for a failure.
        public let hint: String?
        /// "2 actions blocked".
        public let blocked: String?
        /// The job's `out` path.
        public let out: String?
    }

    public let id: String
    public let title: String
    public let folder: String
    /// "SHELF-TEST/TODO.md": the folder's name and the task's file from `ref`.
    public let source: String
    public let agent: String
    /// "attended" / "unattended".
    public let mode: String
    /// The header chip: "Running 12 min", "Asks you", "Done".
    public let label: Label
    public let body: Body
    /// For the log reader: the job's `mode` decides screen capture or log file.
    public let isAttended: Bool
}

public enum DetailBuilder {
    public static func build(_ job: StatusV1.Job, online: Bool, now: Date, timeZone: TimeZone = .current) -> JobDetail {
        let phase = JobPhase(state: job.state)
        let started = DeskTime.parse(job.started)
        let ended = DeskTime.parse(job.ended)
        let minutes = started.map { DeskFormat.minutes(from: $0, to: now) }
        let label = Words.label(phase: phase, asking: job.asking, agent: job.agent, minutes: minutes, online: online)
        let folder = SidebarBuilder.folderName(job.folder)
        let body: JobDetail.Body
        // A live job's terminal works offline too: Desk talks to tmux directly.
        if phase.isLive {
            body = TmuxTarget(status: job.tmux, jobID: job.id).map { .terminal($0) } ?? .noTarget
        } else if phase.isEnded {
            body = .result(card(job, phase: phase, started: started, ended: ended, timeZone: timeZone))
        } else if !online {
            body = .unknown
        } else {
            switch phase {
            case .needsApproval:
                body = .approval(line: "\(Words.agent(job.agent)), \(job.mode), in \(folder).")
            case .waiting(let reason) where reason == "signature":
                body = .notSigned
            case .waiting(let reason):
                let since = DeskTime.parse(job.waitingSince)
                let waited = since.map { DeskFormat.minutes(from: $0, to: now) }
                let soFar = waited.map { w in job.waitMaxMin.map { "\(w) of \($0) min so far" } ?? "\(w) min so far" }
                body = .waiting(reason: Words.waiting(reason, agent: job.agent), soFar: soFar,
                                since: since.map { "Waiting since " + DeskFormat.clock($0, timeZone: timeZone) })
            case .queued:
                body = .queued
            default:
                body = .unknown
            }
        }
        return JobDetail(id: job.id, title: job.title, folder: folder, source: source(folder: folder, ref: job.ref),
                         agent: Words.agent(job.agent), mode: job.mode, label: label, body: body,
                         isAttended: job.mode == "attended")
    }

    /// `ref` = `<path>@<h8>` with `%20`, `%40`, `%25` escapes (protocol v1); without one, the folder alone.
    public static func source(folder: String, ref: String?) -> String {
        guard let ref, let at = ref.lastIndex(of: "@") else { return folder }
        let path = String(ref[..<at])
            .replacingOccurrences(of: "%20", with: " ")
            .replacingOccurrences(of: "%40", with: "@")
            .replacingOccurrences(of: "%25", with: "%")
        return path.isEmpty ? folder : folder + "/" + path
    }

    static func card(_ job: StatusV1.Job, phase: JobPhase, started: Date?, ended: Date?, timeZone: TimeZone) -> JobDetail.ResultCard {
        let at = ended.map { DeskFormat.clock($0, timeZone: timeZone) }
        let took = zip2(started, ended).map { DeskFormat.minutes(from: $0.0, to: $0.1) }
        switch phase {
        case .done:
            var line = at.map { "Finished at \($0)" }
            if let line0 = line, let took { line = line0 + " after \(took) min" }
            return .init(title: "Done", tone: .green, line: line.map { $0 + "." }, hint: nil,
                         blocked: Words.blocked(job.blocked), out: job.out)
        case .failed(let code):
            let line: String? = Int(code).map { c in at.map { "Stopped with exit code \(c) at \($0)." } ?? "Stopped with exit code \(c)." }
            return .init(title: Words.failure(code), tone: .rose, line: line, hint: "The last lines of the log usually say why.",
                         blocked: nil, out: job.out)
        case .cancelled:
            return .init(title: "Cancelled", tone: .muted, line: nil, hint: nil, blocked: nil, out: job.out)
        default:
            return .init(title: "Missed", tone: .amber, line: nil, hint: nil, blocked: nil, out: job.out)
        }
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}
