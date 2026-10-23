import AppKit
import DeskCore
import Foundation
import Observation
import ShelfRunnerCore

/// The app's one model. It holds what was heard and chosen; every word and grouping comes
/// from DeskCore (`SidebarBuilder`, `DetailBuilder`, `LinkRule`). It owns the tmux views'
/// lives: open on select, close on deselect, on quit, and when a view stops showing its job.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// A grouped view session for one job.
    enum ViewState: Equatable {
        case preparing
        case ready(name: String)
        /// The job's window is gone (or never was): "Finishing" until the result comes.
        case closed
    }

    /// How often open views are probed: a view that no longer shows its job is closed.
    static let probeSeconds: TimeInterval = 2

    let paths = Paths.current()
    let tmux = TmuxRunner.resolve()
    let launchedAt = Date()

    private(set) var latest: StatusRead?
    private(set) var heartbeatExists = false
    private(set) var now = Date()
    private(set) var views: [String: ViewState] = [:]
    var selectedJob: String?
    /// Folders whose "Show all (N)" is open.
    var expanded: Set<String> = []

    @ObservationIgnored private var feed: StatusFeed?
    @ObservationIgnored private var timers: [Timer] = []

    private init() {}

    // MARK: derived (DeskCore)

    var status: StatusV1? { if case .status(let s) = latest { s } else { nil } }

    var link: RunnerLink {
        LinkRule.derive(latest: latest, heartbeatExists: heartbeatExists, launchedAt: launchedAt, now: now)
    }

    var sidebar: SidebarModel { SidebarBuilder.build(status: status, link: link, now: now, expanded: expanded) }

    func job(_ id: String) -> StatusV1.Job? { status?.jobs.first { $0.id == id } }

    func detail(_ id: String) -> JobDetail? {
        job(id).map { DetailBuilder.build($0, online: link.isOnline, now: now) }
    }

    // MARK: life

    func start() {
        DeskFiles.sweepAttachScripts(keep: [])
        let feed = StatusFeed(paths: paths) { [weak self] reading, exists in self?.ingest(reading, heartbeatExists: exists) }
        self.feed = feed
        feed.start()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: Self.probeSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.probeViews() }
            },
        ]
    }

    func becameActive() { feed?.ping() }

    /// Quitting: close every view Desk opened (group-size check, `=` targets); the runner's
    /// `shelf-*` sessions and their jobs go on.
    func closeAllViewsNow() {
        guard let tmux else { return }
        for case .ready(let name) in views.values { tmux.closeViewNow(name) }
        views = [:]
    }

    private func tick() {
        now = Date()
        updateDockBadge()
    }

    private func ingest(_ reading: StatusRead?, heartbeatExists exists: Bool) {
        heartbeatExists = exists
        if let reading { latest = StatusReader.newer(latest, reading) }
        now = Date()
        let live = Set((status?.jobs ?? []).filter { JobPhase(state: $0.state).isLive }.map(\.id))
        DeskFiles.sweepAttachScripts(keep: live)
        // A job that ended has no terminal any more: its view (if any) is closed by tmux with it.
        for id in views.keys where !live.contains(id) && status != nil { forget(id) }
        updateDockBadge()
    }

    private func updateDockBadge() {
        let count = sidebar.askingCount
        let label = count > 0 ? "\(count)" : nil
        if NSApp.dockTile.badgeLabel != label { NSApp.dockTile.badgeLabel = label }
    }

    // MARK: URL

    func open(_ url: URL) {
        guard let id = DeskURL.jobID(url) else { return }
        selectedJob = id
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: views

    /// Opens a view only on the job's own live window, under a free name.
    func prepareView(jobID: String, target: TmuxTarget) async {
        guard let tmux else { return }
        if case .ready = views[jobID] { return }
        views[jobID] = .preparing
        guard await tmux.jobWindowAlive(target) else {
            if views[jobID] == .preparing { views[jobID] = .closed }
            return
        }
        let name = await tmux.freeViewName(for: jobID)
        guard selectedJob == jobID, views[jobID] == .preparing else { return }
        views[jobID] = .ready(name: name)
    }

    /// Deselect: close the view; the job goes on in tmux.
    func closeView(jobID: String) {
        if case .ready(let name) = views[jobID], let tmux { Task { await tmux.closeView(name) } }
        views[jobID] = nil
    }

    /// The tmux client in the pane exited: the window closed (the job is finishing) or the
    /// view was closed under it.
    func viewExited(jobID: String) {
        if case .ready = views[jobID] { views[jobID] = .closed }
    }

    private func forget(_ jobID: String) {
        if case .ready(let name) = views[jobID], let tmux { Task { await tmux.closeView(name) } }
        views[jobID] = nil
    }

    /// Every open view, selected or not: when it no longer shows its job's window
    /// (the window closed and tmux moved the view to another job's), close it before a key
    /// reaches the wrong agent.
    private func probeViews() {
        guard let tmux else { return }
        for (jobID, state) in views {
            guard case .ready(let name) = state else { continue }
            Task {
                guard await !tmux.viewShowsJob(name, jobID: jobID) else { return }
                guard self.views[jobID] == .ready(name: name) else { return }
                self.views[jobID] = .closed
                await tmux.closeView(name)
            }
        }
    }

    // MARK: actions without the runner (D1: no Stop, Run, Retry)

    func copyTmuxCommand(_ target: TmuxTarget) {
        guard let tmux else { return }
        TerminalHandoff.copy(tmux.commands, target: target)
    }

    func openInTerminal(_ target: TmuxTarget) {
        guard let tmux else { return }
        TerminalHandoff.openInTerminal(tmux.commands, target: target)
    }

    /// The install line of the "no runner" footer (the tap's cask name may still change).
    static let runnerInstall = "brew install --cask ted2xmen/tap/shelf-runner"

    func copy(_ text: String) { TerminalHandoff.copy(text: text) }

    func loadLog(id: String, attended: Bool) async -> FinishedLog.Lines? {
        await LogReader.load(id: id, attended: attended, paths: paths)
    }

    func showLogsFolder() {
        let dir = paths.logsDir
        if FileManager.default.fileExists(atPath: dir.path) { NSWorkspace.shared.open(dir) }
    }
}
