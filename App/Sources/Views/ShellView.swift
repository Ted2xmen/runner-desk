import DeskCore
import SwiftUI

/// The terminal-first shell: the sidebar under the traffic lights, the work area edge to edge,
/// one hairline between them, and the window-wide status bar at the bottom. Narrow (under
/// 1000 pt): a narrower sidebar, no Scheduled, icon-only actions, a shorter status bar.
struct ShellView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < Theme.Metrics.narrowWindow
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SidebarView(model: model, narrow: narrow)
                        .frame(width: narrow ? Theme.Metrics.sidebarNarrow : Theme.Metrics.sidebar)
                    Rectangle().fill(Theme.line).frame(width: Theme.Metrics.divider)
                        .accessibilityHidden(true)
                    DetailView(model: model, narrow: narrow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                StatusBar(model: model, narrow: narrow)
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .foregroundStyle(Theme.text)
        .sheet(isPresented: Binding(get: { model.showsNewSession }, set: { model.showsNewSession = $0 })) {
            NewSessionSheet(model: model)
        }
        .alert("End this session?", isPresented: Binding(get: { model.confirmingEnd != nil }, set: { if !$0 { model.confirmingEnd = nil } }),
               presenting: model.confirmingEnd.flatMap(model.session)) { session in
            Button("Cancel", role: .cancel) { model.confirmingEnd = nil }
            Button("End session", role: .destructive) { model.endSession(session.id) }
        } message: { session in
            Text("\(session.agent.title) is still running in it. Ending closes it in \((session.folder as NSString).lastPathComponent). Files the agent already wrote stay.")
        }
    }
}
