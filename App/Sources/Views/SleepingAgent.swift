import SwiftUI

/// A small ASCII robot asleep above an empty work area: it breathes (antenna bobs, eyes and
/// mouth change) and Zs float up from its head and fade. Decorative; with Reduce Motion it
/// holds one frame. Every frame has the same lines and width, so the text below never moves.
struct SleepingAgent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Text(Self.render(tick: nil))
            } else {
                TimelineView(.periodic(from: .distantPast, by: Theme.Timing.sleepingAgentFrame)) { context in
                    Text(Self.render(tick: Int(context.date.timeIntervalSinceReferenceDate / Theme.Timing.sleepingAgentFrame)))
                }
            }
        }
        .font(Theme.Fonts.sleepingAgent)
        .lineSpacing(0)
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// Breathing in, breathing out; each held for two ticks. 23 columns, the body on the middle
    /// one, so it sits centered over the text.
    private static let frames: [[String]] = [
        [
            "                       ",
            "           o           ",
            "           |           ",
            "       .---'---.       ",
            "       | -   - |       ",
            "       |   .   |       ",
            "       '-------'       ",
            "      /|=======|\\      ",
            "       '-'   '-'       ",
        ],
        [
            "                       ",
            "                       ",
            "           o           ",
            "       .---'---.       ",
            "       | _   _ |       ",
            "       |   o   |       ",
            "       '-------'       ",
            "      /|=======|\\      ",
            "       '-'   '-'       ",
        ],
    ]

    /// Where a Z sits as it ages, (line, column), and how strong it is: it rises up and to the
    /// right of the head, grows, and fades.
    private static let drift: [(line: Int, column: Int, glyph: Character, opacity: Double)] = [
        (3, 17, "z", 0.85),
        (2, 18, "z", 0.65),
        (1, 20, "Z", 0.40),
        (0, 21, "Z", 0.18),
    ]

    /// A Z starts on these ticks of each cycle; the rest of the cycle is quiet.
    private static let spawns = [0, 2, 4]
    private static let cycle = 10

    private static func render(tick: Int?) -> AttributedString {
        let frame = frames[tick.map { ($0 / 2) % frames.count } ?? 0]
        var zs: [Int: [Int: (Character, Double)]] = [:]
        let ages: [Int]
        if let tick {
            let t = tick % cycle
            ages = spawns.map { t - $0 }.filter { drift.indices.contains($0) }
        } else {
            ages = [0, 2]
        }
        for age in ages {
            let z = drift[age]
            zs[z.line, default: [:]][z.column] = (z.glyph, z.opacity)
        }

        var out = AttributedString()
        for (index, line) in frame.enumerated() {
            if index > 0 { out += AttributedString("\n") }
            var plain = ""
            for (column, char) in line.enumerated() {
                if let (glyph, opacity) = zs[index]?[column] {
                    out += styled(plain, Theme.muted)
                    plain = ""
                    out += styled(String(glyph), Theme.muted.opacity(opacity))
                } else {
                    plain.append(char)
                }
            }
            out += styled(plain, Theme.muted)
        }
        return out
    }

    private static func styled(_ text: String, _ color: Color) -> AttributedString {
        var part = AttributedString(text)
        part.foregroundColor = color
        return part
    }
}
