import UIKit
import WebKit

/// Keeps WebKit's native editor through a same-scene layout handoff. The
/// selection stays inside WebKit; no form values or DOM references cross out.
@MainActor
final class MobileWebView: WKWebView {
    // MARK: - Static Variables

    private static let editorFocusRecovery = """
        (() => {
          let editor = document.activeElement;
          while (editor?.shadowRoot?.activeElement) editor = editor.shadowRoot.activeElement;
          if (!(editor instanceof HTMLElement) || !editor.isConnected ||
              (!editor.matches('input, textarea') && !editor.isContentEditable)) return false;
          const start = editor.selectionStart;
          const end = editor.selectionEnd;
          const direction = editor.selectionDirection;
          const selection = getSelection();
          const anchor = selection?.anchorNode;
          const focus = selection?.focusNode;
          const anchorOffset = selection?.anchorOffset;
          const focusOffset = selection?.focusOffset;
          editor.focus({ preventScroll: true });
          if (typeof start === 'number' && typeof end === 'number') {
            editor.setSelectionRange(start, end, direction);
          } else if (anchor && focus && editor.contains(anchor) && editor.contains(focus)) {
            selection.setBaseAndExtent(anchor, anchorOffset, focus, focusOffset);
          }
          return true;
        })();
        """
    // MARK: - Types

    private struct InputHandoff {
        weak var window: UIWindow?
        weak var scene: UIWindowScene?
        weak var responder: UIView?
        let selection: UITextRange?
        var isCurrent: @MainActor () -> Bool = { true }
        let id = UUID()
    }

    // MARK: - Variables

    private var inputHandoff: InputHandoff?
    private var dismissedInput: InputHandoff?
    private weak var keyboardResponder: UIView?

    // MARK: - Actions - Hosting

    func prepareForLayoutTransition(isCurrent: @escaping @MainActor () -> Bool = { true }) {
        captureInput(expiresAfter: 1, isCurrent: isCurrent)
    }

    func prepareForHostHandoff() {
        captureInput(expiresAfter: 0)
    }

    func rememberKeyboardFocus() {
        if let responder = firstResponder(in: self) { keyboardResponder = responder }
    }

    func keyboardWillHide() {
        guard let window, let responder = firstResponder(in: self) ?? keyboardResponder else { return }
        let handoff = InputHandoff(
            window: window, scene: window.windowScene, responder: responder,
            selection: (responder as? any UITextInput)?.selectedTextRange)
        dismissedInput = handoff
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.dismissedInput?.id == handoff.id else { return }
            self?.dismissedInput = nil
        }
    }

    private func captureInput(
        expiresAfter interval: TimeInterval, isCurrent: @escaping @MainActor () -> Bool = { true }
    ) {
        guard inputHandoff == nil else { return }
        var candidate: InputHandoff?
        if let window, let responder = firstResponder(in: self) {
            candidate = InputHandoff(
                window: window, scene: window.windowScene, responder: responder,
                selection: (responder as? any UITextInput)?.selectedTextRange)
        } else if interval > 0 {
            // A fold may hide the system keyboard before SwiftUI reports its
            // new width. Only that imminent layout can consume this snapshot.
            candidate = dismissedInput
        }
        if var handoff = candidate {
            handoff.isCurrent = isCurrent
            inputHandoff = handoff
            dismissedInput = nil
            let id = handoff.id
            // Ordinary tab removal expires next turn; an explicit layout
            // change allows its incoming full-screen presentation to mount.
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                guard self?.inputHandoff?.id == id else { return }
                self?.inputHandoff = nil
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resumeHostHandoff()
    }

    func resumeHostHandoff() {
        guard let window, let handoff = inputHandoff else { return }
        inputHandoff = nil
        // WebKit settles its old host's input session after UIKit's move.
        // Resume on the next turn, once that teardown has finished.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var owner: UIResponder? = next
            while let current = owner, !(current is UIViewController) { owner = current.next }
            if let transition = (owner as? UIViewController)?.transitionCoordinator {
                let registered = transition.animate(alongsideTransition: nil) { [weak self] context in
                    if !context.isCancelled { self?.restoreInput(handoff, in: window) }
                }
                if registered { return }
            }
            restoreInput(handoff, in: window)
        }
    }

    private func restoreInput(_ handoff: InputHandoff, in window: UIWindow) {
        guard self.window === window, handoff.isCurrent(),
            handoff.window === window || (handoff.scene != nil && handoff.scene === window.windowScene),
            let responder = handoff.responder, responder.isDescendant(of: self)
        else { return }
        if let current = firstResponder(in: window), !current.isDescendant(of: self) {
            return
        }
        guard responder.becomeFirstResponder() else { return }
        if let selection = handoff.selection, let input = responder as? any UITextInput {
            input.selectedTextRange = selection
        }
        // Regaining UIKit's responder does not necessarily resume WebKit's
        // software-keyboard session. Client script focus uses WebKit's public
        // input path; values and selection never leave the document.
        Task { @MainActor [weak self] in
            guard let self, self.window === window, handoff.isCurrent() else { return }
            _ = try? await evaluateJavaScript(Self.editorFocusRecovery, in: nil, in: .defaultClient)
        }
    }

    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let responder = firstResponder(in: child) { return responder }
        }
        return nil
    }
}
