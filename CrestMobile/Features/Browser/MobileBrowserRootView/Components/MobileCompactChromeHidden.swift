import SwiftUI

/// Shares the user's explicit toolbar visibility with the native side and status bars.
struct MobileCompactChromeHidden: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
