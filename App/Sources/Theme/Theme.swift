import AppKit
import DeskCore
import SwiftUI

/// The one set of design tokens: Shelf's palette v2 in a terminal-first shell (sidebar, work
/// area edge to edge, one status bar; hairlines between them, no raised panels), light and
/// dark. Views never spell a color or a size.
/// Rule: the accent (vermilion) is action and brand only, never a state.
enum Theme {
    // Surfaces
    /// The chrome: sidebar and status bar.
    static let bg = dynamic(light: 0xF0EEEB, dark: 0x0C0B0A)
    /// The work area; the terminal and the log sit on it.
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x131110)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1A1816)
    static let foot = dynamic(light: 0xF7F5F2, dark: 0x1A1816)
    static let line = dynamic(light: 0xE6E1DC, dark: 0x2A2623)
    static let line2 = dynamic(light: 0xDCD6CF, dark: 0x34302C)
    /// A sidebar row's ground when selected, and when hovered: fills on the window ground, no
    /// edge (the accent is never selection).
    static let rowSelected = dynamic(light: 0xE2DDD7, dark: 0x25221F)
    static let rowHover = dynamic(light: 0xE9E5E1, dark: 0x191715)
    /// The agent badge's tile in a sidebar row.
    static let badge = dynamic(light: 0xE4DFD9, dark: 0x1F1C1A)
    /// Claude's own orange, only on its mark (never a state).
    static let claude = dynamic(light: 0xC15F3C, dark: 0xD97757)
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

    /// The terminal's ground and text (`panel`, `text`), resolved for one scheme: SwiftTerm takes a
    /// fixed color, so a dynamic one would resolve outside the window's appearance.
    static func terminalColors(dark: Bool) -> (background: NSColor, foreground: NSColor) {
        dark ? (NSColor(hex: 0x131110), NSColor(hex: 0xF3F1EE)) : (NSColor(hex: 0xFFFFFF), NSColor(hex: 0x1A1715))
    }

    /// The 16 ANSI colors of the log pane (protocol v1: 0–15 are the theme's palette); xterm's.
    static let ansi: [Color] = [
        0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
        0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
    ].map { Color(nsColor: NSColor(hex: $0)) }

    enum Metrics {
        /// Sidebar: 300, 264 in a narrow window (900 pt).
        static let sidebar: CGFloat = 300
        static let sidebarNarrow: CGFloat = 264
        /// Below this window width the sidebar narrows, Scheduled hides, header actions turn to
        /// icons, the status bar drops its plain segments.
        static let narrowWindow: CGFloat = 1000
        static let sidebarPadding: CGFloat = 16
        /// The sidebar's job list inset from its edges.
        static let sidebarListInset: CGFloat = 6
        /// The top row: the traffic lights over the sidebar, the job header over the work area;
        /// one height so their hairline is one line.
        static let titleBar: CGFloat = 50
        /// The window-wide status bar at the bottom.
        static let statusBar: CGFloat = 32
        /// The job header's and the notice strips' side padding.
        static let headerPaddingH: CGFloat = 14
        static let statusBarPaddingH: CGFloat = 12
        /// New session sheet.
        static let sheetWidth: CGFloat = 460
        static let sheetList: CGFloat = 190
        /// The status bar's details popover.
        static let popoverWidth: CGFloat = 300
        /// Sidebar rows: folder headers, Show all, scheduled and empty lines.
        static let rowHeight: CGFloat = 26
        static let rowPaddingH: CGFloat = 8
        static let rowGap: CGFloat = 2
        /// Job and session rows: agent badge, two lines, the state at the right.
        static let itemPaddingV: CGFloat = 7
        static let itemMinHeight: CGFloat = 46
        static let badge: CGFloat = 28
        static let badgeIcon: CGFloat = 15
        static let stateGlyph: CGFloat = 14
        /// Shelf's mark on a badge's corner, and its tile.
        static let shelfMark: CGFloat = 11
        static let shelfMarkTile: CGFloat = 14
        /// The state column at a row's right end.
        static let stateColumn: CGFloat = 20
        /// An editor's app icon on its button.
        static let editorIcon: CGFloat = 16
        /// The hover Stop button there.
        static let stopButton: CGFloat = 24
        /// The marker column: dot or state icon.
        static let marker: CGFloat = 14
        static let markerIcon: CGFloat = 12
        static let divider: CGFloat = 1
        static let dot: CGFloat = 7
        static let dotRing: CGFloat = 3
        static let emptyWidth: CGFloat = 440
        /// Between the sleeping robot and the empty state's title.
        static let sleepingAgentGap: CGFloat = 14
        static let icon: CGFloat = 16
        static let iconSmall: CGFloat = 13
        static let buttonHeight: CGFloat = 24
        static let limitBar: CGFloat = 5
        static let gap: CGFloat = 12
        static let pagePadding: CGFloat = 20
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

    /// Waits before a word shows up: a step that usually ends first shows nothing, not a flash.
    enum Timing {
        /// A job view's "Opening…" (preparing takes some 10-15 ms).
        static let openingDelay: Duration = .milliseconds(150)
        /// One frame of the sleeping robot over an empty work area: slow, a calm breath.
        static let sleepingAgentFrame: TimeInterval = 0.7
    }

    enum Radius {
        static let row: CGFloat = 6
        static let card: CGFloat = 14
        static let button: CGFloat = 6
        static let logo: CGFloat = 8
        static let chip: CGFloat = 5
    }

    /// Type: SF Pro for titles and sentences; SF Mono for everything the machine says (times,
    /// counts, `now`, the status bar, tmux and logs).
    enum Fonts {
        static let section = Font.system(size: 12, weight: .semibold)
        /// Sidebar section titles: small letter-spaced caps (Needs you, Scheduled, folders).
        static let sectionCaps = Font.system(size: 10.5, weight: .semibold)
        static let sectionCapsTracking: CGFloat = 0.7
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let rowLabel = Font.system(size: 11, weight: .medium)
        static let rowMeta = Font.system(size: 11)
        static let rowMono = Font.system(size: 11, design: .monospaced)
        static let rowNow = Font.system(size: 11, design: .monospaced)
        /// The status bar and its popover's figures.
        static let status = Font.system(size: 11.5, design: .monospaced)
        static let footer = Font.system(size: 11.5)
        static let footerMono = Font.system(size: 11, design: .monospaced)
        static let headerTitle = Font.system(size: 13, weight: .semibold)
        static let headerMeta = Font.system(size: 11.5, design: .monospaced)
        static let chip = Font.system(size: 11.5, weight: .medium).monospacedDigit()
        static let button = Font.system(size: 12)
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let cardLine = Font.system(size: 13.5)
        static let strip = Font.system(size: 12.5)
        static let log = Font.system(size: 12, design: .monospaced)
        static let emptyTitle = Font.system(size: 17, weight: .semibold)
        static let emptyLine = Font.system(size: 13)
        /// The sleeping robot's ASCII art over an empty work area.
        static let sleepingAgent = Font.system(size: 12, design: .monospaced)
        static let terminalSize: CGFloat = 12.5
    }

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
    }

    private static func nsDynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat, darkAlpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark).withAlphaComponent(darkAlpha)
                : NSColor(hex: light).withAlphaComponent(lightAlpha)
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
    /// shelf-runner, the background service.
    case runner = "ServerStack01"
    /// Claude's mark (Simple Icons, CC0; design/icons/agents/README.md).
    case agentClaude = "AgentClaude"
    /// Codex's mark (LobeHub Icons, MIT; design/icons/agents/README.md).
    case agentCodex = "AgentCodex"
    /// Shelf's mark, in its own colors: a job that came from Shelf.
    case shelfMark = "ShelfMark"

    /// Drawn in its own colors, not tinted.
    var isMulticolor: Bool { self == .shelfMark }
}

struct IconView: View {
    let icon: DeskIcon
    var size: CGFloat = Theme.Metrics.icon
    /// A multicolor icon drawn as a one-color silhouette in the foreground style.
    var monochrome = false

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(icon.isMulticolor && !monochrome ? .original : .template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
