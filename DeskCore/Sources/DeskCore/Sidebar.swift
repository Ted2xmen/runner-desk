import Foundation
import ShelfRunnerCore

/// One job row in the sidebar: title, time, label · agent, one line of `now`.
public struct JobRow: Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let folder: String
    public let agent: String
    public let label: Label
    /// Running: "12 min"; ended: "14:02"; otherwise nil.
    public let time: String?
    /// The status `now`, only for a running, asking or waiting job, and only online.
    public let now: String?
    public let phase: JobPhase
    /// In Needs you: in its folder it is drawn short (title and dot only).
    public let needsYou: Bool
    /// Asks the owner right now (online, live, `asking`): the ringed amber dot.
    public let isAsking: Bool
}

public struct FolderSection: Identifiable, Equatable, Sendable {
    /// The folder's path as the runner wrote it.
    public let id: String
    public let name: String
    /// Jobs that have not ended, in the runner's order.
    public let active: [JobRow]
    /// Ended jobs, newest first: the last `SidebarBuilder.finishedShown` unless expanded.
    public let finished: [JobRow]
    /// Every ended job in this folder ("Show all (N)").
    public let finishedTotal: Int
    public let isExpanded: Bool

    /// "Show all (N)" appears only when some are hidden, or to fold an expanded list.
    public var showsFinishedToggle: Bool { finishedTotal > SidebarBuilder.finishedShown }
}

public struct ScheduledRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let agent: String
    /// "Mon 09:00".
    public let next: String?
}

/// One cell of This Mac (memory, disk, battery, heat), with Shelf's thresholds and tones.
public struct MacCell: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let value: String
    public let tone: Tone
}

public struct LimitBar: Equatable, Sendable, Identifiable {
    public let id: String
    /// "5 hours", "Week".
    public let window: String
    public let percent: Int
    public let tone: Tone
    /// "resets 15:00", "resets Mon 09:00".
    public let resets: String?
}

public struct AgentLimits: Equatable, Sendable, Identifiable {
    public var id: String { agent }
    public let agent: String
    public let bars: [LimitBar]
    /// "status line · 2 min ago".
    public let source: String
}

/// The top line.
public enum ConnectionLine: Equatable, Sendable {
    case looking
    /// "Connected · runner 0.3.0 · 12 s ago".
    case connected(String)
    /// "Runner offline · last seen 5 min ago".
    case offline(String)
    /// "Update shelf-runner": another protocol version.
    case unsupported(String)
    /// No runner: no top line; the footer says it instead.
    case none
}

/// Everything the sidebar draws. Built from the last status, the link and the clock.
public struct SidebarModel: Equatable, Sendable {
    public var connection: ConnectionLine = .none
    public var needsYou: [JobRow] = []
    public var folders: [FolderSection] = []
    public var scheduled: [ScheduledRow] = []
    /// This Mac; empty without a runner.
    public var mac: [MacCell] = []
    /// Shown only with data and online.
    public var limits: [AgentLimits] = []
    /// The Dock badge: jobs asking the owner, online only.
    public var askingCount = 0
    /// The non-blocking "Autonomous jobs need shelf-runner · install" footer.
    public var showsRunnerFooter = false
    /// Skeleton rows while looking.
    public var isLooking = false

    public init() {}

    /// Every row, Needs you first, for lookups by id.
    public var allRows: [JobRow] { needsYou + folders.flatMap { $0.active + $0.finished } }
}

public enum SidebarBuilder {
    /// The last 2 ended jobs per folder, then "Show all (N)".
    public static let finishedShown = 2
    /// Limit bars are ink; from 75 % amber, from 90 % rose (Shelf `RunnerDerivation`).
    public static let limitAmber = 75
    public static let limitRose = 90
    /// Disk: under 10 GB new jobs wait, under 5 GB none start (the runner's rule).
    public static let diskWait = 10.0
    public static let diskStop = 5.0
    public static let batteryLow = 20

    /// `expanded`: folders whose "Show all" is open.
    public static func build(status: StatusV1?, link: RunnerLink, now: Date, expanded: Set<String> = [],
                             timeZone: TimeZone = .current) -> SidebarModel {
        var m = SidebarModel()
        switch link {
        case .looking:
            m.connection = .looking
            m.isLooking = true
            return m
        case .absent:
            m.showsRunnerFooter = true
            return m
        case .unsupported(let runner):
            m.connection = .unsupported("Update shelf-runner" + (runner.map { " · runner \($0)" } ?? ""))
            return m
        case .offline(let seen):
            m.connection = .offline("Runner offline" + (seen.map { " · last seen " + DeskFormat.ago(now.timeIntervalSince($0)) } ?? ""))
        case .connected(let runner, let seen):
            m.connection = .connected("Connected · runner \(runner) · " + DeskFormat.ago(now.timeIntervalSince(seen)))
        }
        guard let status else { return m }
        let online = link.isOnline
        let rows = status.jobs.map { row($0, now: now, online: online, timeZone: timeZone) }

        // Offline the last status is stale: nothing claims the owner's attention.
        m.needsYou = online ? rows.filter(\.needsYou) : []
        m.askingCount = rows.filter(\.isAsking).count

        var order: [String] = []
        for f in status.folders + status.jobs.map(\.folder) where !order.contains(f) { order.append(f) }
        m.folders = order.compactMap { path in
            let mine = rows.filter { $0.folder == path }
            let ended = mine.filter(\.phase.isEnded)
            let endedSorted = ended.sorted { endedAt($0, status) > endedAt($1, status) }
            let isExpanded = expanded.contains(path)
            return FolderSection(id: path, name: folderName(path), active: mine.filter { !$0.phase.isEnded },
                                 finished: isExpanded ? endedSorted : Array(endedSorted.prefix(finishedShown)),
                                 finishedTotal: ended.count, isExpanded: isExpanded)
        }
        m.scheduled = status.scheduled.map {
            ScheduledRow(id: $0.id, title: $0.title, agent: Words.agent($0.agent),
                         next: DeskTime.parse($0.next).map { DeskFormat.weekdayClock($0, timeZone: timeZone) })
        }
        m.mac = mac(status.mac, online: online)
        m.limits = online ? limits(status.limits, now: now, timeZone: timeZone) : []
        return m
    }

    public static func folderName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func endedAt(_ row: JobRow, _ status: StatusV1) -> Date {
        DeskTime.parse(status.jobs.first { $0.id == row.id }?.ended) ?? .distantPast
    }

    /// The Needs you scope is Shelf's: asking, first run, failed, not signed.
    /// `stalled` alone is not in it.
    public static func isNeedsYou(_ phase: JobPhase, asking: Bool) -> Bool {
        switch phase {
        case .needsApproval, .failed: true
        case .waiting(let reason): reason == "signature"
        case .running, .stalled: asking
        default: false
        }
    }

    public static func row(_ job: StatusV1.Job, now: Date, online: Bool, timeZone: TimeZone = .current) -> JobRow {
        let phase = JobPhase(state: job.state)
        let started = DeskTime.parse(job.started)
        let minutes = started.map { DeskFormat.minutes(from: $0, to: now) }
        let label = Words.label(phase: phase, asking: job.asking, agent: job.agent, minutes: nil, online: online)
        var time: String?
        if phase.isLive, let minutes { time = "\(minutes) min" }
        if phase.isEnded, let ended = DeskTime.parse(job.ended) { time = DeskFormat.clock(ended, timeZone: timeZone) }
        let showsNow: Bool = {
            if case .waiting = phase { return true }
            return phase.isLive
        }()
        return JobRow(id: job.id, title: job.title, folder: job.folder, agent: Words.agent(job.agent), label: label, time: time,
                      now: online && showsNow ? job.now : nil, phase: phase, needsYou: isNeedsYou(phase, asking: job.asking),
                      isAsking: online && phase.isLive && job.asking)
    }

    static func mac(_ mac: StatusV1.Mac, online: Bool) -> [MacCell] {
        guard online else {
            return [("memory", "Memory"), ("disk", "Disk"), ("battery", "Battery"), ("heat", "Heat")]
                .map { MacCell(id: $0.0, name: $0.1, value: "Unknown", tone: .muted) }
        }
        let memory: (String, Tone) = switch mac.memory {
        case "normal": ("Fine", .plain)
        case "warn": ("Low", .amber)
        case "critical": ("Very low", .rose)
        default: ("Unknown", .muted)
        }
        let disk: (String, Tone) = mac.diskFreeGB.map { gb in
            (String(format: "%.1f GB free", gb), gb < diskStop ? .rose : (gb < diskWait ? .amber : .plain))
        } ?? ("Unknown", .muted)
        let battery: (String, Tone) = {
            guard let b = mac.battery else { return ("Unknown", .muted) }
            if b == "charging" { return ("Charging", .plain) }
            if b == "lowpower" { return ("Low Power Mode", .amber) }
            if b.hasPrefix("battery:"), let p = Int(b.dropFirst("battery:".count)) {
                return ("\(p) %", p < batteryLow ? .amber : .plain)
            }
            return ("Unknown", .muted)
        }()
        let heat: (String, Tone) = switch mac.thermal {
        case "nominal": ("Fine", .plain)
        case "fair": ("Warm", .amber)
        case "serious": ("Hot", .amber)
        case "critical": ("Too hot", .rose)
        default: ("Unknown", .muted)
        }
        return [MacCell(id: "memory", name: "Memory", value: memory.0, tone: memory.1),
                MacCell(id: "disk", name: "Disk", value: disk.0, tone: disk.1),
                MacCell(id: "battery", name: "Battery", value: battery.0, tone: battery.1),
                MacCell(id: "heat", name: "Heat", value: heat.0, tone: heat.1)]
    }

    static func limits(_ limits: [StatusV1.Limit], now: Date, timeZone: TimeZone) -> [AgentLimits] {
        limits.map { l in
            func bar(_ id: String, _ window: String, _ value: Double?, _ resets: String?, weekday: Bool) -> LimitBar? {
                guard let value else { return nil }
                let p = Int(value.rounded())
                let tone: Tone = p >= limitRose ? .rose : (p >= limitAmber ? .amber : .plain)
                let when = DeskTime.parse(resets).map { weekday ? DeskFormat.weekdayClock($0, timeZone: timeZone) : DeskFormat.clock($0, timeZone: timeZone) }
                return LimitBar(id: l.agent + "." + id, window: window, percent: p, tone: tone, resets: when.map { "resets " + $0 })
            }
            let bars = [bar("5h", "5 hours", l.fiveHour, l.resetsFiveHour, weekday: false),
                        bar("week", "Week", l.week, l.resetsWeek, weekday: true)].compactMap { $0 }
            let source = l.source == "statusline" ? "status line" : l.source
            let age = DeskTime.parse(l.at).map { " · " + DeskFormat.ago(now.timeIntervalSince($0)) } ?? ""
            return AgentLimits(agent: Words.agent(l.agent), bars: bars, source: source + age)
        }
    }
}
