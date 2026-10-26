import AppKit
import SwiftUI

/// Code editors a folder can open in, when installed. Their icons are the apps' own, read from
/// the installed bundle at run time (none ship with Bench).
struct Editor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let appURL: URL
}

enum Editors {
    /// Title and bundle ids, in the order they show.
    static let known: [(title: String, bundleIDs: [String])] = [
        ("Zed", ["dev.zed.Zed", "dev.zed.Zed-Preview"]),
        ("Cursor", ["com.todesktop.230313mzl4w4u92"]),
    ]

    /// The installed ones, looked up once at launch.
    @MainActor static let installed: [Editor] = known.compactMap { item in
        for id in item.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return Editor(id: id, title: item.title, appURL: url)
            }
        }
        return nil
    }

    @MainActor static func open(_ folder: String, in editor: Editor) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: editor.appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor static func icon(_ editor: Editor) -> NSImage {
        NSWorkspace.shared.icon(forFile: editor.appURL.path)
    }
}

/// One small button per installed editor, the app's icon on it: opens the folder there.
struct EditorButtons: View {
    let folder: String
    var size: CGFloat = Theme.Metrics.editorIcon

    var body: some View {
        ForEach(Editors.installed) { editor in
            EditorButton(editor: editor, folder: folder, size: size)
        }
    }
}

private struct EditorButton: View {
    let editor: Editor
    let folder: String
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        Button { Editors.open(folder, in: editor) } label: {
            Image(nsImage: Editors.icon(editor))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .frame(width: Theme.Metrics.stopButton, height: Theme.Metrics.stopButton)
                .background(hovering ? Theme.rowHover : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \((folder as NSString).lastPathComponent) in \(editor.title)")
        .accessibilityLabel("Open folder in \(editor.title)")
    }
}
