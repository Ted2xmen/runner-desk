import Foundation
import ShelfBridgeCore

/// One folder Bridge reads, as the Settings window lists it.
public struct SettingsFolderRow: Identifiable, Equatable, Sendable {
    /// The path as Bridge wrote it.
    public let id: String
    /// The path with the home folder written as `~`.
    public let display: String
    /// "1 running · 2 waiting", "No active jobs".
    public let detail: String
}

/// A command the Settings window offers to copy.
public enum BridgeCommand: Equatable, Sendable {
    /// Installs shelf-bridge; the app holds the exact command.
    case install
    case doctor
    case pair
    case enable

    /// The command, except for `install`, whose text the app holds.
    public var text: String? {
        switch self {
        case .install: nil
        case .doctor: "shelf-bridge doctor"
        case .pair: PairingLine.pairCommand
        case .enable: "shelf-bridge enable <folder>"
        }
    }
}

/// The Settings window's Bridge section: the same state as the status bar, with the details the
/// bar keeps in its tooltips written out. Ages are written at draw time, like the bar's.
public struct BridgeSettings: Equatable, Sendable {
    public let connection: ConnectionLine
    /// `pause` is on in the last status: no new starts.
    public let paused: Bool
    /// nil without Bridge's status: pairing and folders hide.
    public let pairing: PairingLine?
    /// nil without Bridge's status.
    public let folders: [SettingsFolderRow]?

    public init(connection: ConnectionLine, paused: Bool, pairing: PairingLine?, folders: [SettingsFolderRow]?) {
        self.connection = connection
        self.paused = paused
        self.pairing = pairing
        self.folders = folders
    }

    /// From the status bar's model and the last status. `home`: the user's home folder, for `~`.
    public static func derive(sidebar: SidebarModel, status: StatusV2?, home: String) -> BridgeSettings {
        guard let pairing = sidebar.pairing, let status else {
            return BridgeSettings(connection: sidebar.connection, paused: false, pairing: nil, folders: nil)
        }
        let folders = status.folders.map { path in
            SettingsFolderRow(id: path, display: abbreviate(path, home: home),
                              detail: folderDetail(status.jobs.filter { $0.folder == path }))
        }
        return BridgeSettings(connection: sidebar.connection, paused: status.paused, pairing: pairing, folders: folders)
    }

    static let pausedLine = "Paused: no new jobs start; running jobs go on."
    static let noFolders = "No folders yet"
    static let noFoldersHint = "Bridge reads only the folders you enable:"

    /// Under the state: version, slots and paused; the heartbeat's age comes from `ageLine(now:)`.
    public var statusLines: [String] {
        var lines: [String] = []
        if let bridge = connection.bridge { lines.append("Version \(bridge)") }
        if let slots = connection.slotsLine { lines.append(slots) }
        return lines
    }

    public var pausedLine: String? { paused ? Self.pausedLine : nil }

    /// What Bridge's state means, and where to go from it; nil when it runs.
    public var statusNote: String? { connection.note }

    public var statusCommand: BridgeCommand? {
        switch connection {
        case .absent: .install
        case .offline: .doctor
        case .looking, .connected, .unsupported: nil
        }
    }

    /// Unpaired: how to pair, with the command below it.
    public var pairingNote: String? {
        guard let pairing else { return nil }
        switch pairing.state {
        case .paired, .keyOnly: return pairing.honestLine
        case .unpaired: return "Bridge has no pairing key. Run this, then paste the SB1- code in Shelf > Settings > Agents > Bridge."
        }
    }

    public var pairingCommand: BridgeCommand? { pairing?.state == .unpaired ? .pair : nil }

    /// "No folders yet" and its hint; nil while there are folders or no status.
    public var emptyFolders: (title: String, hint: String, command: BridgeCommand)? {
        guard let folders, folders.isEmpty else { return nil }
        return (Self.noFolders, Self.noFoldersHint, .enable)
    }

    static func abbreviate(_ path: String, home: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Live jobs count as running (a stalled one too); jobs not yet started as waiting.
    static func folderDetail(_ jobs: [StatusV2.Job]) -> String {
        let phases = jobs.map { JobPhase(state: $0.state) }
        let running = phases.filter(\.isLive).count
        let waiting = phases.filter { !$0.isLive && !$0.isEnded }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        return parts.isEmpty ? "No active jobs" : parts.joined(separator: " \u{00B7} ")
    }
}

extension ConnectionLine {
    /// "Last heard 12 s ago"; nil when there is no heartbeat time.
    public func ageLine(now: Date) -> String? {
        switch self {
        case .connected(_, let seen, _): "Last heard " + BenchFormat.ago(now.timeIntervalSince(seen))
        case .offline(_, let seen): seen.map { "Last heard " + BenchFormat.ago(now.timeIntervalSince($0)) }
        case .looking, .unsupported, .absent: nil
        }
    }

    /// "Slots: 2 of 2 in use, 1 per folder".
    public var slotsLine: String? {
        guard case .connected(_, _, let slots?) = self else { return nil }
        return "Slots: \(slots.running) of \(slots.max) in use, \(slots.perFolder) per folder"
    }

    /// What a state other than running means.
    public var note: String? {
        switch self {
        case .looking: "Reading heartbeat.json"
        case .connected: nil
        case .offline(_, let seen):
            (seen == nil ? "Its heartbeat cannot be read. " : "")
                + "No heartbeat for over \(Int(LinkRule.offlineSeconds / 60)) min; jobs shown may be out of date."
        case .unsupported: "This Bridge speaks another protocol version than Shelf Bench."
        case .absent: "Not installed or never started. Sessions work without it; autonomous jobs need it."
        }
    }
}
