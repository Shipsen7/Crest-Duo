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
        .task {
            guard session == nil, startupError == nil else { return }
            do {
                session = try NativeBrowserSession()
            } catch {
                startupError = error.localizedDescription
            }
        }
    }
}
