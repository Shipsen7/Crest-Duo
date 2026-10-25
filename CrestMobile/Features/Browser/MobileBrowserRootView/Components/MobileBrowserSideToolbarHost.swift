import SwiftUI

/// Coordinates native bars with the browser's own chrome. Foldable windows
/// disable vertical system bars before resolving their host, keeping browser
/// navigation below the page and its editing hierarchy stable while rotating.
struct MobileBrowserSideToolbarHost: ViewModifier {
    // MARK: - Variables

    /// The browser whose shown Space's tone the bar's glass follows. It is
    /// read here rather than by the view that applies this, so a change to the
    /// window never rebuilds that view in the middle of a change it is making.
    var browser: BrowserStore?
    /// The scheme the bar's glass follows where no browser is given, or nil
    /// for the system's.
    var colorScheme: ColorScheme?

    @Environment(\.mobileBrowserSideToolbarIsHosted) private var isHosted
    @Environment(\.colorScheme) private var contentColorScheme

    private var barColorScheme: ColorScheme? {
        browser?.shownSpace?.settings.look.colorScheme(over: contentColorScheme) ?? colorScheme
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        if isHosted {
            // A stack already carries this window's bars; a second one would
            // take the items meant for it.
            content
        } else {
            #if canImport(SwiftUICore, _version: 8.0.85)
                if #available(iOS 27.1, *) {
                    MobileBrowserSideToolbarStack(
                        colorScheme: barColorScheme ?? contentColorScheme,
                        contentColorScheme: contentColorScheme
                    ) {
                        content
                    }
                    // Rotating a foldable must not replace the page's host
                    // with a side-toolbar navigation stack while it is editing.
                    .toolbarVerticalBehavior(.disabled)
                } else {
                    content
                }
            #else
                content
            #endif
        }
    }

}

#if canImport(SwiftUICore, _version: 8.0.85)
    /// The navigation stack whose bars carry the side toolbar, once the system
    /// has asked for one. A device that never lays bars out down its side keeps
    /// its content exactly as it was; one that has kept the stack from then on,
    /// so turning or folding it never rebuilds the window's content.
    @available(iOS 27.1, *)
    private struct MobileBrowserSideToolbarStack<Content: View>: View {
        // MARK: - Variables

        let colorScheme: ColorScheme
        let contentColorScheme: ColorScheme
        @ViewBuilder let content: Content

        @Environment(\.toolbarVerticalEdge) private var verticalEdge
        @State private var hostsBars = false

        var body: some View {
            Group {
                if hostsBars || verticalEdge != nil {
                    // The bars draw in the stack's scheme and the content gets
                    // its own back, so only the bar's glass takes the tone.
                    NavigationStack {
                        MobileBrowserSideToolbarContent {
                            content
                                .environment(\.colorScheme, contentColorScheme)
                        }
                    }
                    .environment(\.colorScheme, colorScheme)
                } else {
                    content
                }
            }
            .onChange(of: verticalEdge, initial: true) { _, edge in
                if edge != nil { hostsBars = true }
            }
        }
    }

    /// The stack's root: it learns from the system which edge the bars prefer
    /// and tells the chrome below whether its controls are toolbar items.
    @available(iOS 27.1, *)
    private struct MobileBrowserSideToolbarContent<Content: View>: View {
        // MARK: - Variables

        @ViewBuilder let content: Content

        @Environment(\.toolbarVerticalEdge) private var verticalEdge

        var body: some View {
            let placement = MobileBrowserControlPlacement.fitting(verticalEdge: verticalEdge)
            content
                .environment(\.mobileBrowserControlPlacement, placement)
                .environment(\.mobileBrowserSideToolbarIsHosted, true)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarVisibility(placement.barVisibility, for: .navigationBar, .bottomBar)
                // Items in the side column still give the navigation bar a
                // top inset of its own; the display's top is already clear.
                .ignoresSafeArea(.container, edges: placement.movesControlsToToolbar ? .top : [])
        }
    }
#endif

extension EnvironmentValues {
    /// Whether a side toolbar host already wraps this view. A presentation
    /// starts a window's controls over, so it sets this back to false.
    @Entry var mobileBrowserSideToolbarIsHosted = false
}
