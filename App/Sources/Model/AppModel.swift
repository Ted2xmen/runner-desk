import AppKit
import BenchCore
import Foundation
import Observation
import ShelfBridgeCore

/// The app's one model. It holds what was heard and chosen; every word and grouping comes
/// from BenchCore (`SidebarBuilder`, `DetailBuilder`, `LinkRule`). It owns the tmux views'
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
    /// The clock's step: `now`, and the leaf views that write ages.
    static let clockSeconds: TimeInterval = 1

    let paths = Paths.current()
    let tmux = TmuxRunner.resolve()
    /// Bench's own tmux server for Bench sessions; nil without tmux.
    let benchServer = BenchServerRunner.resolve()
    let launchedAt = Date()

    // Inputs of the derived values below: each change rebuilds them (`refresh`).
    private(set) var latest: StatusRead? { didSet { refresh() } }
    private(set) var heartbeatExists = false { didSet { refresh() } }
    /// The clock, ticked every second. Views do not read it: the derived values are rebuilt from
    /// it and only notify when what they show changed; seconds-level text lives in leaf views.
    private(set) var now = Date() { didSet { refresh() } }
    private(set) var views: [String: ViewState] = [:]
    var selectedJob: String? { didSet { refresh() } }
    /// Where the selection was made: a job or session in Needs you is also under its folder,
    /// and only the copy that was clicked shows selected.
    var selectedPlace: SelectionPlace = .folder

    enum SelectionPlace: Equatable { case needsYou, folder }

    func select(_ id: String, in place: SelectionPlace) {
        selectedJob = id
        selectedPlace = place
    }

    func isSelected(_ id: String, in place: SelectionPlace) -> Bool { selectedJob == id && selectedPlace == place }

    /// Selection from outside the sidebar (a URL, a notification): the Needs you copy when there
    /// is one, since the folder copy may sit behind "Show all" or a folded folder.
    func reveal(_ id: String) {
        let m = sidebar
        let inNeedsYou = m.needsYou.contains { $0.id == id } || m.askingSessions.contains { $0.id == id }
        select(id, in: inNeedsYou ? .needsYou : .folder)
    }
    /// Folders whose "Show all (N)" is open.
    var expanded: Set<String> = [] { didSet { refresh() } }
    /// Folders folded shut in the sidebar (their jobs hidden).
    var collapsed: Set<String> = []

    /// Bench's own sessions, as the server last reported them.
    private(set) var sessions: [BenchSessionInfo] = [] { didSet { refresh() } }
    /// Sessions found asking on their screen.
    private(set) var askingSessions: Set<String> = [] { didSet { refresh() } }
    /// Folders Bench opened sessions in, newest first.
    private(set) var recents: [String] = RecentFolders.load() { didSet { refresh() } }
    /// The Shelf app is open (debug and release builds share one bundle id).
    private(set) var shelfRunning = false { didSet { refresh() } }
    nonisolated static let shelfBundleIDs: Set<String> = ["dev.ted2xmen.shelf"]
    var showsNewSession = false
    /// The folder New session opens with (a folder header's "+"); nil: the first offered.
    var newSessionFolder: String?
    /// A session whose End waits for the user's yes.
    var confirmingEnd: String?
    /// Bumped by every start, end and restart: a poll begun before it is dropped.
    @ObservationIgnored private var mutation = 0
    /// Per session: the activity time of the last screen look.
    @ObservationIgnored private var lookedAt: [String: Date] = [:]
    @ObservationIgnored private var polling = false
    /// A poll was asked for while one ran.
    @ObservationIgnored private var pollAgain = false

    @ObservationIgnored private var feed: StatusFeed?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    /// Set while several inputs change together: one `refresh` at the end instead of one each.
    @ObservationIgnored private var holdingRefresh = false

    private init() { rebuild() }

    // MARK: derived (BenchCore)

    var status: StatusV2? { if case .status(let s) = latest { s } else { nil } }

    // Stored, not computed: rebuilt by `refresh` and set whole, so an unchanged value (the
    // usual case on a clock tick) notifies nobody.
    private(set) var link: BridgeLink = .looking
    private(set) var sidebar = SidebarModel()
    /// The selected Bridge job's work area; nil when the selection is not a job in the status.
    private(set) var selectedDetail: JobDetail?

    /// Rebuilds the derived values from their inputs: `latest`, `heartbeatExists`, `now`,
    /// `expanded`, `sessions`, `askingSessions`, `recents`, `shelfRunning`, `selectedJob` (each calls
    /// it on change).
    private func refresh() {
        guard !holdingRefresh else { return }
        rebuild()
        updateDockBadge()
    }

    private func rebuild() {
        link = LinkRule.derive(latest: latest, heartbeatExists: heartbeatExists, launchedAt: launchedAt, now: now)
        sidebar = SidebarBuilder.build(status: status, link: link, now: now, expanded: expanded,
                                       sessions: sessions, asking: askingSessions, recents: recents,
                                       shelfRunning: shelfRunning)
        selectedDetail = selectedJob.flatMap { job($0) }.map { DetailBuilder.build($0, online: link.isOnline, now: now) }
    }

    /// Changes several inputs with one rebuild.
    private func batched(_ body: () -> Void) {
        holdingRefresh = true
        body()
        holdingRefresh = false
        refresh()
    }

    func session(_ id: String) -> BenchSessionInfo? { sessions.first { $0.id == id } }

    func job(_ id: String) -> StatusV2.Job? { status?.jobs.first { $0.id == id } }

    // MARK: life

    func start() {
        BenchFiles.sweepAttachScripts(keep: [])
        let feed = StatusFeed(paths: paths) { [weak self] reading, exists in self?.ingest(reading, heartbeatExists: exists) }
        self.feed = feed
        feed.start()
        watchShelf()
        timers = [
            Timer.scheduledTimer(withTimeInterval: Self.clockSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: Self.probeSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.probeViews()
                    self?.pollSessions()
                }
            },
        ]
        if let benchServer {
            Task {
                await benchServer.prepare()
                self.pollSessions()
            }
        }
    }

    func becameActive() { feed?.ping() }

    /// Shelf's launches and quits, from the workspace's notifications (no polling).
    private func watchShelf() {
        updateShelfRunning()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let app, let id = app.bundleIdentifier, Self.shelfBundleIDs.contains(id) else { return }
                // The one quitting may still be listed while its notification is delivered.
                let quitting = note.name == NSWorkspace.didTerminateApplicationNotification ? app.processIdentifier : nil
                MainActor.assumeIsolated { self?.updateShelfRunning(except: quitting) }
            }
        }
    }

    private func updateShelfRunning(except quitting: pid_t? = nil) {
        let running = NSWorkspace.shared.runningApplications.contains { app in
            app.processIdentifier != quitting && !app.isTerminated && app.bundleIdentifier.map(Self.shelfBundleIDs.contains) == true
        }
        if shelfRunning != running { shelfRunning = running }
    }

    /// Quitting: close every view Bench opened (group-size check, `=` targets); Bridge's
    /// `shelf-*` sessions and their jobs go on.
    func closeAllViewsNow() {
        guard let tmux else { return }
        for case .ready(let name) in views.values { tmux.closeViewNow(name) }
        views = [:]
    }

    /// `now`'s `didSet` rebuilds the derived values (and the Dock badge).
    private func tick() {
        now = Date()
    }

    private func ingest(_ reading: StatusRead?, heartbeatExists exists: Bool) {
        batched {
            heartbeatExists = exists
            if let reading { latest = StatusReader.newer(latest, reading) }
            now = Date()
        }
        let live = Set((status?.jobs ?? []).filter { JobPhase(state: $0.state).isLive }.map(\.id))
        BenchFiles.sweepAttachScripts(keep: live.union(sessions.map(\.id)))
        // A job that ended has no terminal any more: its view (if any) is closed by tmux with it.
        for id in views.keys where !live.contains(id) && status != nil { forget(id) }
    }

    private func updateDockBadge() {
        let count = sidebar.askingCount
        let label = count > 0 ? "\(count)" : nil
        if NSApp.dockTile.badgeLabel != label { NSApp.dockTile.badgeLabel = label }
    }

    // MARK: URL

    func open(_ url: URL) {
        if let link = BenchURL.enableLink(url) {
            switch link {
            case .path(let path): askToEnable(path, from: .link)
            case .malformed: askToEnable(nil, from: .link)
            }
            return
        }
        guard let id = BenchURL.jobID(url) else { return }
        reveal(id)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: enabling a folder in shelf-bridge

    /// The confirmation sheet for one folder: a link opens it on the Bench window, Settings'
    /// "Add folder…" on the Settings window.
    struct EnableSheet: Identifiable, Equatable {
        enum Origin: Equatable { case link, settings }

        let id = UUID()
        let origin: Origin
        let request: EnableFolderRequest
        /// The CLI found when the sheet opened; nil: the command is shown to copy.
        let executable: String?
        var phase: EnableFolderPhase
    }

    var enableSheet: EnableSheet?

    /// Always asks: nothing is enabled before the user says yes. `path` nil: a link without a usable path.
    func askToEnable(_ path: String?, from origin: EnableSheet.Origin) {
        if enableSheet?.phase.isRunning == true { return }
        let request = path.map(ShelfBridgeCLI.request) ?? EnableFolderRequest(requested: "", check: .problem(.malformedLink), home: NSHomeDirectory())
        let executable = request.path == nil ? nil : ShelfBridgeCLI.locate(paths: paths)
        let phase = EnableFolderPhase.initial(check: request.check, folders: status?.folders, cliFound: executable != nil)
        if origin == .link {
            // One sheet at a time on the Bench window.
            showsNewSession = false
            confirmingEnd = nil
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
        }
        enableSheet = EnableSheet(origin: origin, request: request, executable: executable, phase: phase)
    }

    /// Enable, after the user's yes: runs the CLI once and shows its answer.
    func confirmEnable() {
        guard var sheet = enableSheet, sheet.phase == .confirm, let path = sheet.request.path, let executable = sheet.executable else { return }
        sheet.phase = .running
        enableSheet = sheet
        let id = sheet.id
        Task {
            let outcome = await ShelfBridgeCLI.enable(path, executable: executable)
            guard self.enableSheet?.id == id else { return }
            self.enableSheet?.phase = EnableFolderPhase.after(outcome)
            if case .enabled = outcome { self.feed?.ping() }
        }
    }

    func dismissEnableSheet() { enableSheet = nil }

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
    /// reaches the wrong agent. One `list-sessions` on Bridge's server answers for every view
    /// (each view's current window); a view missing from it, or a failed call, is closed.
    private func probeViews() {
        guard let tmux else { return }
        let open = views.compactMap { jobID, state -> (jobID: String, name: String)? in
            if case .ready(let name) = state { (jobID, name) } else { nil }
        }
        guard !open.isEmpty else { return }
        Task {
            let out = await tmux.run(tmux.commands.currentWindows())
            let windows = out.status == 0 ? TmuxReply.currentWindows(out.text) : [:]
            for view in open where !TmuxReply.showsJob(windows[view.name] ?? "", jobID: view.jobID) {
                guard self.views[view.jobID] == .ready(name: view.name) else { continue }
                self.views[view.jobID] = .closed
                Task { await tmux.closeView(view.name) }
            }
        }
    }

    // MARK: Bench sessions

    /// Reads the server's sessions, then looks for questions on quiet, changed screens. A request
    /// while a poll runs is not dropped: one more pass runs right after.
    func pollSessions() {
        guard let benchServer else { return }
        guard !polling else {
            pollAgain = true
            return
        }
        polling = true
        Task {
            repeat {
                pollAgain = false
                await pollOnce(benchServer)
            } while pollAgain
            polling = false
        }
    }

    private func pollOnce(_ benchServer: BenchServerRunner) async {
        let started = mutation
        // A failed call (not "no server") keeps the sessions and the selection as they were.
        guard let list = await benchServer.list(), started == mutation else { return }
        if list != sessions { sessions = list }
        let now = Date()
        var asking = askingSessions.intersection(list.filter { !$0.isDead && now.timeIntervalSince($0.activity) >= SessionAsking.quiet }.map(\.id))
        let due = list.filter { SessionAsking.shouldCapture($0, lastLookedAt: lookedAt[$0.id], now: now) }
        for s in due { lookedAt[s.id] = s.activity }
        let screens = await withTaskGroup(of: (String, String?).self, returning: [String: String].self) { group in
            for s in due { group.addTask { (s.id, await benchServer.capture(s.id)) } }
            var out: [String: String] = [:]
            for await (id, screen) in group { out[id] = screen }
            return out
        }
        for s in due {
            guard let screen = screens[s.id] else { continue }
            if SessionAsking.isAsking(screen, s, now: now) { asking.insert(s.id) } else { asking.remove(s.id) }
        }
        lookedAt = lookedAt.filter { id, _ in list.contains { $0.id == id } }
        guard started == mutation else { return }
        batched {
            askingSessions = asking
            if let id = selectedJob, BenchSessionName.isValid(id), !list.contains(where: { $0.id == id }) { selectedJob = nil }
        }
    }

    /// A folder header's "+": New session with that folder chosen.
    func startNewSession(in folder: String) {
        newSessionFolder = folder
        showsNewSession = true
    }

    func newSession(folder: String, agent: BenchAgent) {
        guard let benchServer else { return }
        var g = SystemRandomNumberGenerator()
        let name = BenchSessionName.make(using: &g)
        mutation += 1
        recents = RecentFolders.adding(folder, to: recents)
        RecentFolders.save(recents)
        Task {
            guard await benchServer.start(name: name, folder: folder, agent: agent) else { return }
            self.mutation += 1
            let list = await benchServer.list()
            self.batched {
                if let list { self.sessions = list }
                self.select(name, in: .folder)
            }
        }
    }

    /// End: asks first when something other than an idle shell runs in it.
    func requestEnd(_ id: String) {
        guard let s = session(id) else { return }
        if s.endNeedsConfirmation(shell: BenchServerRunner.loginShell) { confirmingEnd = id } else { endSession(id) }
    }

    func endSession(_ id: String) {
        guard let benchServer, BenchSessionName.isValid(id) else { return }
        confirmingEnd = nil
        mutation += 1
        batched {
            sessions.removeAll { $0.id == id }
            askingSessions.remove(id)
            if selectedJob == id { selectedJob = nil }
        }
        Task {
            await benchServer.kill(id)
            self.mutation += 1
            if let list = await benchServer.list() { self.sessions = list }
        }
    }

    func restartSession(_ id: String) {
        guard let benchServer else { return }
        mutation += 1
        Task {
            await benchServer.respawn(id)
            self.mutation += 1
            if let list = await benchServer.list() { self.sessions = list }
        }
    }

    /// A live Bridge job in this folder (for the shared-folder note).
    func liveJob(in folder: String) -> String? {
        status?.jobs.first { $0.folder == folder && JobPhase(state: $0.state).isLive }?.id
    }

    /// Folders New session offers: Bridge's enabled folders, then recent ones.
    var sessionFolders: [(path: String, source: String)] {
        var out: [(String, String)] = (status?.folders ?? []).map { ($0, "bridge") }
        for f in recents where !out.contains(where: { $0.0 == f }) { out.append((f, "recent")) }
        return out
    }

    // MARK: actions without Bridge (D1: no Stop, Run, Retry)

    func copyTmuxCommand(_ target: TmuxTarget) {
        guard let tmux else { return }
        TerminalHandoff.copy(tmux.commands, target: target)
    }

    func openInTerminal(_ target: TmuxTarget) {
        guard let tmux else { return }
        TerminalHandoff.openInTerminal(tmux.commands, target: target)
    }

    /// The install line of the "no Bridge" footer (the tap's cask name may still change).
    static let bridgeInstall = "brew install --cask ted2xmen/tap/shelf-bridge"

    func copy(_ text: String) { TerminalHandoff.copy(text: text) }

    func loadLog(id: String, attended: Bool) async -> FinishedLog.Lines? {
        await LogReader.load(id: id, attended: attended, paths: paths)
    }

    func showLogsFolder() {
        let dir = paths.logsDir
        if FileManager.default.fileExists(atPath: dir.path) { NSWorkspace.shared.open(dir) }
    }
}
