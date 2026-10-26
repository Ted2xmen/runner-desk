import AppKit
import BenchCore
import SwiftUI

/// The Settings window (Cmd+,): the appearance choice, Bridge as the status bar sees it
/// (read-only), and the app's name and version.
struct SettingsView: View {
    let model: AppModel
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.SettingsPane.sectionGap) {
            SettingsSection(title: "Appearance") {
                HStack {
                    Text("Theme")
                        .font(Theme.SettingsFonts.rowTitle)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Theme.SettingsPane.pickerWidth)
                }
            }

            BridgeSection(settings: BridgeSettings.derive(sidebar: model.sidebar, status: model.status, home: NSHomeDirectory()),
                          copy: model.copy, addFolder: chooseFolder)

            Text(Self.aboutLine)
                .font(Theme.SettingsFonts.about)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.SettingsPane.padding)
        .frame(width: Theme.SettingsPane.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.bg)
        .onChange(of: appearance) { _, choice in choice.apply() }
        .enableFolderSheet(model, origin: .settings)
    }

    /// "Add folder…": a folder from the panel, then the same confirmation as a link.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for shelf-bridge to read."
        if panel.runModal() == .OK, let url = panel.url { model.askToEnable(url.path, from: .settings) }
    }

    private static var aboutLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Shelf Bench"
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(name) \(version) (\($0))" } ?? "\(name) \(version)"
    }
}

/// shelf-bridge's state, the Shelf pairing and the folders Bridge reads. Without Bridge's
/// status only the state and its hint show.
private struct BridgeSection: View {
    let settings: BridgeSettings
    let copy: (String) -> Void
    let addFolder: () -> Void

    var body: some View {
        SettingsSection(title: "Bridge") {
            status
            if let pairing = settings.pairing {
                SettingsDivider()
                pairingRow(pairing)
            }
            if let folders = settings.folders {
                SettingsDivider()
                foldersRow(folders)
            }
        }
    }

    private var status: some View {
        let line = settings.connection
        return VStack(alignment: .leading, spacing: Theme.SettingsPane.lineGap) {
            SettingsRowHeader(title: "Status") {
                IconView(icon: .bridge, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.color(line.tone))
                Text(line.text).foregroundStyle(line.tone == .green ? Theme.text2 : Theme.color(line.tone))
            }
            Ticking(active: line.showsAge) { now in
                let facts = settings.statusLines.prefix(1) + [line.ageLine(now: now)].compactMap { $0 }
                if !facts.isEmpty { SettingsLine(facts.joined(separator: " \u{00B7} ")) }
            }
            ForEach(settings.statusLines.dropFirst(), id: \.self) { SettingsLine($0) }
            if let paused = settings.pausedLine { SettingsLine(paused, tone: .amber) }
            if let note = settings.statusNote { SettingsLine(note) }
            if let command = settings.statusCommand {
                SettingsCommandRow(command: command.text ?? AppModel.bridgeInstall, copy: copy)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pairingRow(_ pairing: PairingLine) -> some View {
        VStack(alignment: .leading, spacing: Theme.SettingsPane.lineGap) {
            SettingsRowHeader(title: "Shelf pairing") {
                IconView(icon: .shelfMark, size: Theme.Metrics.iconSmall, monochrome: !pairing.isPaired)
                    .foregroundStyle(Theme.muted)
                Text(pairing.text).foregroundStyle(pairing.isPaired ? Theme.text2 : Theme.muted)
            }
            if let keyId = pairing.keyId {
                HStack(spacing: Theme.Space.small) {
                    Text("Bridge key").foregroundStyle(Theme.muted)
                    Text(keyId).font(Theme.SettingsFonts.mono).foregroundStyle(Theme.text2).textSelection(.enabled)
                }
                .font(Theme.SettingsFonts.rowNote)
                .accessibilityElement(children: .combine)
            }
            SettingsLine(pairing.shelfLine)
            Ticking(active: pairing.showsAge) { now in SettingsLine(pairing.lastJobLine(now: now)) }
            if let unsigned = pairing.unsignedLine { SettingsLine(unsigned, tone: .amber) }
            if let note = settings.pairingNote { SettingsLine(note, tone: pairing.isPaired ? .muted : .plain) }
            if let command = settings.pairingCommand?.text { SettingsCommandRow(command: command, copy: copy) }
        }
        .accessibilityElement(children: .contain)
    }

    private func foldersRow(_ folders: [SettingsFolderRow]) -> some View {
        VStack(alignment: .leading, spacing: Theme.SettingsPane.lineGap) {
            SettingsRowHeader(title: "Folders") {
                if !folders.isEmpty { Text("\(folders.count)").foregroundStyle(Theme.muted) }
            }
            if let empty = settings.emptyFolders {
                SettingsLine(empty.title, tone: .plain)
                SettingsLine(empty.hint)
                SettingsCommandRow(command: empty.command.text ?? "", copy: copy)
            } else {
                ForEach(folders) { folder in
                    HStack(spacing: Theme.Space.mid) {
                        Text(folder.display)
                            .font(Theme.SettingsFonts.mono)
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.id)
                        Spacer(minLength: Theme.Space.mid)
                        Text(folder.detail)
                            .font(Theme.SettingsFonts.rowNote)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(folder.id + ", " + folder.detail)
                }
            }
            FramedButton(title: "Add folder\u{2026}", icon: .folder, action: addFolder)
                .padding(.leading, -Theme.Space.row)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A titled white card with a hairline edge.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            Text(title)
                .font(Theme.SettingsFonts.section)
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: Theme.SettingsPane.rowGap) { content }
                .padding(Theme.SettingsPane.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.line, lineWidth: Theme.SettingsPane.border))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: Theme.SettingsPane.border)
    }
}

/// A row's title, with its state at the trailing edge.
private struct SettingsRowHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Text(title)
                .font(Theme.SettingsFonts.rowTitle)
                .foregroundStyle(Theme.text)
            Spacer(minLength: Theme.Space.mid)
            trailing
        }
        .font(Theme.SettingsFonts.rowNote)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// One line of detail under a row's title; muted unless its tone says otherwise.
private struct SettingsLine: View {
    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone = .muted) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(Theme.SettingsFonts.rowNote)
            .foregroundStyle(Theme.color(tone))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A command to run in Terminal: selectable mono text and a copy button.
struct SettingsCommandRow: View {
    let command: String
    let copy: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Text(command)
                .font(Theme.SettingsFonts.mono)
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(command)
            Spacer(minLength: 0)
            Button { copy(command) } label: {
                IconView(icon: .copy, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
                    .frame(width: Theme.SettingsPane.copyTarget, height: Theme.SettingsPane.copyTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
            .accessibilityLabel("Copy \(command)")
        }
        .padding(.leading, Theme.SettingsPane.commandPadding)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }
}
