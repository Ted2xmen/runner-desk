import DeskCore
import SwiftUI

/// The window-wide status bar, one mono line like tmux's: Settings, the shelf-runner state and the
/// Shelf pairing at the left; This Mac and the agent limits pushed to the right. A click on This Mac or the limits opens the full figures.
/// Narrow: only the segments that are not fine. Without a runner: the install line.
struct StatusBar: View {
    let model: AppModel
    let narrow: Bool
    @State private var showsDetails = false

    var body: some View {
        let m = model.sidebar
        HStack(spacing: 0) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Theme.Metrics.icon, height: Theme.Metrics.icon)
                    .foregroundStyle(Theme.icon)
                    .frame(width: Theme.Metrics.statusBar, height: Theme.Metrics.statusBar)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            Separator()
            connection(m.connection)
            if let pairing = m.pairing {
                Separator()
                // Room goes to the runner, This Mac and the limits first.
                PairingSegment(line: pairing).layoutPriority(-1)
            }
            Spacer(minLength: Theme.Space.mid)
            if m.showsRunnerFooter {
                RunnerAbsent(copy: model.copy)
            } else if !m.mac.isEmpty {
                Button { showsDetails.toggle() } label: {
                    HStack(spacing: 0) {
                        ForEach(Array(macCells(m.mac).enumerated()), id: \.element.id) { index, cell in
                            if index > 0 { Separator() }
                            Segment(name: cell.name.lowercased(), value: cell.value, tone: cell.tone)
                        }
                        ForEach(m.limits) { agent in
                            Separator()
                            LimitsSegment(agent: agent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("This Mac and agent limits")
                .popover(isPresented: $showsDetails, arrowEdge: .top) {
                    DetailsPopover(cells: m.mac, limits: m.limits)
                }
            }
        }
        .font(Theme.Fonts.status)
        .lineLimit(1)
        .padding(.leading, Theme.Space.tight)
        .padding(.trailing, Theme.Metrics.statusBarPaddingH)
        .frame(height: Theme.Metrics.statusBar)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: Theme.Metrics.divider) }
    }

    /// Narrow: a fine value says nothing; only the others stay.
    private func macCells(_ cells: [MacCell]) -> [MacCell] {
        narrow ? cells.filter { $0.tone != .plain } : cells
    }

    /// The runner's state, tinted; its version, heartbeat age and slots live in the tooltip, which
    /// alone redraws with the clock.
    private func connection(_ line: ConnectionLine) -> some View {
        Ticking(active: line.showsAge) { now in
            HStack(spacing: Theme.Space.small) {
                IconView(icon: .runner, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.color(line.tone))
                Text(line.text).foregroundStyle(line.tone == .green ? Theme.text2 : Theme.color(line.tone))
            }
            .frame(height: Theme.Metrics.statusBar)
            .contentShape(Rectangle())
            .help(line.help(now: now))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.accessibilityLabel)
        }
    }
}

/// A leaf that redraws with the clock, alone: ages ("12 s ago") are written here, not in the
/// model, so the bar and the sidebar do not re-render every second. Inactive: drawn once.
struct Ticking<Content: View>: View {
    let active: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if active {
            TimelineView(.periodic(from: .now, by: AppModel.clockSeconds)) { context in content(context.date) }
        } else {
            content(Date())
        }
    }
}

/// Shelf's mark and how far the pairing is proven; Shelf open or not, the newest job from Shelf
/// and its age live in the tooltip, which alone redraws with the clock. Only a pairing proven by a
/// job from Shelf shows the mark in color and the text in ink; a bare key or none is muted.
private struct PairingSegment: View {
    let line: PairingLine

    var body: some View {
        Ticking(active: line.showsAge) { now in
            // Short of room (a narrow window with This Mac warnings), the mark alone stays.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.small) {
                    mark
                    Text(line.text).foregroundStyle(Theme.color(line.tone))
                }
                mark
            }
            .frame(height: Theme.Metrics.statusBar)
            .contentShape(Rectangle())
            .help(line.help(now: now))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.accessibilityLabel(now: now))
        }
    }

    private var mark: some View {
        IconView(icon: .shelfMark, size: Theme.Metrics.iconSmall, monochrome: !line.isPaired)
            .foregroundStyle(Theme.muted)
    }
}

/// A thin vertical rule between segments.
private struct Separator: View {
    var body: some View {
        Rectangle().fill(Theme.line2).frame(width: Theme.Metrics.divider, height: Theme.Metrics.iconSmall)
            .padding(.horizontal, Theme.Space.mid)
            .accessibilityHidden(true)
    }
}

/// "memory Low": the name muted, the value in its tone.
private struct Segment: View {
    let name: String
    let value: String
    let tone: Tone

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Text(name).foregroundStyle(Theme.muted)
            Text(value).foregroundStyle(tone == .plain ? Theme.text2 : Theme.color(tone))
        }
        .accessibilityElement(children: .combine)
    }
}

/// "claude 5h 34% wk 61%".
private struct LimitsSegment: View {
    let agent: AgentLimits

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Text(agent.agent.lowercased()).foregroundStyle(Theme.muted)
            ForEach(agent.bars) { bar in
                Text(bar.short).foregroundStyle(Theme.muted)
                Text("\(bar.percent)%").foregroundStyle(bar.tone == .plain ? Theme.text2 : Theme.color(bar.tone))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.agent) limits, " + agent.bars.map { "\($0.window) \($0.percent) percent" }.joined(separator: ", "))
    }
}

/// No runner: the install line and a copy button.
private struct RunnerAbsent: View {
    let copy: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Text("Autonomous jobs need shelf-runner").foregroundStyle(Theme.text2)
            Text(AppModel.runnerInstall).foregroundStyle(Theme.muted).truncationMode(.middle).textSelection(.enabled)
            Button { copy(AppModel.runnerInstall) } label: {
                IconView(icon: .copy, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
                    .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.statusBar)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
            .accessibilityLabel("Copy install command")
        }
    }
}

/// The full figures behind the status bar: This Mac, then each agent's limit bars with their
/// resets and source.
private struct DetailsPopover: View {
    let cells: [MacCell]
    let limits: [AgentLimits]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.mid) {
            Text("THIS MAC").font(Theme.Fonts.sectionCaps).tracking(Theme.Fonts.sectionCapsTracking).foregroundStyle(Theme.muted)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.section, verticalSpacing: Theme.Space.tight) {
                ForEach(cells) { cell in
                    GridRow {
                        Text(cell.name).foregroundStyle(Theme.muted)
                        Text(cell.value).foregroundStyle(cell.tone == .plain ? Theme.text : Theme.color(cell.tone))
                    }
                    .font(Theme.Fonts.footer)
                }
            }
            ForEach(limits) { agent in
                Rectangle().fill(Theme.line).frame(height: Theme.Metrics.divider)
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.agent).font(Theme.Fonts.section)
                    Spacer()
                    Ticking(active: agent.at != nil) { now in
                        Text(agent.sourceLine(now: now)).font(Theme.Fonts.footer).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(agent.bars) { bar in LimitBarView(bar: bar) }
            }
        }
        .padding(Theme.Metrics.sidebarPadding)
        .frame(width: Theme.Metrics.popoverWidth)
    }
}

private struct LimitBarView: View {
    let bar: LimitBar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            HStack {
                Text(bar.window).font(Theme.Fonts.footer).foregroundStyle(Theme.text2)
                if let resets = bar.resets { Text(resets).font(Theme.Fonts.footer).foregroundStyle(Theme.muted) }
                Spacer()
                Text("\(bar.percent) %").font(Theme.Fonts.status).foregroundStyle(bar.tone == .plain ? Theme.text : Theme.color(bar.tone))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(bar.tone == .plain ? Theme.text : Theme.color(bar.tone))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, bar.percent))) / 100)
                }
            }
            .frame(height: Theme.Metrics.limitBar)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.window) \(bar.percent) percent" + (bar.resets.map { ", \($0)" } ?? ""))
    }
}
