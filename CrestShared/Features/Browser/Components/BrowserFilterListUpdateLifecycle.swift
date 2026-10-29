import SwiftUI

/// Follows the foreground scene rather than running a background timer.
struct BrowserFilterListUpdateLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let rulesChanged: () -> Void
    private var updates: BrowserFilterListUpdates { .shared }
    @AppStorage(BrowserProtectionMode.storageKey)
    private var selectedModeName = BrowserProtectionMode.fennavio.name

    private var usesPreviousFilters: Bool {
        #if os(iOS)
            BrowserProtectionMode.named(selectedModeName) == .fennavio
        #else
            true
        #endif
    }

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase == .active && usesPreviousFilters) {
                guard scenePhase == .active, usesPreviousFilters else { return }
                await updates.refreshWhileActive()
            }
            .task(id: BrowserAppPreferenceStore.shared.disabledFilterLists) {
                guard usesPreviousFilters else { return }
                await updates.refresh()
            }
            .onChange(of: selectedModeName) {
                rulesChanged()
                if usesPreviousFilters {
                    Task { await updates.refresh() }
                }
            }
            .onChange(of: updates.generation) {
                if usesPreviousFilters { rulesChanged() }
            }
    }
}
