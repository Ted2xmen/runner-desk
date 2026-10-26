import DeskCore
import SwiftUI

/// "Enable this folder in shelf-runner?": the folder, what enabling means, Cancel or Enable.
/// Nothing is enabled before Enable; without the CLI the command is offered to copy instead.
struct EnableFolderSheet: View {
    let model: AppModel
    let sheet: AppModel.EnableSheet

    var body: some View {
        // The model's copy: the phase moves on while the sheet is up.
        let sheet = model.enableSheet.flatMap { $0.id == self.sheet.id ? $0 : nil } ?? self.sheet
        let phase = sheet.phase
        let request = sheet.request
        VStack(alignment: .leading, spacing: Theme.Space.mid) {
            Text(EnableFolder.title).font(Theme.Fonts.cardTitle)
            if !request.display.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.hair) {
                    HStack(spacing: Theme.Space.small) {
                        IconView(icon: .folder, size: Theme.Metrics.iconSmall).foregroundStyle(Theme.icon)
                        Text(request.display)
                            .font(Theme.SettingsFonts.mono)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    if let from = request.resolvedFrom {
                        Text(from)
                            .font(Theme.Fonts.rowMeta)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(Theme.Space.mid)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .help(request.full)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Folder \(request.full)")
            }
            if phase.showsExplanation {
                Text(EnableFolder.explanation)
                    .font(Theme.Fonts.cardLine)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = phase.message {
                HStack(spacing: Theme.Space.small) {
                    if phase.isRunning { ProgressView().controlSize(.small) }
                    Text(message)
                        .font(Theme.Fonts.cardLine)
                        .foregroundStyle(Theme.color(phase.tone))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if phase.showsCommand {
                SettingsCommandRow(command: request.command, copy: model.copy)
            }
            HStack(spacing: Theme.Space.row) {
                Spacer()
                Button(phase.dismissTitle) { model.dismissEnableSheet() }
                    .keyboardShortcut(.cancelAction)
                if phase.showsEnable {
                    Button("Enable") { model.confirmEnable() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(phase.isRunning)
                }
            }
            .padding(.top, Theme.Space.small)
        }
        .padding(Theme.Metrics.pagePadding)
        .frame(width: Theme.Metrics.sheetWidth)
        .foregroundStyle(Theme.text)
    }
}

extension View {
    /// The enable sheet, on this window, for requests from `origin`.
    func enableFolderSheet(_ model: AppModel, origin: AppModel.EnableSheet.Origin) -> some View {
        sheet(item: Binding(get: { model.enableSheet?.origin == origin ? model.enableSheet : nil },
                            set: { if $0 == nil { model.dismissEnableSheet() } })) { sheet in
            EnableFolderSheet(model: model, sheet: sheet)
        }
    }
}
