#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: with `SHELF_BENCH_SNAPSHOT_DIR` set, the window draws itself into
/// `snapshot-<n>.png` every 3 s, six times; a sheet on it into `snapshot-<n>-sheet.png`. Lets an
/// agent check a layout without screen recording rights or touching the user's screen (no
/// clicks, no focus change).
enum DebugSnapshot {
    @MainActor
    static func startIfAsked() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SHELF_BENCH_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        // `SHELF_BENCH_SELECT=<job or session id>`: selects it, so a snapshot can show its page.
        if let id = env["SHELF_BENCH_SELECT"], !id.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                AppModel.shared.reveal(id)
            }
        }
        // `SHELF_BENCH_OPEN_URL=<shelfbench:// link>`: opens it as if clicked;
        // `SHELF_BENCH_ENABLE_CONFIRM=1` then presses Enable (with `SHELF_BENCH_BRIDGE` set to
        // a stand-in, never the real Bridge).
        if let link = env["SHELF_BENCH_OPEN_URL"], let url = URL(string: link) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                AppModel.shared.open(url)
                guard env["SHELF_BENCH_ENABLE_CONFIRM"] == "1", env["SHELF_BENCH_BRIDGE"] != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                AppModel.shared.confirmEnable()
            }
        }
        // `SHELF_BENCH_SHOW_SETTINGS=1`: the Settings view in a window of its own, without taking
        // focus (the Settings scene opens only for an active app), drawn into `snapshot-<n>-settings.png`.
        var settings: NSWindow?
        if env["SHELF_BENCH_SHOW_SETTINGS"] == "1" {
            let host = NSHostingView(rootView: SettingsView(model: AppModel.shared))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderBack(nil)
            settings = window
        }
        Task { @MainActor in
            for count in 1...6 {
                try? await Task.sleep(for: .seconds(3))
                if let settings {
                    settings.setContentSize(settings.contentView?.fittingSize ?? .zero)
                    write(settings.contentView, to: URL(fileURLWithPath: dir).appendingPathComponent("snapshot-\(count)-settings.png"))
                }
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil && $0 !== settings }) else { continue }
                write(window.contentView, to: URL(fileURLWithPath: dir).appendingPathComponent("snapshot-\(count).png"))
                // A sheet's ground is its window's, not its view's: drawn first.
                if let sheet = window.attachedSheet {
                    var ground: CGColor?
                    sheet.effectiveAppearance.performAsCurrentDrawingAppearance { ground = NSColor.windowBackgroundColor.cgColor }
                    write(sheet.contentView, ground: ground, to: URL(fileURLWithPath: dir).appendingPathComponent("snapshot-\(count)-sheet.png"))
                }
            }
        }
    }

    /// The layer tree, not `cacheDisplay`: layer grounds (SwiftTerm's) only show this way.
    /// At 2x, and flipped: the bitmap context's origin is bottom left, the layer tree's top left.
    @MainActor
    private static func write(_ view: NSView?, ground: CGColor? = nil, to url: URL) {
        let scale: CGFloat = 2
        guard let view, let layer = view.layer,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                                         pixelsHigh: Int(view.bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = context.cgContext
        if let ground {
            cg.setFillColor(ground)
            cg.fill(CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        }
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: view.bounds.height)
        cg.scaleBy(x: 1, y: -1)
        layer.render(in: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
