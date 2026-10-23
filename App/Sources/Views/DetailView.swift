import DeskCore
import SwiftUI

/// The work area, D1: header strip with Copy tmux command and Open in Terminal (no
/// Stop), the live terminal, or the result card and log, or a waiting card. Empty and
/// in-between states: opening, no jobs, no runner, nothing selected.
struct DetailView: View {
    let model: AppModel
    let narrow: Bool

    var body: some View {
        Group {
            if let id = model.selectedJob, let detail = model.detail(id) {
                JobPage(model: model, detail: detail, narrow: narrow)
                    .id(id)
            } else if let id = model.selectedJob {
                if model.link == .looking {
                    EmptyState(title: "Opening job \(id)…", line: "Looking for shelf-runner…")
                } else {
                    EmptyState(title: "This job is no longer in the runner's list.",
                               line: "The runner keeps finished jobs for 24 hours. Its log may still be in the logs folder.",
                               buttonTitle: "Show logs folder", action: model.showLogsFolder)
                }
            } else {
                Placeholder(model: model)
            }
        }
        .background(Theme.bg)
    }
}

private struct Placeholder: View {
    let model: AppModel

    var body: some View {
        switch model.link {
        case .looking:
            EmptyState(title: "Looking for shelf-runner…", line: "Reading heartbeat.json")
        case .absent:
            EmptyState(title: "No runner jobs here", line: "Autonomous jobs need shelf-runner. Desk shows its jobs and their terminals once it runs.",
                       mono: AppModel.runnerInstall)
        case .unsupported:
            EmptyState(title: "Update shelf-runner", line: "This runner speaks another protocol version than Runner Desk.")
        case .connected, .offline:
            if model.sidebar.folders.allSatisfy({ $0.active.isEmpty && $0.finished.isEmpty }) {
                EmptyState(title: "No jobs yet", line: "Jobs you hand to an agent in Shelf, or queue with shelf-runner, show up here.")
            } else {
                EmptyState(title: "Choose a job", line: "A running job opens its live terminal here.")
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
                Strip(text: "Runner offline. The terminal still works: it is connected to tmux directly.", tone: .rose)
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
            EmptyState(title: "No tmux window", line: "The runner did not report a tmux window for this job.")
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
            Card(title: "Unknown", lines: ["The runner is offline. This is the last state it reported."], tone: .muted)
        }
    }
}

private struct Header: View {
    let model: AppModel
    let detail: JobDetail
    let narrow: Bool

    var body: some View {
        HStack(spacing: Theme.Metrics.gap) {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                Text(detail.title).font(Theme.Fonts.headerTitle).lineLimit(1)
                HStack(spacing: Theme.Space.small) {
                    LabelChip(label: detail.label)
                    Text([detail.source, detail.agent, detail.mode].joined(separator: " · "))
                        .font(Theme.Fonts.headerMeta).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Metrics.gap)
            if case .terminal(let target) = detail.body, model.tmux != nil, model.views[detail.id] != .closed {
                FramedButton(title: "Copy tmux command", icon: .copy, iconOnly: narrow) { model.copyTmuxCommand(target) }
                FramedButton(title: "Open in Terminal", icon: .openExternal, iconOnly: narrow) { model.openInTerminal(target) }
            }
        }
        .padding(.horizontal, Theme.Metrics.pagePadding)
        .frame(height: Theme.Metrics.header)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
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
                    Strip(text: "Finishing. The tmux window closed; the result shows here when the runner reports it.", tone: .plain)
                    Spacer()
                case .preparing, .none:
                    Color.clear
                }
            } else {
                EmptyState(title: "tmux not found", line: "Set its path in ~/.config/shelf-runner/config.toml under [tmux].")
            }
        }
        .task(id: jobID) { await model.prepareView(jobID: jobID, target: target) }
        .onDisappear { model.closeView(jobID: jobID) }
    }
}

private struct Card: View {
    let title: String
    let lines: [String]
    let tone: Tone
    var icon: DeskIcon = .alert

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            HStack(spacing: Theme.Space.row) {
                IconView(icon: icon).foregroundStyle(Theme.color(tone))
                Text(title).font(Theme.Fonts.cardTitle)
            }
            ForEach(lines, id: \.self) { Text($0).font(Theme.Fonts.cardLine).foregroundStyle(Theme.text2) }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.line2))
        .padding(Theme.Metrics.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

/// An ended job: the result card, then its log.
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
            .padding(Theme.Metrics.cardPadding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.line2))
            .padding(Theme.Metrics.pagePadding)
            if let log, !log.lines.isEmpty {
                LogPane(log: log)
            } else if loaded {
                EmptyState(title: "No log", line: "~/Library/Logs/shelf-runner has no log for this job.")
            }
        }
        .task(id: detail.id) {
            log = await model.loadLog(id: detail.id, attended: detail.isAttended)
            loaded = true
        }
    }
}
