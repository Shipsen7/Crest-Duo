import SwiftUI

/// Follows the foreground scene rather than running a background timer.
struct BrowserFilterListUpdateLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let rulesChanged: () -> Void
    private var updates: BrowserFilterListUpdates { .shared }

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await updates.refreshWhileActive()
            }
            .task(id: BrowserAppPreferenceStore.shared.disabledFilterLists) {
                await updates.refresh()
            }
            .onChange(of: updates.generation) {
                rulesChanged()
            }
    }
}
