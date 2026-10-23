import DeskCore
import SwiftUI

/// The sidebar: connection line, Needs you, folders with jobs, Scheduled, then
/// This Mac and limits at the bottom; without a runner the "no runner" footer instead.
struct SidebarView: View {
    let model: AppModel
    let narrow: Bool

    var body: some View {
        let m = model.sidebar
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Theme.Metrics.windowControlsRow)
            LogoRow()
            ConnectionRow(line: m.connection)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if m.isLooking {
                        SkeletonRows()
                    } else {
                        if !m.needsYou.isEmpty {
                            SectionTitle(text: "Needs you", count: m.needsYou.count, tone: .amber)
                            ForEach(m.needsYou) { row in
                                JobRowView(row: row, short: false, selected: model.selectedJob == row.id) { model.selectedJob = row.id }
                            }
                        }
                        ForEach(m.folders) { folder in
                            FolderView(folder: folder, selected: model.selectedJob,
                                       select: { model.selectedJob = $0 },
                                       toggle: { toggle(folder.id) })
                        }
                        if !narrow && !m.scheduled.isEmpty {
                            SectionTitle(text: "Scheduled", count: nil, tone: .muted)
                            ForEach(m.scheduled) { ScheduledRowView(row: $0) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.row)
                .padding(.bottom, Theme.Metrics.sidebarPadding)
            }
            if m.showsRunnerFooter {
                RunnerAbsentFooter(copy: model.copy)
            } else if !m.mac.isEmpty {
                MacFooter(cells: m.mac, limits: m.limits)
            }
        }
        .background(Theme.bg)
    }

    private func toggle(_ id: String) {
        if model.expanded.contains(id) { model.expanded.remove(id) } else { model.expanded.insert(id) }
    }
}

private struct LogoRow: View {
    var body: some View {
        HStack(spacing: Theme.Space.mid) {
            IconView(icon: .commandLine, size: Theme.Metrics.logoGlyph)
                .foregroundStyle(Theme.onAccent)
                .frame(width: Theme.Metrics.logo, height: Theme.Metrics.logo)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.logo))
            Text("Runner Desk").font(Theme.Fonts.logo)
        }
        .padding(.horizontal, Theme.Metrics.sidebarPadding)
        .padding(.bottom, Theme.Space.mid)
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionRow: View {
    let line: ConnectionLine

    var body: some View {
        let (text, tone): (String?, Tone) = switch line {
        case .looking: ("Looking for shelf-runner…", .muted)
        case .connected(let t): (t, .green)
        case .offline(let t): (t, .rose)
        case .unsupported(let t): (t, .amber)
        case .none: (nil, .muted)
        }
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.small) {
                StateDot(tone: tone)
                Text(text).font(Theme.Fonts.connection).foregroundStyle(Theme.text2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metrics.sidebarPadding)
            .padding(.bottom, Theme.Space.mid)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    let count: Int?
    let tone: Tone

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Text(text).font(Theme.Fonts.section).foregroundStyle(tone == .amber ? Theme.amber : Theme.muted)
            if let count { Text("\(count)").font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, Theme.Space.row)
        .padding(.top, Theme.Space.section)
        .padding(.bottom, Theme.Space.small)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct FolderView: View {
    let folder: FolderSection
    let selected: String?
    let select: (String) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.small) {
                IconView(icon: .folder, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
                Text(folder.name).font(Theme.Fonts.section).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.row)
            .padding(.top, Theme.Space.section)
            .padding(.bottom, Theme.Space.small)
            .help(folder.id)
            .accessibilityAddTraits(.isHeader)
            ForEach(folder.active + folder.finished) { row in
                JobRowView(row: row, short: row.needsYou, selected: selected == row.id) { select(row.id) }
            }
            if folder.active.isEmpty && folder.finished.isEmpty {
                Text("No jobs in the last 24 hours").font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.Metrics.rowPaddingH)
                    .padding(.vertical, Theme.Space.tight)
            }
            if folder.showsFinishedToggle {
                Button(action: toggle) {
                    Text(folder.isExpanded ? "Show fewer" : "Show all (\(folder.finishedTotal))")
                        .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.text2)
                        .padding(.horizontal, Theme.Metrics.rowPaddingH)
                        .frame(minHeight: Theme.Metrics.hitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A job row: title and time; label · agent; one mono line of `now`. `short`: a Needs you job
/// in its folder, title and dot only.
struct JobRowView: View {
    let row: JobRow
    let short: Bool
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
                StateDot(tone: row.label.tone, ringed: row.isAsking)
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(Theme.Fonts.jobCardTitle).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: Theme.Space.tight)
                        if !short, let time = row.time {
                            Text(time).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
                        }
                    }
                    if !short {
                        Text("\(row.label.text) · \(row.agent)").font(Theme.Fonts.rowMeta)
                            .foregroundStyle(Theme.color(row.label.tone)).lineLimit(1)
                        if let now = row.now {
                            Text(now).font(Theme.Fonts.rowNow).foregroundStyle(Theme.text2).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.jobCardPaddingH)
            .padding(.vertical, Theme.Metrics.jobCardPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.sel : Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.jobCard))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.jobCard)
                    .strokeBorder(selected ? Theme.icon : Theme.line2,
                                  lineWidth: selected ? Theme.Metrics.jobCardBorderSelected : Theme.Metrics.jobCardBorder)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.jobCard))
        }
        .buttonStyle(.plain)
        .padding(.bottom, Theme.Metrics.jobCardGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(row.label.text), \(row.agent)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ScheduledRowView: View {
    let row: ScheduledRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            IconView(icon: .clock, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(row.title).font(Theme.Fonts.rowTitle).lineLimit(1)
                Text([row.next, row.agent].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.vertical, Theme.Metrics.rowPaddingV)
        .accessibilityElement(children: .combine)
    }
}

/// Opening: grey rows while Desk looks for the runner.
private struct SkeletonRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.mid) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .fill(Theme.line)
                    .frame(width: i % 2 == 0 ? Theme.Metrics.skeletonLong : Theme.Metrics.skeletonShort, height: Theme.Metrics.skeletonRow)
            }
        }
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.top, Theme.Space.section)
        .accessibilityLabel("Looking for shelf-runner")
    }
}

/// This Mac and the agent limits; limits only with data and online.
private struct MacFooter: View {
    let cells: [MacCell]
    let limits: [AgentLimits]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            Text("This Mac").font(Theme.Fonts.section).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Theme.Space.tight) {
                ForEach(cells) { cell in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cell.name).font(Theme.Fonts.footer).foregroundStyle(Theme.muted)
                        Text(cell.value).font(Theme.Fonts.footer).foregroundStyle(Theme.color(cell.tone)).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            ForEach(limits) { agent in
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text(agent.agent).font(Theme.Fonts.section)
                    ForEach(agent.bars) { bar in LimitBarView(bar: bar) }
                    Text(agent.source).font(Theme.Fonts.footer).foregroundStyle(Theme.muted)
                }
                .padding(.top, Theme.Space.tight)
            }
        }
        .padding(Theme.Metrics.sidebarPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

private struct LimitBarView: View {
    let bar: LimitBar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            HStack {
                Text(bar.window).font(Theme.Fonts.footer).foregroundStyle(Theme.text2)
                Spacer()
                Text("\(bar.percent) %").font(Theme.Fonts.footer).foregroundStyle(Theme.color(bar.tone))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(bar.tone == .plain ? Theme.text : Theme.color(bar.tone))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, bar.percent))) / 100)
                }
            }
            .frame(height: Theme.Metrics.limitBar)
            if let resets = bar.resets { Text(resets).font(Theme.Fonts.footer).foregroundStyle(Theme.muted) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.window) \(bar.percent) percent" + (bar.resets.map { ", \($0)" } ?? ""))
    }
}

/// No runner: one non-blocking line; the brew command can be copied.
private struct RunnerAbsentFooter: View {
    static let install = AppModel.runnerInstall
    let copy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text("Autonomous jobs need shelf-runner · install").font(Theme.Fonts.footer).foregroundStyle(Theme.text2)
            HStack(spacing: Theme.Space.small) {
                Text(Self.install).font(Theme.Fonts.footerMono).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Button { copy(Self.install) } label: {
                    IconView(icon: .copy, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
                        .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")
                .accessibilityLabel("Copy install command")
            }
        }
        .padding(Theme.Metrics.sidebarPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
