import SwiftUI
import UIKit

@main
struct FennavioNativeApp: App {
    var body: some Scene { WindowGroup { NativeBrowserLaunchView() } }
}

/// Startup failures never reset existing data or silently disable protection.
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
                        "Content Blocking Unavailable", systemImage: "shield.slash", description: Text(protectionError))
                    Button("Retry") {
                        self.protectionError = nil
                        Task { await openSession() }
                    }
                    Button("Continue Without Blocking", action: openWithoutBlocking)
                }
            } else if let startupError {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "Could Not Open Browsing Data", systemImage: "exclamationmark.triangle",
                        description: Text(startupError))
                    Button("Retry") {
                        self.startupError = nil
                        Task { await openSession() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .background { NativePrivacyCover().frame(width: 0, height: 0) }
        .overlay {
            if scenePhase != .active { Color(uiColor: .systemBackground).ignoresSafeArea() }
        }
        .task { await openSession() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            session?.setForeground(false)
        }
        .onChange(of: scenePhase) { _, phase in
            session?.setForeground(phase == .active)
            if phase == .active && session == nil && protectionError == nil && startupError == nil {
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
                let opened = try NativeBrowserSession(contentRuleList: rules)
                opened.setForeground(scenePhase == .active)
                session = opened
            } catch { startupError = error.localizedDescription }
        } catch { protectionError = error.localizedDescription }
    }

    private func openWithoutBlocking() {
        do {
            let opened = try NativeBrowserSession()
            opened.setForeground(scenePhase == .active)
            session = opened
            protectionError = nil
        } catch {
            startupError = error.localizedDescription
            protectionError = nil
        }
    }
}
