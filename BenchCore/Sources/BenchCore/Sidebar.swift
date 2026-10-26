import Foundation
import ShelfBridgeCore

/// One job row in the sidebar: title, time, label · agent, one line of `now`.
public struct JobRow: Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let folder: String
    public let agent: String
    /// Which mark the row shows.
    public let mark: AgentMark
    public let label: Label
    /// Running: "12 min"; ended: "14:02"; otherwise nil.
    public let time: String?
    /// The status `now`, only for a running, asking or waiting job, and only online.
    public let now: String?
    public let phase: JobPhase
    public var isFromShelf: Bool { phase.isFromShelf }
    /// Also listed in Needs you; it stays under its folder too.
    public let needsYou: Bool
    /// Asks the owner right now (online, live, `asking`): the ringed amber dot.
    public let isAsking: Bool
}

public struct FolderSection: Identifiable, Equatable, Sendable {
    /// The folder's path as Bridge wrote it.
    public let id: String
    public let name: String
    /// Jobs that have not ended, in Bridge's order.
    public let active: [JobRow]
    /// Ended jobs, newest first: the last `SidebarBuilder.finishedShown` unless expanded.
    public let finished: [JobRow]
    /// Every ended job in this folder ("Show all (N)").
    public let finishedTotal: Int
    public let isExpanded: Bool
    /// How many of this folder's jobs and sessions are also in Needs you.
    public let inNeedsYou: Int
    /// Bench's own sessions here, oldest first (an asking one too; it is also in Needs you).
    public let sessions: [SessionRow]
    /// Shown when the folder has nothing to list: "No jobs in the last 24 hours", "No sessions".
    public let emptyLine: String?

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
    /// The status bar's short form: "5h", "wk".
    public let short: String
    public let percent: Int
    public let tone: Tone
    /// "resets 15:00", "resets Mon 09:00".
    public let resets: String?
}

public struct AgentLimits: Equatable, Sendable, Identifiable {
    public var id: String { agent }
    public let agent: String
    public let bars: [LimitBar]
    /// "status line".
    public let source: String
    /// When Bridge read these limits; the age is written at draw time (`sourceLine`).
    public let at: Date?

    /// "status line · 2 min ago". Kept out of the model: it changes every second.
    public func sourceLine(now: Date) -> String {
        source + (at.map { " · " + BenchFormat.ago(now.timeIntervalSince($0)) } ?? "")
    }
}

/// Bridge segment of the status bar: a short state that does not move with the clock, and a
/// tooltip whose age ("Last heard 12 s ago") is written at draw time (`help(now:)`), so the model
/// does not change every second.
public enum ConnectionLine: Equatable, Sendable {
    case looking
    case connected(bridge: String, seen: Date, slots: StatusV2.Slots?)
    /// `Bridge`: the version in the last status, if any.
    case offline(bridge: String?, lastSeen: Date?)
    /// Another protocol version.
    case unsupported(bridge: String?)
    /// No heartbeat at all; the install footer shows too.
    case absent

    /// "shelf-bridge running".
    public var text: String {
        switch self {
        case .looking: "Looking for shelf-bridge…"
        case .connected: "shelf-bridge running"
        case .offline: "shelf-bridge offline"
        case .unsupported: "Update shelf-bridge"
        case .absent: "No shelf-bridge"
        }
    }

    public var tone: Tone {
        switch self {
        case .looking, .absent: .muted
        case .connected: .green
        case .offline: .rose
        case .unsupported: .amber
        }
    }

    public var bridge: String? {
        switch self {
        case .connected(let bridge, _, _): bridge
        case .offline(let bridge, _), .unsupported(let bridge): bridge
        case .looking, .absent: nil
        }
    }

    /// "shelf-bridge running, version 0.3.0".
    public var accessibilityLabel: String {
        text + (bridge.map { ", version \($0)" } ?? "")
    }

    static let about = "shelf-bridge: the background service that runs agent jobs (not Shelf pairing)."

    /// The tooltip: what shelf-bridge is, its version, the heartbeat's age, slots, and a hint
    /// when it is not running.
    public func help(now: Date) -> String {
        var lines = [Self.about]
        if let bridge { lines.append("Version \(bridge)") }
        switch self {
        case .looking:
            lines.append("Reading heartbeat.json")
        case .connected(_, let seen, let slots):
            lines.append("Last heard " + BenchFormat.ago(now.timeIntervalSince(seen)))
            if let slots { lines.append("Slots: \(slots.running) of \(slots.max) in use, \(slots.perFolder) per folder") }
        case .offline(_, let seen):
            lines.append(seen.map { "Last heard " + BenchFormat.ago(now.timeIntervalSince($0)) } ?? "Its heartbeat cannot be read")
            lines.append("No heartbeat for over \(Int(LinkRule.offlineSeconds / 60)) min; jobs shown may be out of date. Check it with shelf-bridge doctor.")
        case .unsupported:
            lines.append("This Bridge speaks another protocol version than Shelf Bench.")
        case .absent:
            lines.append("Not installed or never started. Sessions work without it; autonomous jobs need it.")
        }
        return lines.joined(separator: "\n")
    }

    /// The tooltip holds an age that moves with the clock.
    public var showsAge: Bool {
        switch self {
        case .connected: true
        case .offline(_, let seen): seen != nil
        case .looking, .unsupported, .absent: false
        }
    }
}

/// Everything the sidebar draws. Built from the last status, the link and the clock.
public struct SidebarModel: Equatable, Sendable {
    public var connection: ConnectionLine = .looking
    /// The Shelf pairing segment; nil without Bridge's status.
    public var pairing: PairingLine?
    public var needsYou: [JobRow] = []
    public var folders: [FolderSection] = []
    public var scheduled: [ScheduledRow] = []
    /// This Mac; empty without Bridge.
    public var mac: [MacCell] = []
    /// Shown only with data and online.
    public var limits: [AgentLimits] = []
    /// Bench sessions asking (found on their screen); also under their folder.
    public var askingSessions: [SessionRow] = []
    /// The Dock badge: jobs asking the owner (online only) and asking Bench sessions.
    public var askingCount = 0
    /// The non-blocking "Autonomous jobs need shelf-bridge · install" footer.
    public var showsBridgeFooter = false
    /// Skeleton rows while looking.
    public var isLooking = false

    public init() {}

    /// Every row, Needs you first, for lookups by id.
    public var allRows: [JobRow] { needsYou + folders.flatMap { $0.active + $0.finished } }
    public var allSessions: [SessionRow] { askingSessions + folders.flatMap(\.sessions) }
    /// Nothing at all to list: no job, no session, no folder.
    public var isBlank: Bool { needsYou.isEmpty && askingSessions.isEmpty && folders.isEmpty }
}

public enum SidebarBuilder {
    /// The last 2 ended jobs per folder, then "Show all (N)".
    public static let finishedShown = 2
    /// Limit bars are ink; from 75 % amber, from 90 % rose (Shelf `BridgeDerivation`).
    public static let limitAmber = 75
    public static let limitRose = 90
    /// Disk: under 10 GB new jobs wait, under 5 GB none start (Bridge's rule).
    public static let diskWait = 10.0
    public static let diskStop = 5.0
    public static let batteryLow = 20

    /// `expanded`: folders whose "Show all" is open. `sessions`: Bench's own, `asking` the ids of
    /// those found asking. `recents`: folders Bench opened sessions in, listed only without Bridge.
    /// `shelfRunning`: the Shelf app is open.
    public static func build(status: StatusV2?, link: BridgeLink, now: Date, expanded: Set<String> = [],
                             sessions: [BenchSessionInfo] = [], asking: Set<String> = [], recents: [String] = [],
                             shelfRunning: Bool = false, timeZone: TimeZone = .current) -> SidebarModel {
        var m = SidebarModel()
        m.pairing = PairingLine.derive(status: status, link: link, shelfRunning: shelfRunning)
        let sessionRows = sessions.sorted { $0.created < $1.created }.map { SessionRow.make($0, asking: asking.contains($0.id), now: now) }
        m.askingSessions = sessionRows.filter(\.isAsking)
        m.askingCount = m.askingSessions.count
        /// Folders from sessions (and recents) alone: without Bridge, or before it answers.
        func sessionFolders(after known: [String], withRecents: Bool) -> [FolderSection] {
            var order: [String] = []
            for f in sessionRows.map(\.folder) + (withRecents ? recents : []) where !known.contains(f) && !order.contains(f) { order.append(f) }
            return order.map { path in
                let mine = sessionRows.filter { $0.folder == path }
                return FolderSection(id: path, name: folderName(path), active: [], finished: [], finishedTotal: 0, isExpanded: false,
                                     inNeedsYou: mine.filter(\.isAsking).count, sessions: mine,
                                     emptyLine: mine.isEmpty && sessionRows.allSatisfy { $0.folder != path } ? "No sessions" : nil)
            }
        }
        switch link {
        case .looking:
            m.connection = .looking
            m.isLooking = sessionRows.isEmpty
            m.folders = sessionFolders(after: [], withRecents: false)
            return m
        case .absent:
            m.connection = .absent
            m.showsBridgeFooter = true
            m.folders = sessionFolders(after: [], withRecents: true)
            return m
        case .unsupported(let bridge):
            m.connection = .unsupported(bridge: bridge)
            m.folders = sessionFolders(after: [], withRecents: false)
            return m
        case .offline(let seen):
            m.connection = .offline(bridge: status?.bridge, lastSeen: seen)
        case .connected(let bridge, let seen):
            m.connection = .connected(bridge: bridge, seen: seen, slots: status?.slots)
        }
        guard let status else {
            m.folders = sessionFolders(after: [], withRecents: false)
            return m
        }
        let online = link.isOnline
        let rows = status.jobs.map { row($0, now: now, online: online, timeZone: timeZone) }

        // Offline the last status is stale: nothing claims the owner's attention.
        m.needsYou = online ? rows.filter(\.needsYou) : []
        m.askingCount += rows.filter(\.isAsking).count

        // A job in Needs you stays under its folder too: the folder always shows all it has.
        let inNeedsYou = Set(m.needsYou.map(\.id))
        var order: [String] = []
        for f in status.folders + status.jobs.map(\.folder) where !order.contains(f) { order.append(f) }
        m.folders = order.compactMap { path in
            let all = rows.filter { $0.folder == path }
            let mine = all
            let ended = mine.filter(\.phase.isEnded)
            let endedSorted = ended.sorted { endedAt($0, status) > endedAt($1, status) }
            let isExpanded = expanded.contains(path)
            let active = mine.filter { !$0.phase.isEnded }
            let here = sessionRows.filter { $0.folder == path }
            let nothing = active.isEmpty && ended.isEmpty && here.isEmpty
            return FolderSection(id: path, name: folderName(path), active: active,
                                 finished: isExpanded ? endedSorted : Array(endedSorted.prefix(finishedShown)),
                                 finishedTotal: ended.count, isExpanded: isExpanded,
                                 inNeedsYou: all.filter { inNeedsYou.contains($0.id) }.count + here.filter(\.isAsking).count,
                                 sessions: here,
                                 emptyLine: nothing ? "No jobs in the last 24 hours" : nil)
        }
        m.folders += sessionFolders(after: order, withRecents: false)
        m.scheduled = status.scheduled.map {
            ScheduledRow(id: $0.id, title: $0.title, agent: Words.agent($0.agent),
                         next: BenchTime.parse($0.next).map { BenchFormat.weekdayClock($0, timeZone: timeZone) })
        }
        m.mac = mac(status.mac, online: online)
        m.limits = online ? limits(status.limits, timeZone: timeZone) : []
        return m
    }

    public static func folderName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func endedAt(_ row: JobRow, _ status: StatusV2) -> Date {
        BenchTime.parse(status.jobs.first { $0.id == row.id }?.ended) ?? .distantPast
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

    public static func row(_ job: StatusV2.Job, now: Date, online: Bool, timeZone: TimeZone = .current) -> JobRow {
        let phase = JobPhase(state: job.state)
        let started = BenchTime.parse(job.started)
        let minutes = started.map { BenchFormat.minutes(from: $0, to: now) }
        let label = Words.label(phase: phase, asking: job.asking, agent: job.agent, minutes: nil, online: online)
        var time: String?
        if phase.isLive, let minutes { time = "\(minutes) min" }
        if phase.isEnded, let ended = BenchTime.parse(job.ended) { time = BenchFormat.clock(ended, timeZone: timeZone) }
        let showsNow: Bool = {
            if case .waiting = phase { return true }
            return phase.isLive
        }()
        return JobRow(id: job.id, title: job.title, folder: job.folder, agent: Words.agent(job.agent), mark: AgentMark(raw: job.agent),
                      label: label, time: time,
                      now: online && showsNow ? job.now : nil, phase: phase, needsYou: isNeedsYou(phase, asking: job.asking),
                      isAsking: online && phase.isLive && job.asking)
    }

    static func mac(_ mac: StatusV2.Mac, online: Bool) -> [MacCell] {
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

    static func limits(_ limits: [StatusV2.Limit], timeZone: TimeZone) -> [AgentLimits] {
        limits.map { l in
            func bar(_ id: String, _ window: String, _ short: String, _ value: Double?, _ resets: String?, weekday: Bool) -> LimitBar? {
                guard let value else { return nil }
                let p = Int(value.rounded())
                let tone: Tone = p >= limitRose ? .rose : (p >= limitAmber ? .amber : .plain)
                let when = BenchTime.parse(resets).map { weekday ? BenchFormat.weekdayClock($0, timeZone: timeZone) : BenchFormat.clock($0, timeZone: timeZone) }
                return LimitBar(id: l.agent + "." + id, window: window, short: short, percent: p, tone: tone, resets: when.map { "resets " + $0 })
            }
            let bars = [bar("5h", "5 hours", "5h", l.fiveHour, l.resetsFiveHour, weekday: false),
                        bar("week", "Week", "wk", l.week, l.resetsWeek, weekday: true)].compactMap { $0 }
            let source = l.source == "statusline" ? "status line" : l.source
            return AgentLimits(agent: Words.agent(l.agent), bars: bars, source: source, at: BenchTime.parse(l.at))
        }
    }
}
