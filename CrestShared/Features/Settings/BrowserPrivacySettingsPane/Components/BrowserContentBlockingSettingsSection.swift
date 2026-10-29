import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
    @Binding var policy: ContentBlockingPolicy
    let errorDescription: String?
    @Bindable private var preferences = BrowserAppPreferenceStore.shared
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

    var body: some View {
        Section("Content blocking") {
            Toggle("Block known ads and trackers", isOn: isEnabled)
                .accessibilityIdentifier("content-blocking-enabled")

            #if os(iOS)
                Picker("Blocking rules", selection: $selectedModeName) {
                    Text("Brave iOS (test)").tag(BrowserProtectionMode.braveIOS.name)
                    Text("Fennavio (previous)").tag(BrowserProtectionMode.fennavio.name)
                }
                .accessibilityIdentifier("content-blocking-rule-source")
                if !usesPreviousFilters {
                    Text(
                        "Brave's bundled iOS WebKit rules are active. The full Rust engine, advanced cosmetics and automatic Brave updates are not included. Reload the page after switching."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            #endif

            if usesPreviousFilters && updates.isAvailable {
                ForEach(updates.subscriptions) { subscription in
                    Toggle(
                        subscription.title,
                        isOn: Binding {
                            !preferences.disabledFilterLists.contains(subscription.id)
                        } set: { enabled in
                            var disabled = preferences.disabledFilterLists.filter { $0 != subscription.id }
                            if !enabled { disabled.append(subscription.id) }
                            preferences.disabledFilterLists = disabled
                        })
                }
                Text(
                    "Filter selection applies to all Spaces on this device. Lists update automatically according to their expiry while the app is active."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                LabeledContent(
                    "Filter lists",
                    value: updates.updatedAt?.formatted(date: .abbreviated, time: .shortened)
                        ?? String(localized: "Included with app"))
                if updates.ruleCount > 0 {
                    LabeledContent("Rules", value: updates.ruleCount.formatted())
                }
                Button {
                    Task { await updates.refresh(force: true) }
                } label: {
                    if updates.isUpdating {
                        ProgressView()
                    } else {
                        Text("Update filter lists")
                    }
                }
                .disabled(updates.isUpdating)
                if updates.failed {
                    Text("Update unavailable. Previous filters remain active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if policy.blocksContent, let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding {
            policy.blocksContent
        } set: { isEnabled in
            policy = .blocking(isEnabled)
        }
    }
}
