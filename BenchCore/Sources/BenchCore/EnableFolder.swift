import Foundation

/// Turning a folder on in shelf-bridge from Bench: the checks on the path, the sheet's words and
/// states, the CLI's argv and how its answer reads. Bench always asks first and runs
/// `shelf-bridge enable <path>` only after the user's yes; the file system and the process are
/// the app's.
public enum EnableFolder {
    public static let title = "Enable this folder in shelf-bridge?"
    public static let explanation = "Agents can run jobs in this folder. A job starts only from a signed queue line, and only after you approve that line."
    public static let cliName = "shelf-bridge"

    /// Why a path can't be enabled.
    public enum Problem: Equatable, Sendable {
        case malformedLink
        case notAbsolute
        case missing
        case notADirectory
        case root
        case home
        case system

        public var message: String {
            switch self {
            case .malformedLink: "This link doesn't name a folder."
            case .notAbsolute: "The folder must be a full path, starting with /."
            case .missing: "This folder doesn't exist."
            case .notADirectory: "This is a file, not a folder."
            case .root: "The whole disk can't be enabled. Choose a project folder."
            case .home: "Your home folder can't be enabled. Choose a project folder inside it."
            case .system: "This is a system location. Choose a project folder."
            }
        }
    }

    public enum Check: Equatable, Sendable {
        /// The realpath to enable.
        case ok(String)
        case problem(Problem)
    }

    /// Folders that never hold a project, matched on the realpath (`/tmp` is `/private/tmp`).
    static let systemPrefixes = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/etc", "/var",
                                 "/tmp", "/dev", "/cores", "/opt", "/Applications"]
    /// Only the folder itself is refused: what is inside may be a project.
    static let systemExact = ["/Users", "/Volumes"]

    /// `requested`: the path as asked for. `resolved`: its realpath, nil when it does not exist.
    /// `isDirectory`: the realpath is a folder. `home`: the user's home folder.
    public static func check(requested: String, resolved: String?, isDirectory: Bool, home: String) -> Check {
        guard requested.hasPrefix("/") else { return .problem(.notAbsolute) }
        guard let resolved else { return .problem(.missing) }
        guard isDirectory else { return .problem(.notADirectory) }
        let path = trimmed(resolved)
        let home = trimmed(home)
        if path == "/" { return .problem(.root) }
        if !home.isEmpty, path == home { return .problem(.home) }
        if systemExact.contains(path) || systemPrefixes.contains(where: { inside(path, $0) }) { return .problem(.system) }
        if !home.isEmpty, inside(path, home + "/Library") { return .problem(.system) }
        return .ok(path)
    }

    /// Bridge lists the folder in its status already (`folders` holds realpaths).
    public static func isEnabled(_ resolved: String, folders: [String]?) -> Bool {
        folders?.contains(trimmed(resolved)) ?? false
    }

    /// The CLI's arguments after its executable: argv, never a shell.
    public static func arguments(_ resolved: String) -> [String] { ["enable", resolved] }

    /// The same command for Terminal, the path quoted when it needs it.
    public static func command(_ resolved: String) -> String {
        ([cliName] + arguments(resolved).map(TmuxCommands.quoted)).joined(separator: " ")
    }

    // MARK: finding the CLI

    /// Bridge's LaunchAgent label: its plist names the binary the background agent runs.
    public static let launchAgentLabel = "dev.ted2xmen.shelf-bridge"
    /// ShelfBridge.app's bundle id.
    public static let bundleID = "dev.ted2xmen.shelf-bridge"

    /// The executable in the LaunchAgent plist (`ProgramArguments[0]`), when it is an absolute
    /// path to a `shelf-bridge` binary.
    public static func launchAgentProgram(_ plist: Data) -> String? {
        guard let dict = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let args = dict["ProgramArguments"] as? [String], let first = args.first,
              first.hasPrefix("/"), (first as NSString).lastPathComponent == cliName else { return nil }
        return first
    }

    /// The binary inside a ShelfBridge.app bundle.
    public static func bundleExecutable(app: String) -> String {
        (trimmed(app) as NSString).appendingPathComponent("Contents/MacOS/\(cliName)")
    }

    /// Where to look, in order: the binary the background agent runs (same build, same state),
    /// then PATH and the usual install places, then the app bundle Launch Services knows.
    /// Duplicates dropped; the app keeps the first that is executable.
    public static func candidates(launchAgent: String?, onPath: String?, appBundle: String?) -> [String] {
        var out: [String] = []
        for c in [launchAgent, onPath, appBundle.map { bundleExecutable(app: $0) }] {
            if let c, !out.contains(c) { out.append(c) }
        }
        return out
    }

    // MARK: the CLI's answer

    public enum Outcome: Equatable, Sendable {
        /// `already`: Bridge had it on before (`already enabled: <path>`).
        case enabled(already: Bool)
        case failed(String)
    }

    /// Longest error text shown.
    static let maxMessage = 400

    /// From the exit status and the combined output. -1: the process did not start.
    public static func outcome(status: Int32, output: String) -> Outcome {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if status == 0 {
            return .enabled(already: lines.contains { $0.hasPrefix("already enabled: ") })
        }
        if status == -1 { return .failed("Couldn't start shelf-bridge. " + (lines.first ?? "")) }
        let prefix = cliName + ": "
        let text = lines.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return .failed("shelf-bridge stopped with status \(status).") }
        return .failed(text.count > maxMessage ? String(text.prefix(maxMessage)) + "\u{2026}" : text)
    }

    // MARK: paths

    static func trimmed(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func inside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }
}

/// The confirmation sheet's state, from the first look to the CLI's answer.
public enum EnableFolderPhase: Equatable, Sendable {
    /// The path can't be enabled.
    case invalid(EnableFolder.Problem)
    /// Bridge lists it already: nothing to do.
    case alreadyEnabled
    /// Ready to ask: Cancel or Enable.
    case confirm
    /// No CLI found: the command to run by hand.
    case manual
    case running
    case enabled(already: Bool)
    case failed(String)

    /// The first state: a problem wins, then a folder already on, then whether the CLI is there.
    public static func initial(check: EnableFolder.Check, folders: [String]?, cliFound: Bool) -> EnableFolderPhase {
        switch check {
        case .problem(let problem): return .invalid(problem)
        case .ok(let path):
            if EnableFolder.isEnabled(path, folders: folders) { return .alreadyEnabled }
            return cliFound ? .confirm : .manual
        }
    }

    public static func after(_ outcome: EnableFolder.Outcome) -> EnableFolderPhase {
        switch outcome {
        case .enabled(let already): .enabled(already: already)
        case .failed(let message): .failed(message)
        }
    }

    /// The line under the folder; nil while asking (the explanation shows instead).
    public var message: String? {
        switch self {
        case .invalid(let problem): problem.message
        case .alreadyEnabled: "shelf-bridge already reads this folder. Nothing to do."
        case .confirm: nil
        case .manual: "Shelf Bench can't find the shelf-bridge command. Run this in Terminal:"
        case .running: "Enabling\u{2026}"
        case .enabled(let already):
            already ? "shelf-bridge already read this folder." : "Enabled. shelf-bridge will list it in a moment."
        case .failed(let message): message
        }
    }

    public var tone: Tone {
        switch self {
        case .invalid, .failed: .rose
        case .enabled: .green
        case .alreadyEnabled, .confirm, .manual, .running: .muted
        }
    }

    /// The explanation of what enabling means shows while the choice is still open.
    public var showsExplanation: Bool {
        switch self {
        case .confirm, .manual, .running: true
        case .invalid, .alreadyEnabled, .enabled, .failed: false
        }
    }

    public var showsCommand: Bool { self == .manual }
    public var showsEnable: Bool { self == .confirm || self == .running }
    public var isRunning: Bool { self == .running }
    /// Cancel while a choice is open; Close while the CLI runs (closing does not stop it); Done
    /// once there is nothing left to choose.
    public var dismissTitle: String {
        switch self {
        case .confirm, .manual: "Cancel"
        case .running: "Close"
        case .invalid, .alreadyEnabled, .enabled, .failed: "Done"
        }
    }
}

/// What the sheet shows about the folder.
public struct EnableFolderRequest: Equatable, Sendable {
    /// The path as asked for (link or panel).
    public let requested: String
    public let check: EnableFolder.Check
    /// The folder, `~` for home; the resolved path when there is one.
    public let display: String
    /// The full path, for the tooltip.
    public let full: String
    /// "Resolved from ~/link" when the realpath differs from the path asked for.
    public let resolvedFrom: String?
    /// `shelf-bridge enable <path>`, for Terminal.
    public let command: String

    public init(requested: String, check: EnableFolder.Check, home: String) {
        self.requested = requested
        self.check = check
        let shown: String
        if case .ok(let path) = check { shown = path } else { shown = requested }
        full = shown
        display = BridgeSettings.abbreviate(shown, home: home)
        let asked = EnableFolder.trimmed(requested)
        resolvedFrom = (asked != shown && !asked.isEmpty) ? "Resolved from " + BridgeSettings.abbreviate(asked, home: home) : nil
        command = EnableFolder.command(shown)
    }

    public var path: String? { if case .ok(let p) = check { p } else { nil } }
}
