import SwiftUI
import UIKit

/// Coordinates the system's side controls on the closed front display with
/// bottom controls on the expanded phone, without replacing the page hierarchy.
struct MobileBrowserSideToolbarHost: ViewModifier {
    // MARK: - Variables

    /// The browser whose shown Space's tone the bar's glass follows. It is
    /// read here rather than by the view that applies this, so a change to the
    /// window never rebuilds that view in the middle of a change it is making.
    var browser: BrowserStore?
    var page: MobileBrowserPage?
    /// The scheme the bar's glass follows where no browser is given, or nil
    /// for the system's.
    var colorScheme: ColorScheme?

    @Environment(\.mobileBrowserSideToolbarIsHosted) private var isHosted
    @Environment(\.colorScheme) private var contentColorScheme

    private var barColorScheme: ColorScheme {
        pageBackground?.colorScheme ?? spaceColorScheme
    }

    private var spaceColorScheme: ColorScheme {
        browser?.shownSpace?.settings.look.colorScheme(over: contentColorScheme) ?? colorScheme ?? contentColorScheme
    }

    private var pageBackground: MobileBrowserPageBackground? {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
        return MobileBrowserPageBackground(page: page)
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        if isHosted {
            content
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            #if canImport(SwiftUICore, _version: 8.0.85)
                if #available(iOS 27.1, *) {
                    MobilePhoneSideToolbarStack(
                        colorScheme: barColorScheme,
                        spaceColorScheme: spaceColorScheme,
                        backgroundColor: pageBackground?.color,
                        shownTabID: browser?.shownTab?.id,
                        activeSpaceName: browser?.shownSpace?.settings.name
                    ) {
                        content.environment(\.colorScheme, contentColorScheme)
                    }
                } else {
                    phoneContent(content)
                }
            #else
                phoneContent(content)
            #endif
        } else {
            #if canImport(SwiftUICore, _version: 8.0.85)
                if #available(iOS 27.1, *) {
                    MobileBrowserSideToolbarStack(
                        colorScheme: barColorScheme,
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

    private func phoneContent(_ content: Content) -> some View {
        content
            .environment(\.mobileBrowserControlPlacement, .bottom)
            .environment(\.mobileBrowserSideToolbarIsHosted, true)
            .modifier(MobilePhoneSystemBars(shownTabID: browser?.shownTab?.id))
    }

}

#if canImport(SwiftUICore, _version: 8.0.85)
    /// A stable stack: folding changes toolbar placement, never its content's identity.
    @available(iOS 27.1, *)
    private struct MobilePhoneSideToolbarStack<Content: View>: View {
        // MARK: - Variables

        let colorScheme: ColorScheme
        let spaceColorScheme: ColorScheme
        let backgroundColor: UIColor?
        let shownTabID: UUID?
        let activeSpaceName: String?
        @ViewBuilder let content: Content
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            NavigationStack {
                MobileBrowserSideToolbarContent(prefersBottomControls: true) {
                    content
                }
                .toolbarBackground(
                    backgroundColor.map { Color(uiColor: $0) } ?? Color(uiColor: .systemBackground),
                    for: .navigationBar, .bottomBar
                )
                .toolbarBackgroundVisibility(
                    backgroundColor == nil ? .automatic : .visible, for: .navigationBar, .bottomBar
                )
            }
            .toolbarVerticalBehavior(horizontalSizeClass == .compact ? .automatic : .disabled)
            .modifier(
                MobilePhoneSystemBars(
                    shownTabID: shownTabID,
                    activeSpaceName: activeSpaceName,
                    spaceColorScheme: spaceColorScheme,
                    keepsStatusBarVisible: horizontalSizeClass == .compact
                )
            )
            .environment(\.colorScheme, colorScheme)
        }
    }

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

        var prefersBottomControls = false
        @ViewBuilder let content: Content

        @Environment(\.toolbarVerticalEdge) private var verticalEdge

        var body: some View {
            let placement =
                verticalEdge == nil && prefersBottomControls
                ? MobileBrowserControlPlacement.bottom
                : MobileBrowserControlPlacement.fitting(verticalEdge: verticalEdge)
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

/// The phone's status band follows page scrolling without owning browsing state.
private struct MobilePhoneSystemBars: ViewModifier {
    // MARK: - Variables

    let shownTabID: UUID?
    var activeSpaceName: String? = nil
    var spaceColorScheme: ColorScheme? = nil
    var keepsStatusBarVisible = false
    @State private var hidesStatusBar = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            phoneContent(content)
                .toolbarVisibility(
                    hidesStatusBar && !keepsStatusBarVisible ? .hidden : .automatic,
                    for: .statusBar
                )
        } else {
            phoneContent(content)
                .statusBarHidden(hidesStatusBar && !keepsStatusBarVisible)
        }
    }

    private func phoneContent(_ content: Content) -> some View {
        content
            .overlay {
                if !keepsStatusBarVisible, !hidesStatusBar, let activeSpaceName {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activeSpaceName)
                            .font(.headline)
                            .foregroundStyle(CrestBrandTheme.textDisplay)
                            .environment(\.colorScheme, spaceColorScheme ?? colorScheme)
                            .lineLimit(1)
                            .padding(.leading, CrestSpacing.section)
                            .padding(.trailing, MobileBrowserRootLayout.expandedHeaderTrailingClearance)
                            .padding(.top, CrestSpacing.extraExtraLarge)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .environment(\.mobileBrowserPageScrollChanged) { hides in
                guard hidesStatusBar != hides else { return }
                withAnimation(CrestMotion.toolbar.unlessReducingMotion(reduceMotion)) { hidesStatusBar = hides }
            }
            .onChange(of: shownTabID) { hidesStatusBar = false }
    }
}

extension EnvironmentValues {
    /// Only the phone shell supplies this transient presentation action.
    @Entry var mobileBrowserPageScrollChanged: ((Bool) -> Void)?
}
