import DeskCore
import Foundation
import ShelfRunnerCore

/// Runs tmux control commands (probe, group size, kill) as argv, never through a shell
/// (argv arrays, `=` on every target). The tmux path and socket are the runner's (`config.toml [tmux]`),
/// so both talk to the same server.
struct TmuxRunner: Sendable {
    let commands: TmuxCommands

    /// nil when tmux is not found (Desk then shows jobs without a terminal).
    static func resolve(paths: Paths = .current()) -> TmuxRunner? {
        let config = (try? Config.load(from: paths.configFile)) ?? Config()
        guard let path = ExecutableLocator.find("tmux", configured: config.tmuxPath, home: paths.home) else { return nil }
        return TmuxRunner(commands: TmuxCommands(executable: path, socket: config.tmuxSocket, configuredPath: config.tmuxPath != nil))
    }

    struct Output: Sendable {
        let status: Int32
        let text: String
    }

    /// The child's environment: Desk's own minus `TMUX` (Desk may be started from inside tmux).
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TMUX"] = nil
        env["TMUX_PANE"] = nil
        return env
    }

    func run(_ args: [String]) async -> Output {
        let executable = commands.executable
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = Self.environment()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Output(status: p.terminationStatus, text: String(decoding: data, as: UTF8.self)))
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: Output(status: -1, text: "\(error)"))
            }
        }
    }

    /// For quitting: the app is going away, there is no later.
    func runNow(_ args: [String]) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: commands.executable)
        process.arguments = args
        process.environment = Self.environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Output(status: -1, text: "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }

    // MARK: views

    /// The job's window is still there, named by its id: the probe the runner uses (`windowAlive`).
    func jobWindowAlive(_ target: TmuxTarget) async -> Bool {
        let out = await run(commands.jobWindow(target))
        return out.status == 0 && TmuxReply.showsJob(out.text, jobID: target.window)
    }

    /// `view-<id>`, or a suffixed name when one is still there (an orphan last member).
    func freeViewName(for jobID: String) async -> String {
        let plain = ViewName.view(jobID)
        if await run(commands.hasSession(plain)).status != 0 { return plain }
        var g = SystemRandomNumberGenerator()
        return ViewName.view(jobID, suffix: ViewName.suffix(using: &g))
    }

    func viewShowsJob(_ view: String, jobID: String) async -> Bool {
        let out = await run(commands.windowProbe(view))
        return out.status == 0 && TmuxReply.showsJob(out.text, jobID: jobID)
    }

    /// Kills a view only while another group member holds the job windows: killing the last member would take them with it.
    /// Desk never kills a `shelf-*` session: only names it made.
    func closeView(_ view: String) async {
        guard view.hasPrefix("view-") else { return }
        let size = TmuxReply.groupSize(await run(commands.groupSize(view)).text)
        if TmuxReply.mayKill(groupSize: size) { _ = await run(commands.killSession(view)) }
    }

    func closeViewNow(_ view: String) {
        guard view.hasPrefix("view-") else { return }
        let size = TmuxReply.groupSize(runNow(commands.groupSize(view)).text)
        if TmuxReply.mayKill(groupSize: size) { _ = runNow(commands.killSession(view)) }
    }
}
