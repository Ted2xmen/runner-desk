import AppKit
import DeskCore
import Foundation
import ShelfRunnerCore

/// The `shelf-runner` command, for the one call Desk makes with it: `enable <folder>`, after
/// the user's yes. Argv, never a shell.
enum ShelfRunnerCLI {
    /// The first executable of: the binary the runner's LaunchAgent starts, `shelf-runner` on
    /// PATH or in the usual install places, the binary inside the ShelfRunner.app Launch Services
    /// knows. nil when none is there.
    static func locate(paths: Paths = .current()) -> String? {
        #if DEBUG
        // Debug builds only: a stand-in for tests and snapshots, so the real runner is never touched.
        if let fake = ProcessInfo.processInfo.environment["RUNNER_DESK_SHELF_RUNNER"], !fake.isEmpty {
            return FileManager.default.isExecutableFile(atPath: fake) ? fake : nil
        }
        #endif
        let plist = paths.home.appendingPathComponent("Library/LaunchAgents/\(EnableFolder.launchAgentLabel).plist")
        let agent = (try? Data(contentsOf: plist)).flatMap(EnableFolder.launchAgentProgram)
        let onPath = ExecutableLocator.find(EnableFolder.cliName, configured: nil, home: paths.home)
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: EnableFolder.bundleID)?.path
        return EnableFolder.candidates(launchAgent: agent, onPath: onPath, appBundle: app)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `shelf-runner enable <path>`; the environment is Desk's (the same `SHELF_RUNNER_HOME`).
    static func enable(_ path: String, executable: String) async -> EnableFolder.Outcome {
        let out = await TmuxRunner.run(executable: executable, EnableFolder.arguments(path), environment: TmuxRunner.environment())
        return EnableFolder.outcome(status: out.status, output: out.text)
    }

    /// The realpath of `path` and whether it is a folder; nil when it does not exist.
    static func resolve(_ path: String) -> (path: String, isDirectory: Bool)? {
        guard path.hasPrefix("/"), let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        let resolved = String(cString: real)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir) else { return nil }
        return (resolved, isDir.boolValue)
    }

    /// The checked request for a path asked for by a link or the folder panel.
    static func request(for requested: String) -> EnableFolderRequest {
        let home = NSHomeDirectory()
        let found = resolve(requested)
        let check = EnableFolder.check(requested: requested, resolved: found?.path, isDirectory: found?.isDirectory ?? false, home: home)
        return EnableFolderRequest(requested: requested, check: check, home: home)
    }
}
