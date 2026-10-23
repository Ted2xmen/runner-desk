import DeskCore
import SwiftUI

/// The flat shell: sidebar on the left under the traffic lights, the work
/// area on the right. Narrow (900 pt): 240 sidebar, no Scheduled, icon-only actions.
struct ShellView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < Theme.Metrics.narrowWindow
            HStack(spacing: 0) {
                SidebarView(model: model, narrow: narrow)
                    .frame(width: narrow ? Theme.Metrics.sidebarNarrow : Theme.Metrics.sidebar)
                Rectangle().fill(Theme.line).frame(width: 1)
                DetailView(model: model, narrow: narrow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .foregroundStyle(Theme.text)
    }
}
