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
    @State private var protectionError: String?
    @State private var isStarting = false

    var body: some View {
        Group {
            if let session {
                NativeBrowserView(session: session)
            } else if let protectionError {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "Content Blocking Unavailable",
                        systemImage: "shield.slash",
                        description: Text(protectionError)
                    )
                    Button("Continue Without Blocking", action: openWithoutBlocking)
                }
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
        .task { await openSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && session == nil && protectionError == nil {
                Task { await openSession() }
            }
        }
    }

    @MainActor
    private func openSession() async {
        guard session == nil, protectionError == nil, startupError == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let rules = try await NativeContentBlocker.compileBundled()
            do {
                session = try NativeBrowserSession(contentRuleList: rules)
            } catch {
                startupError = error.localizedDescription
            }
        } catch {
            // Never load an unfiltered page without the person's knowledge.
            protectionError = error.localizedDescription
        }
    }

    private func openWithoutBlocking() {
        do {
            session = try NativeBrowserSession()
            protectionError = nil
        } catch {
            startupError = error.localizedDescription
            protectionError = nil
        }
    }
}
