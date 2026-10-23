import AppKit
import DeskCore
import SwiftUI

/// The one set of design tokens: Shelf's palette v2 and flat shell (no
/// glass), same values in light and dark. Views never spell a color or a size.
/// Rule: the accent (vermilion) is action and brand only, never a state.
enum Theme {
    // Surfaces
    static let bg = dynamic(light: 0xFAF8F5, dark: 0x0C0B0A)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x110F0E)
    static let foot = dynamic(light: 0xF5F2EE, dark: 0x161413)
    static let line = dynamic(light: 0xECE7E2, dark: 0x221F1D)
    static let line2 = dynamic(light: 0xE0D9D2, dark: 0x2E2A27)
    static let sel = dynamic(light: 0xF1ECE6, dark: 0x1C1917)
    // Text and icons
    static let text = dynamic(light: 0x1A1715, dark: 0xF3F1EE)
    static let text2 = dynamic(light: 0x4D4741, dark: 0xC2BCB6)
    static let muted = dynamic(light: 0x8C857E, dark: 0x807973)
    static let icon = dynamic(light: 0x706962, dark: 0x9E9791)
    // Meaning
    static let red = dynamic(light: 0xC2255E, dark: 0xF2588F)
    static let green = dynamic(light: 0x1F8A3E, dark: 0x3FB950)
    static let amber = dynamic(light: 0xA86A10, dark: 0xE8A33D)
    // Accent (vermilion #E8412C)
    static let accent = dynamic(light: 0xE8412C, dark: 0xE8412C)
    static let onAccent = Color.white

    static func color(_ tone: Tone) -> Color {
        switch tone {
        case .plain: text2
        case .muted: muted
        case .green: green
        case .amber: amber
        case .rose: red
        }
    }

    /// The terminal's ground and text (`bg`, `text`), resolved for one scheme: SwiftTerm takes a
    /// fixed color, so a dynamic one would resolve outside the window's appearance.
    static func terminalColors(dark: Bool) -> (background: NSColor, foreground: NSColor) {
        dark ? (NSColor(hex: 0x0C0B0A), NSColor(hex: 0xF3F1EE)) : (NSColor(hex: 0xFAF8F5), NSColor(hex: 0x1A1715))
    }

    /// The 16 ANSI colors of the log pane (protocol v1: 0–15 are the theme's palette); xterm's.
    static let ansi: [Color] = [
        0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
        0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
    ].map { Color(nsColor: NSColor(hex: $0)) }

    enum Metrics {
        /// Sidebar: 264, 240 in a narrow window (900 pt).
        static let sidebar: CGFloat = 264
        static let sidebarNarrow: CGFloat = 240
        /// Below this window width the sidebar narrows, Scheduled hides, header actions turn to icons.
        static let narrowWindow: CGFloat = 1000
        static let sidebarPadding: CGFloat = 16
        /// Room for the traffic lights over the sidebar.
        static let windowControlsRow: CGFloat = 44
        static let header: CGFloat = 64
        static let logo: CGFloat = 28
        static let logoGlyph: CGFloat = 18
        static let rowPaddingH: CGFloat = 10
        static let rowPaddingV: CGFloat = 7
        /// Job cards in the sidebar: taller than a list row, a card ground and a hairline edge.
        static let jobCardPaddingH: CGFloat = 12
        static let jobCardPaddingV: CGFloat = 11
        static let jobCardGap: CGFloat = 6
        static let jobCardBorder: CGFloat = 1
        static let jobCardBorderSelected: CGFloat = 1.5
        static let dot: CGFloat = 7
        static let dotRing: CGFloat = 3
        static let emptyWidth: CGFloat = 440
        static let icon: CGFloat = 16
        static let iconSmall: CGFloat = 13
        static let buttonHeight: CGFloat = 28
        static let limitBar: CGFloat = 5
        static let gap: CGFloat = 12
        static let pagePadding: CGFloat = 28
        static let cardPadding: CGFloat = 20
        static let skeletonRow: CGFloat = 14
        static let skeletonLong: CGFloat = 180
        static let skeletonShort: CGFloat = 130
        static let minWindowWidth: CGFloat = 900
        static let minWindowHeight: CGFloat = 600
        static let defaultWindowWidth: CGFloat = 1280
        static let defaultWindowHeight: CGFloat = 800
        static let hitTarget: CGFloat = 28
    }

    /// Spacing steps (Shelf's canvases use the same few).
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let small: CGFloat = 6
        static let chipH: CGFloat = 7
        static let row: CGFloat = 8
        static let mid: CGFloat = 10
        static let section: CGFloat = 18
    }

    enum Radius {
        static let row: CGFloat = 9
        static let jobCard: CGFloat = 10
        static let card: CGFloat = 14
        static let button: CGFloat = 8
        static let logo: CGFloat = 8
        static let chip: CGFloat = 5
    }

    /// Type (SF Pro; mono for `now`, tmux and logs).
    enum Fonts {
        static let logo = Font.system(size: 15, weight: .semibold)
        static let connection = Font.system(size: 12).monospacedDigit()
        static let section = Font.system(size: 12, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let jobCardTitle = Font.system(size: 13.5, weight: .semibold)
        static let rowMeta = Font.system(size: 11.5).monospacedDigit()
        static let rowNow = Font.system(size: 11, design: .monospaced)
        static let footer = Font.system(size: 11.5)
        static let footerMono = Font.system(size: 11, design: .monospaced)
        static let headerTitle = Font.system(size: 15, weight: .semibold)
        static let headerMeta = Font.system(size: 12).monospacedDigit()
        static let chip = Font.system(size: 11.5, weight: .medium).monospacedDigit()
        static let button = Font.system(size: 12)
        static let cardTitle = Font.system(size: 20, weight: .semibold)
        static let cardLine = Font.system(size: 13.5)
        static let strip = Font.system(size: 12.5)
        static let log = Font.system(size: 12, design: .monospaced)
        static let emptyTitle = Font.system(size: 17, weight: .semibold)
        static let emptyLine = Font.system(size: 13)
        static let terminalSize: CGFloat = 12.5
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark))
    }

    private static func nsDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Hugeicons Free, stroke rounded (MIT, design/icons/LICENSE-hugeicons.md).
enum DeskIcon: String {
    case commandLine = "CommandLine"
    case copy = "Copy01"
    case openExternal = "LinkSquare02"
    case folder = "Folder01"
    case clock = "Clock01"
    case alert = "Alert02"
    case done = "CheckmarkCircle02"
    case failed = "CancelCircle"
    case chevronDown = "ArrowDown01"
    case chevronRight = "ArrowRight01"
    case file = "File01"
}

struct IconView: View {
    let icon: DeskIcon
    var size: CGFloat = Theme.Metrics.icon

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
