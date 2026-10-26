import AppKit
import DeskCore
import SwiftUI

/// New session: a folder (the runner's enabled ones, recent ones, or another), an agent, Start.
/// The session is attended: it runs in front of the user, never unattended.
struct NewSessionSheet: View {
    let model: AppModel
    @State private var folder: String?
    @State private var agent: DeskAgent = .claude
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let folders = choices
        VStack(alignment: .leading, spacing: Theme.Space.mid) {
            Text("New session").font(Theme.Fonts.cardTitle)
            Text("FOLDER").font(Theme.Fonts.sectionCaps).tracking(Theme.Fonts.sectionCapsTracking).foregroundStyle(Theme.muted)
            ScrollView {
                VStack(spacing: Theme.Metrics.rowGap) {
                    ForEach(folders, id: \.path) { item in
                        FolderChoice(path: item.path, source: item.source, selected: folder == item.path) { folder = item.path }
                    }
                    if folders.isEmpty {
                        Text("No folders yet.").font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Metrics.rowPaddingH)
                    }
                }
            }
            .frame(height: Theme.Metrics.sheetList)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            FramedButton(title: "Choose another folder\u{2026}", icon: .folder) { chooseFolder() }
            Text("AGENT").font(Theme.Fonts.sectionCaps).tracking(Theme.Fonts.sectionCapsTracking).foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.small)
            Picker("Agent", selection: $agent) {
                ForEach(DeskAgent.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let folder, let note = note(for: folder) {
                Text(note).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.amber)
            }
            Text("The session runs in the background and goes on when Runner Desk quits.")
                .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    if let folder { model.newSession(folder: folder, agent: agent) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folder == nil)
            }
            .padding(.top, Theme.Space.small)
        }
        .padding(Theme.Metrics.pagePadding)
        .frame(width: Theme.Metrics.sheetWidth)
        .onAppear {
            if folder == nil { folder = model.newSessionFolder ?? choices.first?.path }
        }
        .onDisappear { model.newSessionFolder = nil }
    }

    /// The runner's folders, recent ones, and one just chosen.
    private var choices: [(path: String, source: String)] {
        var list = model.sessionFolders
        if let folder, !list.contains(where: { $0.path == folder }) { list.insert((folder, "chosen"), at: 0) }
        return list
    }

    private func note(for folder: String) -> String? {
        if let job = model.liveJob(in: folder) {
            return "Runner job running here: \(job). You can still start a session."
        }
        let others = model.sessions.filter { $0.folder == folder && !$0.isDead }.count
        return others > 0 ? "Another session is running here. Two agents may edit the same files." : nil
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

private struct FolderChoice: View {
    let path: String
    let source: String
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Space.small) {
                IconView(icon: .folder, size: Theme.Metrics.markerIcon).foregroundStyle(Theme.icon)
                    .frame(width: Theme.Metrics.marker)
                Text((path as NSString).lastPathComponent).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.text)
                Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(Theme.Fonts.rowMeta).foregroundStyle(Theme.muted).truncationMode(.head)
                Spacer(minLength: Theme.Space.tight)
                Text(source).font(Theme.Fonts.rowMono).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .padding(.horizontal, Theme.Metrics.rowPaddingH)
            .frame(height: Theme.Metrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.rowSelected : (hovering ? Theme.rowHover : Color.clear),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(path)
        .accessibilityLabel("\((path as NSString).lastPathComponent), \(source)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
