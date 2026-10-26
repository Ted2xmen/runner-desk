import SwiftUI

/// The Settings pane's sizes and type, on top of the shared tokens.
extension Theme {
    enum SettingsPane {
        static let width: CGFloat = 460
        static let padding: CGFloat = 24
        static let sectionGap: CGFloat = 18
        static let cardPadding: CGFloat = 16
        static let rowGap: CGFloat = 10
        static let border: CGFloat = 1
        static let pickerWidth: CGFloat = 240
        /// Between the detail lines of one row.
        static let lineGap: CGFloat = 4
        /// A command row: the copy button's square and the text's inset.
        static let copyTarget: CGFloat = 24
        static let commandPadding: CGFloat = 8
    }

    enum SettingsFonts {
        static let section = Font.system(size: 12, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let rowNote = Font.system(size: 12)
        /// Paths, keys and commands.
        static let mono = Font.system(size: 11.5, design: .monospaced)
        static let about = Font.system(size: 11.5).monospacedDigit()
    }
}
