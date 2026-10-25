import SwiftUI

struct BrowserPlatformAppIconSettingsSection: View {
    // MARK: - Variables

    var body: some View {
        CrestSettingsGroup("App icon") {
            LabeledContent("Fennavio") {
                BrowserPlatformCurrentAppIcon()
                    .frame(width: 58, height: 58)
                    .clipShape(.rect(cornerRadius: 13))
                    .accessibilityHidden(true)
            }
        }
    }
}
