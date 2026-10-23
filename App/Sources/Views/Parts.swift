import DeskCore
import SwiftUI

/// The state dot (amber with a ring when the job asks).
struct StateDot: View {
    let tone: Tone
    var ringed = false

    var body: some View {
        Circle()
            .fill(Theme.color(tone))
            .frame(width: Theme.Metrics.dot, height: Theme.Metrics.dot)
            .overlay(Circle().stroke(Theme.color(tone).opacity(ringed ? 0.35 : 0), lineWidth: Theme.Metrics.dotRing).padding(-Theme.Space.hair))
            .accessibilityHidden(true)
    }
}

/// The header's state chip: the label on its tone at 14 %.
struct LabelChip: View {
    let label: DeskCore.Label

    var body: some View {
        Text(label.text)
            .font(Theme.Fonts.chip)
            .foregroundStyle(Theme.color(label.tone))
            .padding(.horizontal, Theme.Space.chipH)
            .padding(.vertical, Theme.Space.hair)
            .background(Theme.color(label.tone).opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}

/// A secondary framed button (Copy tmux command, Open in Terminal, Copy log). The accent is
/// for actions D1 has none of. `iconOnly` in a narrow window, with the label as tooltip and
/// accessibility label.
struct FramedButton: View {
    let title: String
    let icon: DeskIcon
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.small) {
                IconView(icon: icon, size: Theme.Metrics.iconSmall)
                if !iconOnly { Text(title).font(Theme.Fonts.button) }
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, iconOnly ? Theme.Space.chipH : Theme.Space.mid)
            .frame(minWidth: Theme.Metrics.hitTarget, minHeight: Theme.Metrics.buttonHeight)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button).stroke(Theme.line2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A full-width notice under the header: neutral, amber or rose.
struct Strip: View {
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(Theme.Fonts.strip)
            .foregroundStyle(tone == .plain ? Theme.text2 : Theme.color(tone))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metrics.pagePadding)
            .padding(.vertical, Theme.Space.row)
            .background(tone == .plain ? Theme.foot : Theme.color(tone).opacity(0.10))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// A centered empty or in-between state.
struct EmptyState: View {
    let title: String
    var line: String?
    var mono: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.row) {
            Text(title).font(Theme.Fonts.emptyTitle)
            if let line { Text(line).font(Theme.Fonts.emptyLine).foregroundStyle(Theme.text2).multilineTextAlignment(.center) }
            if let mono {
                Text(mono).font(Theme.Fonts.footerMono).foregroundStyle(Theme.text2).textSelection(.enabled)
            }
            if let buttonTitle, let action {
                FramedButton(title: buttonTitle, icon: .folder, action: action).padding(.top, Theme.Space.small)
            }
        }
        .frame(maxWidth: Theme.Metrics.emptyWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
