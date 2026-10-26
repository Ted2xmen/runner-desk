import AppKit

/// The app's light or dark choice: follow the system, or force one. Stored in UserDefaults under
/// `appearance` and applied app-wide through `NSApp.appearance`, so every window, the terminal
/// and the dynamic theme colors resolve against it.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The saved choice; `system` when nothing (or something unknown) is stored.
    static var stored: Appearance {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    /// Debug builds only: `RUNNER_DESK_APPEARANCE=light|dark` wins over the saved choice at launch,
    /// so a snapshot run can pin a scheme without touching the user's defaults. A choice made in
    /// Settings after launch still applies.
    static var override: Appearance? {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["RUNNER_DESK_APPEARANCE"]?.lowercased() else { return nil }
        return Appearance(rawValue: value)
        #else
        return nil
        #endif
    }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Sets `NSApp.appearance` for this choice.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    /// Applies the saved choice, or the debug override. Call before the first window shows.
    @MainActor
    static func applyStored() {
        (override ?? stored).apply()
    }
}
