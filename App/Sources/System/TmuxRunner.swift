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
        guard let path = executable(paths: paths) else { return nil }
        return TmuxRunner(commands: TmuxCommands(executable: path, socket: config.tmuxSocket, configuredPath: config.tmuxPath != nil))
    }

    /// The tmux Desk runs: `config.toml [tmux] path`, else the usual places.
    static func executable(paths: Paths = .current()) -> String? {
        let config = (try? Config.load(from: paths.configFile)) ?? Config()
        return ExecutableLocator.find("tmux", configured: config.tmuxPath, home: paths.home)
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
        await Self.run(executable: commands.executable, args, environment: Self.environment())
    }

    /// One tmux call off the main thread: argv, never a shell; stdout and stderr together.
    /// The pipe is drained while the child runs (a full 64 KB pipe buffer would block it forever);
    /// the call returns once both EOF and exit have happened.
    static func run(executable: String, _ args: [String], environment: [String: String]) async -> Output {
        await withCheckedContinuation { continuation in
            let join = RunJoin(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { p in join.exited(p.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                join.failed("\(error)")
                return
            }
            let reader = pipe.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                join.read(reader.readDataToEndOfFile())
            }
        }
    }

    /// Resumes the continuation exactly once, after both the output's EOF and the exit status are in.
    private final class RunJoin: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Output, Never>?
        private var data: Data?
        private var status: Int32?

        init(_ continuation: CheckedContinuation<Output, Never>) { self.continuation = continuation }

        func read(_ data: Data) { finish { $0.data = data } }

        func exited(_ status: Int32) { finish { $0.status = status } }

        func failed(_ message: String) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: Output(status: -1, text: message))
        }

        private func finish(_ update: (RunJoin) -> Void) {
            lock.lock()
            update(self)
            guard let data, let status, let c = continuation else { lock.unlock(); return }
            continuation = nil
            lock.unlock()
            c.resume(returning: Output(status: status, text: String(decoding: data, as: UTF8.self)))
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
