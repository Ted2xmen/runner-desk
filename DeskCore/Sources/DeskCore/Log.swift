import Foundation
import ShelfRunnerCore

/// An ended job's log in the work area: the runner's own rule
/// (`Bridge.replyLog`). An attended job reads its last saved screen (`<id>.screen.txt`, tmux
/// already applied every redraw), else its log file; an unattended (print mode) job writes its
/// result at exit, after the last capture, so its log file is the answer. The log file is raw
/// pane output: `AnsiText.parse` turns it into plain lines and color runs.
public enum FinishedLog {
    public enum Source: Equatable, Sendable {
        case screen
        case log
    }

    /// Where to look, in order.
    public static func sources(attended: Bool) -> [Source] { attended ? [.screen, .log] : [.log] }

    /// At most this much of the file's end is read (a long agent session logs megabytes).
    public static let maxBytes = 2 * 1024 * 1024

    public struct Lines: Equatable, Sendable {
        public let lines: [String]
        /// One list of runs per line; empty lists for a plain source.
        public let styles: [[AnsiText.Run]]
        /// The file was longer than `maxBytes`.
        public let truncated: Bool
    }

    public static func lines(_ text: String, source: Source, truncated: Bool = false) -> Lines {
        switch source {
        case .screen:
            let lines = LogTail.allLines(text)
            return Lines(lines: lines, styles: Array(repeating: [], count: lines.count), truncated: truncated)
        case .log:
            let parsed = AnsiText.parse(raw: text)
            return Lines(lines: parsed.lines, styles: parsed.styles, truncated: truncated)
        }
    }
}

/// Protocol v1 colors: `fg`/`bg` `-1` default, `0…15` the theme's palette, `16…255` the standard
/// cube and grays, `≥256` truecolor `256 + (r<<16 | g<<8 | b)`.
public enum TermColor: Equatable, Sendable {
    case defaultColor
    /// 0…15: the view maps it to its theme's ANSI colors.
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)

    public init(_ value: Int) {
        switch value {
        case ..<0: self = .defaultColor
        case 0..<16: self = .palette(value)
        case 16..<232:
            let i = value - 16
            let steps: [UInt8] = [0, 95, 135, 175, 215, 255]
            self = .rgb(steps[i / 36], steps[(i / 6) % 6], steps[i % 6])
        case 232..<256:
            let g = UInt8(8 + (value - 232) * 10)
            self = .rgb(g, g, g)
        default:
            let c = value - 256
            self = .rgb(UInt8((c >> 16) & 0xff), UInt8((c >> 8) & 0xff), UInt8(c & 0xff))
        }
    }
}
