import DeskCore
import ShelfRunnerCore
import SwiftUI

/// An ended job's log: plain lines with the colors `AnsiText` found (protocol v1 colors),
/// newest at the bottom. Lines are the agent's own output, drawn as text.
struct LogPane: View {
    let log: FinishedLog.Lines

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if log.truncated {
                        Text("Earlier lines are left out.").font(Theme.Fonts.log).foregroundStyle(Theme.muted)
                    }
                    ForEach(log.lines.indices, id: \.self) { i in
                        Text(LogStyle.line(log.lines[i], runs: i < log.styles.count ? log.styles[i] : []))
                            .font(Theme.Fonts.log)
                            .foregroundStyle(Theme.text2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                            .id(i)
                    }
                }
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.bottom, Theme.Metrics.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottomLeading)
            .onAppear { proxy.scrollTo(log.lines.count - 1, anchor: .bottomLeading) }
        }
        .accessibilityLabel("Log")
    }
}

/// Turns a line and its runs (Unicode scalar offsets) into styled text.
enum LogStyle {
    static func line(_ text: String, runs: [AnsiText.Run]) -> AttributedString {
        guard !runs.isEmpty else { return AttributedString(text) }
        let scalars = Array(text.unicodeScalars)
        var out = AttributedString()
        var cursor = 0
        func piece(_ from: Int, _ to: Int) -> AttributedString {
            var s = String.UnicodeScalarView()
            s.append(contentsOf: scalars[from..<to])
            return AttributedString(String(s))
        }
        for run in runs {
            let start = min(max(run.start, cursor), scalars.count)
            let end = min(start + max(0, run.len), scalars.count)
            if start > cursor { out += piece(cursor, start) }
            var styled = piece(start, end)
            apply(run.style, to: &styled)
            out += styled
            cursor = end
        }
        if cursor < scalars.count { out += piece(cursor, scalars.count) }
        return out
    }

    private static func apply(_ style: AnsiText.Style, to s: inout AttributedString) {
        var fg = color(style.fg)
        var bg = color(style.bg)
        if style.flags & AnsiText.Style.inverse != 0 {
            let f = fg ?? Theme.text2
            fg = bg ?? Theme.panel
            bg = f
        }
        if style.flags & AnsiText.Style.dim != 0 { fg = Theme.muted }
        if let fg { s.foregroundColor = fg }
        if let bg { s.backgroundColor = bg }
        if style.flags & AnsiText.Style.bold != 0 { s.inlinePresentationIntent = .stronglyEmphasized }
        if style.flags & AnsiText.Style.italic != 0 {
            s.inlinePresentationIntent = (s.inlinePresentationIntent ?? []).union(.emphasized)
        }
        if style.flags & AnsiText.Style.underline != 0 { s.underlineStyle = .single }
    }

    private static func color(_ value: Int) -> Color? {
        switch TermColor(value) {
        case .defaultColor: nil
        case .palette(let i): Theme.ansi[i]
        case .rgb(let r, let g, let b): Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}
