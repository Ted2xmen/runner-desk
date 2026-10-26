import BenchCore
import SwiftUI

/// The work area, D1: header strip with Copy tmux command and Open in Terminal (no
/// Stop), the live terminal, or the result card and log, or a waiting card. Empty and
/// in-between states: opening, no jobs, no Bridge, nothing selected.
struct DetailView: View {
    let model: AppModel
    let narrow: Bool

    var body: some View {
        Group {
            if let id = model.selectedJob, let session = model.session(id) {
                SessionPage(model: model, session: session, narrow: narrow)
                    .id(id)
            } else if let id = model.selectedJob, BenchSessionName.isValid(id) {
                EmptyState(title: "Starting session…")
            } else if let id = model.selectedJob, let detail = model.selectedDetail, detail.id == id {
                JobPage(model: model, detail: detail, narrow: narrow)
                    .id(id)
            } else if let id = model.selectedJob {
                if model.link == .looking {
                    EmptyState(title: "Opening job \(id)…", line: "Looking for shelf-bridge…")
                } else {
                    EmptyState(title: "This job is no longer in Bridge's list.",
                               line: "Bridge keeps finished jobs for 24 hours. Its log may still be in the logs folder.",
                               buttonTitle: "Show logs folder", action: model.showLogsFolder)
                }
            } else {
                Placeholder(model: model)
            }
        }
        .background(Theme.panel)
    }
}

private struct Placeholder: View {
    let model: AppModel

    var body: some View {
        let m = model.sidebar
        if model.link != .looking, m.isBlank || (model.link == .absent && model.sessions.isEmpty) {
            if model.benchServer != nil {
                EmptyState(title: "Start your first session", sleeping: true,
                           line: "Pick a folder and an agent. The session runs in the background and goes on when Shelf Bench quits.",
                           buttonTitle: "New session", buttonIcon: .commandLine) { model.showsNewSession = true }
            } else {
                EmptyState(title: "Shelf Bench needs tmux", line: "Sessions run in tmux, out of sight.", mono: "brew install tmux")
            }
        } else {
            linkState
        }
    }

    @ViewBuilder private var linkState: some View {
        switch model.link {
        case .looking:
            EmptyState(title: "Looking for shelf-bridge…", line: "Reading heartbeat.json")
        case .absent:
            EmptyState(title: "Choose a session", sleeping: true, line: "A session opens its live terminal here.")
        case .unsupported:
            EmptyState(title: "Update shelf-bridge", line: "This Bridge speaks another protocol version than Shelf Bench.")
        case .connected, .offline:
            if model.sessions.isEmpty && model.sidebar.folders.allSatisfy({ $0.active.isEmpty && $0.finished.isEmpty }) {
                EmptyState(title: "No jobs yet", sleeping: true, line: "Jobs you hand to an agent in Shelf, or queue with shelf-bridge, show up here.")
            } else {
                EmptyState(title: "Choose a job", sleeping: true, line: "A running job opens its live terminal here.")
            }
        }
    }
}

private struct JobPage: View {
    let model: AppModel
    let detail: JobDetail
    let narrow: Bool

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model, detail: detail, narrow: narrow)
            if case .offline = model.link {
                Strip(text: "Bridge offline. The terminal still works: it is connected to tmux directly.", tone: .rose)
            }
            if model.link.isOnline, let job = model.job(detail.id), job.asking, JobPhase(state: job.state).isLive {
                Strip(text: "\(detail.agent) asks" + (job.now.map { ": “\($0)”" } ?? "") + " Answer in the terminal below.", tone: .amber)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch detail.body {
        case .terminal(let target):
            LiveTerminal(model: model, jobID: detail.id, target: target)
        case .noTarget:
            EmptyState(title: "No tmux window", line: "Bridge did not report a tmux window for this job.")
        case .result(let card):
            ResultPage(model: model, detail: detail, card: card)
        case .approval(let line):
            Card(title: "First run of this task", lines: [line, "Approve it in Shelf. It shows up in Running here once it starts."], tone: .amber)
        case .notSigned:
            Card(title: "Not signed. Use Queue again in Shelf.",
                 lines: ["In Shelf, Queue again writes the line again, signed; Take it back drops it."], tone: .amber)
        case .waiting(let reason, let soFar, let since):
            Card(title: reason, lines: [soFar, since].compactMap { $0 }, tone: .muted, icon: .clock)
        case .queued:
            Card(title: "Queued", lines: ["It starts when its turn comes."], tone: .muted, icon: .clock)
        case .unknown:
            Card(title: "Unknown", lines: ["Bridge is offline. This is the last state it reported."], tone: .muted)
        }
    }
}

/// One line over the work area, as high as the traffic lights' row: state chip, title, where
/// and who, then the actions.
private struct Header: View {
    let model: AppModel
    let detail: JobDetail
    let narrow: Bool

    var body: some View {
        HStack(spacing: Theme.Space.mid) {
            HStack(spacing: Theme.Space.row) {
                LabelChip(label: detail.label)
                Text(detail.title).font(Theme.Fonts.headerTitle).lineLimit(1)
                if detail.isFromShelf {
                    IconView(icon: .shelfMark, size: Theme.Metrics.shelfMarkTile)
                }
                Text(((detail.isFromShelf ? ["From Shelf"] : []) + [detail.source, detail.agent, detail.mode]).joined(separator: " \u{00B7} "))
                    .font(Theme.Fonts.headerMeta).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Space.mid)
            if let folder = model.job(detail.id)?.folder { EditorButtons(folder: folder) }
            if case .terminal(let target) = detail.body, model.tmux != nil, model.views[detail.id] != .closed {
                FramedButton(title: "Copy tmux command", icon: .copy, iconOnly: narrow) { model.copyTmuxCommand(target) }
                FramedButton(title: "Open in Terminal", icon: .openExternal, iconOnly: narrow) { model.openInTerminal(target) }
            }
        }
        .padding(.horizontal, Theme.Metrics.headerPaddingH)
        .frame(height: Theme.Metrics.titleBar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: Theme.Metrics.divider) }
    }
}

/// A Bench session: the header (state, "You · Claude", folder, actions), a shared-folder note,
/// then its live terminal, or once the agent exited the exit code with Restart and End.
private struct SessionPage: View {
    let model: AppModel
    let session: BenchSessionInfo
    let narrow: Bool

    var body: some View {
        // The label and title do not move with the clock; the running time is a ticking leaf.
        let row = SessionRow.make(session, asking: model.askingSessions.contains(session.id), now: session.created)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.mid) {
                HStack(spacing: Theme.Space.row) {
                    LabelChip(label: row.label)
                    Text(row.title).font(Theme.Fonts.headerTitle).lineLimit(1)
                    Ticking(active: true) { now in
                        let time = SessionRow.make(session, asking: false, now: now).time
                        Text((session.folder as NSString).abbreviatingWithTildeInPath + " \u{00B7} " + time)
                            .font(Theme.Fonts.headerMeta).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.head)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Theme.Space.mid)
                EditorButtons(folder: session.folder)
                if let server = model.benchServer {
                    if !session.isDead {
                        FramedButton(title: "Copy tmux command", icon: .copy, iconOnly: narrow) { server.copyCommand(session.id) }
                        FramedButton(title: "Open in Terminal", icon: .openExternal, iconOnly: narrow) { server.openInTerminal(session.id) }
                    }
                    FramedButton(title: "End session", icon: .failed, iconOnly: narrow) { model.requestEnd(session.id) }
                }
            }
            .padding(.horizontal, Theme.Metrics.headerPaddingH)
            .frame(height: Theme.Metrics.titleBar)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: Theme.Metrics.divider) }
            let others = model.sessions.filter { $0.folder == session.folder && $0.id != session.id && !$0.isDead }.count
            if let note = SessionWords.sharedFolder(otherSessions: others, bridgeJob: model.liveJob(in: session.folder)) {
                Strip(text: note, tone: .amber)
            }
            if session.isDead {
                let words = SessionWords.exited(session)
                VStack(alignment: .leading, spacing: Theme.Space.row) {
                    HStack(spacing: Theme.Space.row) {
                        IconView(icon: .alert).foregroundStyle(Theme.muted)
                        Text(words.title).font(Theme.Fonts.cardTitle)
                    }
                    Text(words.line).font(Theme.Fonts.cardLine).foregroundStyle(Theme.text2)
                    HStack(spacing: Theme.Space.row) {
                        ActionButton(title: "Restart") { model.restartSession(session.id) }
                        FramedButton(title: "End session", icon: .failed) { model.endSession(session.id) }
                    }
                    .padding(.top, Theme.Space.small)
                }
                .padding(Theme.Metrics.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let server = model.benchServer {
                TerminalPane(executable: server.server.executable, args: server.server.attach(session.id),
                             environment: BenchServerRunner.terminalEnvironment(),
                             onExit: { model.pollSessions() })
            }
        }
    }
}

/// The live job: a grouped view session in the embedded terminal, opened only on the job's
/// own window and closed when the job is deselected (`.onDisappear`).
private struct LiveTerminal: View {
    let model: AppModel
    let jobID: String
    let target: TmuxTarget

    var body: some View {
        // A container, not a Group: `onDisappear` on a Group would fire for each child it swaps.
        VStack(spacing: 0) {
            if let tmux = model.tmux {
                switch model.views[jobID] {
                case .ready(let name):
                    TerminalPane(executable: tmux.commands.executable, args: tmux.commands.openView(target, name: name),
                                 onExit: { model.viewExited(jobID: jobID) })
                case .closed:
                    Strip(text: "Finishing. The tmux window closed; the result shows here when Bridge reports it.", tone: .plain)
                    Spacer()
                case .preparing, .none:
                    OpeningWord()
                }
            } else {
                EmptyState(title: "tmux not found", line: "Set its path in ~/.config/shelf-bridge/config.toml under [tmux].")
            }
        }
        .task(id: jobID) { await model.prepareView(jobID: jobID, target: target) }
        .onDisappear { model.closeView(jobID: jobID) }
    }
}

/// Usually a few milliseconds: nothing at first, then a quiet word (not a spinner) only when
/// opening takes long enough to be seen.
private struct OpeningWord: View {
    @State private var shows = false

    var body: some View {
        Group {
            if shows {
                Text("Opening…")
                    .font(Theme.Fonts.emptyLine).foregroundStyle(Theme.muted)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: Theme.Timing.openingDelay)
            if !Task.isCancelled { shows = true }
        }
    }
}

/// A job without a terminal (first run, not signed, waiting, queued, unknown): an icon and a
/// title, then plain lines, on the work area itself.
private struct Card: View {
    let title: String
    let lines: [String]
    let tone: Tone
    var icon: BenchIcon = .alert

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            HStack(spacing: Theme.Space.row) {
                IconView(icon: icon).foregroundStyle(Theme.color(tone))
                Text(title).font(Theme.Fonts.cardTitle)
            }
            ForEach(lines, id: \.self) { Text($0).font(Theme.Fonts.cardLine).foregroundStyle(Theme.text2) }
        }
        .padding(Theme.Metrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// An ended job: the result on top, a hairline, then its log.
private struct ResultPage: View {
    let model: AppModel
    let detail: JobDetail
    let card: JobDetail.ResultCard
    @State private var log: FinishedLog.Lines?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    HStack(spacing: Theme.Space.row) {
                        IconView(icon: card.tone == .green ? .done : (card.tone == .rose ? .failed : .alert)).foregroundStyle(Theme.color(card.tone))
                        Text(card.title).font(Theme.Fonts.cardTitle)
                    }
                    ForEach([card.line, card.blocked, card.hint, card.out.map { "Output: \($0)" }].compactMap { $0 }, id: \.self) {
                        Text($0).font(Theme.Fonts.cardLine).foregroundStyle(Theme.text2)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if let log, !log.lines.isEmpty {
                    FramedButton(title: "Copy log", icon: .copy) { model.copy(log.lines.joined(separator: "\n")) }
                }
            }
            .padding(Theme.Metrics.pagePadding)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: Theme.Metrics.divider) }
            if let log, !log.lines.isEmpty {
                LogPane(log: log)
            } else if loaded {
                EmptyState(title: "No log", line: "~/Library/Logs/shelf-bridge has no log for this job.")
            }
        }
        .task(id: detail.id) {
            log = await model.loadLog(id: detail.id, attended: detail.isAttended)
            loaded = true
        }
    }
}
