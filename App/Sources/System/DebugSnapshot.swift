#if DEBUG
import AppKit

/// Debug builds only: with `RUNNER_DESK_SNAPSHOT_DIR` set, the window draws itself into
/// `snapshot-<n>.png` every 3 s, six times. Lets an agent check a layout without screen
/// recording rights or touching the user's screen (no clicks, no focus change).
enum DebugSnapshot {
    @MainActor
    static func startIfAsked() {
        guard let dir = ProcessInfo.processInfo.environment["RUNNER_DESK_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        Task { @MainActor in
            for count in 1...6 {
                try? await Task.sleep(for: .seconds(3))
                // The layer tree, not `cacheDisplay`: layer grounds (SwiftTerm's) only show this way.
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView, let layer = view.layer,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
                layer.render(in: context.cgContext)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("snapshot-\(count).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }
}
#endif
