import SwiftUI

@main
struct FennavioNativeApp: App {
    var body: some Scene {
        WindowGroup {
            NativeBrowserLaunchView()
        }
    }
}

/// If the persisted format cannot be read, stop instead of overwriting tabs.
private struct NativeBrowserLaunchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: NativeBrowserSession?
    @State private var startupError: String?

    var body: some View {
        Group {
            if let session {
                NativeBrowserView(session: session)
            } else if let startupError {
                ContentUnavailableView(
                    "Could Not Open Browsing Data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(startupError)
                )
            } else {
                ProgressView()
            }
        }
        // Prevent ordinary app-switcher previews from displaying a banking page.
        // Device testing must still confirm capture timing on the Duo.
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
        }
        .task(perform: openSession)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && session == nil { openSession() }
        }
    }

    private func openSession() {
        guard session == nil else { return }
        do {
            session = try NativeBrowserSession()
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }
}
