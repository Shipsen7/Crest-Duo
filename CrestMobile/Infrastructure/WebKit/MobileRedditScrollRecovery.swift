import WebKit

/// Native content rules can hide Reddit's consent dialog without applying the
/// filter's accompanying overflow repair. Recover only an invisible consent
/// surface; visible sign-in, consent and other modal dialogs keep their input.
@MainActor
enum MobileRedditScrollRecovery {
    // MARK: - Static Variables

    static let script = WKUserScript(
        source: """
            (() => {
              const host = location.hostname.toLowerCase();
              if (location.protocol !== 'https:' ||
                  (host !== 'reddit.com' && !host.endsWith('.reddit.com'))) return;

              const consentSelector = '#data-protection-consent-dialog, shreddit-cookie-banner, ' +
                '[reddit-cookie-banner], shreddit-async-loader[bundlename="reddit_cookie_banner"]';
              const modalSelector = 'dialog[open], [aria-modal="true"], [role="dialog"], [role="menu"], .dialog-open';
              const repaired = new Map();
              const observedRoots = new WeakSet();
              const roots = new Set();
              let scheduled = false;

              const hidden = (element) => {
                const visibility = getComputedStyle(element).visibility;
                if (visibility === 'hidden' || visibility === 'collapse') return true;
                for (let node = element; node; node = node.parentElement || node.getRootNode().host) {
                  if (getComputedStyle(node).display === 'none') return true;
                }
                return false;
              };
              const restore = () => {
                for (const [element, original] of repaired) {
                  if (element.style.getPropertyValue('overflow-y') !== 'auto' ||
                      element.style.getPropertyPriority('overflow-y') !== 'important') continue;
                  if (original.value) element.style.setProperty('overflow-y', original.value, original.priority);
                  else element.style.removeProperty('overflow-y');
                }
                repaired.clear();
              };
              const recover = () => {
                scheduled = false;
                const consent = [...document.querySelectorAll(consentSelector)];
                for (const root of roots) {
                  if (root.host && !root.host.isConnected) roots.delete(root);
                }
                const modals = [...roots].flatMap((root) => [...root.querySelectorAll(modalSelector)]);
                if (!consent.some(hidden) || consent.some((element) => !hidden(element)) ||
                    modals.some((modal) => !hidden(modal))) {
                  restore();
                  return;
                }
                // A hidden native dialog may still occupy the modal top layer.
                // Closing it neither accepts cookies nor presses a page button.
                for (const modal of modals) {
                  if (!(modal instanceof HTMLDialogElement) || !modal.open || !hidden(modal)) continue;
                  for (let node = modal; node; node = node.parentElement || node.getRootNode().host) {
                    if (!consent.includes(node)) continue;
                    modal.close();
                    break;
                  }
                }
                for (const element of [document.documentElement, document.body]) {
                  if (!element) continue;
                  const overflow = getComputedStyle(element).overflowY;
                  if (overflow !== 'hidden' && overflow !== 'clip') continue;
                  if (!repaired.has(element)) repaired.set(element, {
                    value: element.style.getPropertyValue('overflow-y'),
                    priority: element.style.getPropertyPriority('overflow-y')
                  });
                  element.style.setProperty('overflow-y', 'auto', 'important');
                }
              };
              const schedule = () => {
                if (scheduled) return;
                scheduled = true;
                requestAnimationFrame(recover);
              };
              const discover = (root) => {
                const elements = root instanceof Element ? [root, ...root.querySelectorAll('*')] :
                  [...root.querySelectorAll('*')];
                for (const element of elements) {
                  if (!element.shadowRoot) continue;
                  observe(element.shadowRoot);
                  discover(element.shadowRoot);
                }
              };
              const observer = new MutationObserver((records) => {
                for (const record of records) {
                  for (const node of record.addedNodes) {
                    if (node instanceof Element) discover(node);
                  }
                }
                schedule();
              });
              const observe = (root) => {
                if (observedRoots.has(root)) return;
                observedRoots.add(root);
                roots.add(root);
                observer.observe(root, { childList: true, subtree: true, attributes: true,
                  attributeFilter: ['class', 'style', 'open', 'hidden', 'aria-modal'] });
              };
              observe(document.documentElement);
              discover(document.documentElement);
              schedule();
            })();
            """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true,
        in: .defaultClient
    )
}
