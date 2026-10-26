import SwiftUI
import UIKit

/// The document's visible background, shared by the safe areas and phone bars.
/// A site's theme meta tag may describe a light header over a dark document.
@MainActor
struct MobileBrowserPageBackground {
    // MARK: - Variables

    let color: UIColor

    var colorScheme: ColorScheme {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return .light }
        return red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.5 ? .dark : .light
    }

    // MARK: - Initializers

    init?(page: MobileBrowserPage?) {
        guard let page, page.committedNavigationCount > 0 else { return nil }
        color = page.underPageColor ?? page.themeColor ?? .systemBackground
    }
}
