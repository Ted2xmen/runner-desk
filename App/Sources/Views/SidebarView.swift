import BenchCore
import SwiftUI

/// The sidebar is a list of jobs and Bench sessions, nothing else: New session in the traffic
/// lights' row, Needs you, folders that fold (sessions first, then Bridge jobs), Scheduled. Each
/// job and session shows once. Connection, This Mac and limits live in the status bar.
struct SidebarView: View {
    let model: AppModel
    let narrow: Bool

    var body: some View {
        let m = model.sidebar
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights' row, New session at its right end.
            HStack {
                Spacer()
                NewSessionButton(enabled: model.benchServer != nil) { model.newSessionFolder = nil; model.showsNewSession = true }
            }
            .padding(.horizontal, Theme.Metrics.sidebarListInset)
            .frame(height: Theme.Metrics.titleBar)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if m.isLooking {
                        SkeletonRows()
                    } else {
                        if !m.needsYou.isEmpty || !m.askingSessions.isEmpty {
                            SectionTitle(text: "Needs you", count: m.needsYou.count + m.askingSessions.count, tone: .amber)
                            ForEach(m.askingSessions) { row in
                                SessionRowView(row: row, inNeedsYou: true, selected: model.isSelected(row.id, in: .needsYou),
                                               select: { model.select(row.id, in: .needsYou) }, end: { model.requestEnd(row.id) })
                            }
                            ForEach(m.needsYou) { row in
                                JobRowView(row: row, inNeedsYou: true, selected: model.isSelected(row.id, in: .needsYou)) {
                                    model.select(row.id, in: .needsYou)
                                }
                            }
                        }
                        ForEach(m.folders) { folder in
                            FolderView(folder: folder, collapsed: model.collapsed.contains(folder.id),
                                       selected: model.selectedPlace == .folder ? model.selectedJob : nil,
                                       select: { model.select($0, in: .folder) }, end: { model.requestEnd($0) },
                                       fold: { toggle(&model.collapsed, folder.id) },
                                       showAll: { toggle(&model.expanded, folder.id) },
                                       newSession: model.benchServer == nil ? nil : { model.startNewSession(in: folder.id) })
                        }
                        if !narrow && !m.scheduled.isEmpty {
                            SectionTitle(text: "Scheduled", count: m.scheduled.count, tone: .muted)
                            ForEach(m.scheduled) { ScheduledRowView(row: $0) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.sidebarListInset)
                .padding(.bottom, Theme.Metrics.sidebarPadding)
            }
        }
        .background(Theme.bg)
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

/// A section title: small letter-spaced caps and a count.
private struct SectionTitle: View {
    let text: String
    let count: Int
    let tone: Tone

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Text(text.uppercased())
                .font(Theme.Fonts.sectionCaps)
                .tracking(Theme.Fonts.sectionCapsTracking)
                .foregroundStyle(tone == .amber ? Theme.amber : Theme.muted)
            Text("\(count)").font(Theme.Fonts.rowMono).foregroundStyle(Theme.muted)
                .accessibilityLabel(count == 1 ? "1 job" : "\(count) jobs")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.top, Theme.Space.mid)
        .padding(.bottom, Theme.Space.tight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A folder: a header that folds it (chevron, name, count), then its jobs.
private struct FolderView: View {
    let folder: FolderSection
    let collapsed: Bool
    let selected: String?
    let select: (String) -> Void
    let end: (String) -> Void
    let fold: () -> Void
    let showAll: () -> Void
    /// New session in this folder; nil without tmux.
    let newSession: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: fold) {
                HStack(spacing: Theme.Space.small) {
                    IconView(icon: collapsed ? .chevronRight : .chevronDown, size: Theme.Metrics.markerIcon)
                        .foregroundStyle(Theme.icon)
                        .frame(width: Theme.Metrics.badge)
                    Text(folder.name.uppercased())
                        .font(Theme.Fonts.sectionCaps).tracking(Theme.Fonts.sectionCapsTracking)
                        .foregroundStyle(Theme.muted)
                        .truncationMode(.middle)
                    Text("\(folder.sessions.count + folder.active.count + folder.finishedTotal)").font(Theme.Fonts.rowMono).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .padding(.horizontal, Theme.Metrics.rowPaddingH)
                .frame(height: Theme.Metrics.rowHeight)
                .modifier(RowGround(selected: false))
            }
            .buttonStyle(.plain)
            .help(folder.id)
            .accessibilityLabel("\(folder.name), \(collapsed ? "folded" : "open")")
            .accessibilityAddTraits(.isHeader)
            // Editors and New session here: shown while the header is hovered, over its right end.
            .overlay(alignment: .trailing) {
                if hovering {
                    HStack(spacing: Theme.Space.hair) {
                        EditorButtons(folder: folder.id, size: Theme.Metrics.markerIcon + Theme.Space.tight)
                        if let newSession { plusButton(newSession) }
                    }
                    .padding(.trailing, Theme.Space.tight)
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                if let newSession { Button("New Session Here\u{2026}", action: newSession) }
                ForEach(Editors.installed) { editor in
                    Button("Open in \(editor.title)") { Editors.open(folder.id, in: editor) }
                }
            }
            .accessibilityAction(named: "New session here") { newSession?() }
            .padding(.top, Theme.Space.mid)
            if !collapsed {
                ForEach(folder.sessions) { row in
                    SessionRowView(row: row, inNeedsYou: false, selected: selected == row.id,
                                   select: { select(row.id) }, end: { end(row.id) })
                }
                ForEach(folder.active + folder.finished) { row in
                    JobRowView(row: row, inNeedsYou: false, selected: selected == row.id) { select(row.id) }
                }
                if let empty = folder.emptyLine {
                    Text(empty).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
                        .padding(.leading, Theme.Metrics.rowPaddingH + Theme.Metrics.badge + Theme.Space.mid)
                        .frame(height: Theme.Metrics.rowHeight)
                }
                if folder.showsFinishedToggle {
                    Button(action: showAll) {
                        Text(folder.isExpanded ? "Show fewer" : "Show all (\(folder.finishedTotal))")
                            .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
                            .padding(.leading, Theme.Metrics.rowPaddingH + Theme.Metrics.badge + Theme.Space.mid)
                            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.rowHeight, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func plusButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: Theme.Metrics.markerIcon, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: Theme.Metrics.stopButton, height: Theme.Metrics.stopButton)
                .background(Theme.badge, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New session in \(folder.name)")
        .accessibilityLabel("New session in \(folder.name)")
    }
}

/// The ground every sidebar row shares: a fill when selected or hovered, never an edge.
private struct RowGround: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.rowSelected : (hovering ? Theme.rowHover : Color.clear),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
            .onHover { hovering = $0 }
            .padding(.bottom, Theme.Metrics.rowGap)
    }
}

/// A job: the agent's badge; the title, and under it the state and the time (in Needs you also
/// the folder), the live `now` as a third line; the state glyph at the right.
struct JobRowView: View {
    let row: JobRow
    let inNeedsYou: Bool
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Space.mid) {
                AgentBadge(mark: row.mark, dimmed: row.phase.isEnded, fromShelf: row.isFromShelf)
                VStack(alignment: .leading, spacing: Theme.Space.hair) {
                    // An ended job is history: its title steps back a tone.
                    Text(row.title).font(Theme.Fonts.rowTitle)
                        .foregroundStyle(row.phase.isEnded ? Theme.text2 : Theme.text)
                    (Text(row.label.text).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.color(row.label.tone))
                        + Text(meta).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted))
                    if let now = row.now {
                        Text("\u{203A} " + now).font(Theme.Fonts.rowNow).foregroundStyle(Theme.text2)
                    }
                }
                Spacer(minLength: Theme.Space.tight)
                StateGlyph(state: glyph)
            }
            .lineLimit(1)
            .padding(.horizontal, Theme.Metrics.rowPaddingH)
            .padding(.vertical, Theme.Metrics.itemPaddingV)
            .frame(minHeight: Theme.Metrics.itemMinHeight)
            .modifier(RowGround(selected: selected))
        }
        .buttonStyle(.plain)
        .help("\(row.label.text) \u{00B7} \(row.agent)" + (row.isFromShelf ? " \u{00B7} From Shelf" : ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(row.label.text), \(row.agent)" + (row.isFromShelf ? ", from Shelf" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// " · 4 min", " · 14:02", and in Needs you " · SHELF-TEST".
    private var meta: String {
        var parts: [String] = []
        if let time = row.time { parts.append(time) }
        if inNeedsYou { parts.append(SidebarBuilder.folderName(row.folder)) }
        return parts.map { " \u{00B7} " + $0 }.joined()
    }

    private var glyph: StateGlyph.State {
        if row.isAsking { return .asking }
        switch row.phase {
        case .running: return .working
        case .stalled, .needsApproval: return .attention
        case .waiting(let reason): return reason == "signature" ? .attention : .waiting
        case .queued: return .waiting
        case .done: return .done
        case .failed: return .failed
        case .cancelled, .missed: return .stopped
        case .unknown: return .idle(.muted)
        }
    }
}

/// The agent's mark on a small tile: Claude's mark in its orange, Codex's in ink, a terminal for
/// a shell.
struct AgentBadge: View {
    let mark: AgentMark
    var dimmed = false
    /// Shelf's mark on the corner: the job came from Shelf.
    var fromShelf = false

    var body: some View {
        Group {
            switch mark {
            case .claude:
                IconView(icon: .agentClaude, size: Theme.Metrics.badgeIcon).foregroundStyle(Theme.claude)
            case .codex:
                IconView(icon: .agentCodex, size: Theme.Metrics.badgeIcon).foregroundStyle(Theme.text)
            case .shell:
                IconView(icon: .commandLine, size: Theme.Metrics.badgeIcon).foregroundStyle(Theme.text2)
            case .other:
                Circle().fill(Theme.icon).frame(width: Theme.Metrics.dot, height: Theme.Metrics.dot)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .frame(width: Theme.Metrics.badge, height: Theme.Metrics.badge)
        .background(Theme.badge, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .overlay(alignment: .bottomTrailing) {
            if fromShelf {
                IconView(icon: .shelfMark, size: Theme.Metrics.shelfMark)
                    .frame(width: Theme.Metrics.shelfMarkTile, height: Theme.Metrics.shelfMarkTile)
                    .background(Theme.bg, in: Circle())
                    .offset(x: Theme.Space.tight, y: Theme.Space.tight)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The state at the right of a row: spinning while it works, a ringed amber dot when it asks,
/// a check, a cross, a stop square, a clock.
struct StateGlyph: View {
    enum State: Equatable {
        case working, asking, attention, waiting, done, failed, stopped
        case idle(Tone)
    }

    let state: State

    var body: some View {
        Group {
            switch state {
            case .working:
                ProgressView().controlSize(.small).scaleEffect(0.7)
            case .asking:
                StateDot(tone: .amber, ringed: true)
            case .attention:
                StateDot(tone: .amber)
            case .waiting:
                IconView(icon: .clock, size: Theme.Metrics.stateGlyph).foregroundStyle(Theme.muted)
            case .done:
                IconView(icon: .done, size: Theme.Metrics.stateGlyph).foregroundStyle(Theme.green)
            case .failed:
                IconView(icon: .failed, size: Theme.Metrics.stateGlyph).foregroundStyle(Theme.red)
            case .stopped:
                Image(systemName: "stop.circle").font(.system(size: Theme.Metrics.stateGlyph)).foregroundStyle(Theme.muted)
            case .idle(let tone):
                StateDot(tone: tone)
            }
        }
        .frame(width: Theme.Metrics.stateColumn, height: Theme.Metrics.badge)
        .accessibilityHidden(true)
    }
}

/// A Bench session: the agent's badge; "You · Claude", and under it its word and time (in Needs
/// you also the folder); at the right spinning while it works, a dot when idle, the stop square
/// once it exited. On hover the right end turns into Stop (End session, which asks first when
/// something still runs).
private struct SessionRowView: View {
    let row: SessionRow
    let inNeedsYou: Bool
    let selected: Bool
    let select: () -> Void
    let end: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.mid) {
            AgentBadge(mark: row.mark, dimmed: row.isDead)
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(row.title).font(Theme.Fonts.rowTitle).foregroundStyle(row.isDead ? Theme.text2 : Theme.text)
                (Text(row.label.text).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.color(row.label.tone))
                    + Text(" \u{00B7} " + row.time + (inNeedsYou ? " \u{00B7} " + SidebarBuilder.folderName(row.folder) : ""))
                        .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted))
            }
            Spacer(minLength: Theme.Space.tight)
            if hovering {
                Button(action: end) {
                    Image(systemName: "stop.fill").font(.system(size: Theme.Metrics.stateGlyph * 0.7))
                        .foregroundStyle(Theme.text2)
                        .frame(width: Theme.Metrics.stopButton, height: Theme.Metrics.stopButton)
                        .background(Theme.badge, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                        .frame(width: Theme.Metrics.stateColumn)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("End session")
                .accessibilityLabel("End session")
            } else {
                StateGlyph(state: row.isDead ? .stopped : row.isAsking ? .asking : row.isWorking ? .working : .idle(.green))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.vertical, Theme.Metrics.itemPaddingV)
        .frame(minHeight: Theme.Metrics.itemMinHeight)
        .modifier(RowGround(selected: selected))
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .help(row.label.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.label.text), \(row.time)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "End session", end)
    }
}

/// "+" in the traffic lights' row: New session (Cmd-N). Off without tmux.
private struct NewSessionButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .resizable()
                .scaledToFit()
                .frame(width: Theme.Metrics.iconSmall, height: Theme.Metrics.iconSmall)
                .foregroundStyle(enabled ? (hovering ? Theme.text : Theme.icon) : Theme.muted)
                .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.hitTarget)
                .background(hovering && enabled ? Theme.rowHover : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? "New session (\u{2318}N)" : "Shelf Bench needs tmux: brew install tmux")
        .accessibilityLabel("New session")
    }
}

private struct ScheduledRowView: View {
    let row: ScheduledRow

    var body: some View {
        HStack(spacing: Theme.Space.mid) {
            IconView(icon: .clock, size: Theme.Metrics.markerIcon).foregroundStyle(Theme.icon)
                .frame(width: Theme.Metrics.badge)
            Text(row.title).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.text2)
            Spacer(minLength: Theme.Space.tight)
            if let next = row.next { Text(next).font(Theme.Fonts.rowMono).foregroundStyle(Theme.muted).fixedSize() }
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .frame(height: Theme.Metrics.rowHeight)
        .help(row.agent)
        .accessibilityElement(children: .combine)
    }
}

/// Opening: grey rows while Bench looks for Bridge.
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
        .accessibilityLabel("Looking for shelf-bridge")
    }
}
