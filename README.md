# Fennavio — native WebKit browser

This branch contains an independent iPhone/iPad application built with SwiftUI,
UIKit and Apple's system WebKit. It has no runtime or build dependency on the
former Crest modules, .NET, Chromium, Sparkle, CloudKit or external Swift packages.
The former project, engines, helpers and publication workflows are not part of
this source tree. Attribution and license records remain; the Git history is
preserved.

## Build and run

Use macOS with Xcode, an iOS 26.1-or-newer SDK/runtime, and XcodeGen. Install
XcodeGen with `brew install xcodegen` when it is not already installed.

```sh
./Scripts/bootstrap.sh
open Fennavio.xcodeproj
```

Choose **FennavioNativePreview**, an iPhone simulator or your connected iPhone,
and Run. For a physical device, select your own development team in Signing &
Capabilities. No cloud container, app group, private SDK or other browser app is
required. The generated Xcode project is reproducible from `project.yml` and is
not checked in. Do not edit the generated project to make permanent changes.

The bundle identifier remains `io.github.shipsen7.fennavio.native-preview`.
It does not replace an installed non-preview Fennavio or read its saved data.
The preview name distinguishes this development app from an approved release.
A native macOS app and synchronization are not implemented by this target.

## Validation

```sh
./Scripts/check.sh       # Foundation model tests and Swift syntax checks
./Scripts/ci-apple.sh    # macOS: disposable iPhone simulator tests + Release device build
```

The Apple script creates and deletes its own simulator. It does not erase an
existing simulator or install over a physical device. GitHub Actions runs the
same script with read-only repository permissions and without signing secrets.
A successful model test or syntax check is **not** an Apple SDK build. Simulator
results are **not** physical-device acceptance or a security certification.

## Browsing behavior and safety boundaries

Regular tab groups share WebKit's persistent website store. Moving a tab keeps
its live page and history; deleting a group does not delete other groups'
cookies. Private browsing uses a separate nonpersistent store. Private tabs,
history and bookmarks are not written to the local model files. Ending the
private session detaches its pages, cancels downloads and replaces that store.
A file deliberately exported to Files is an independent copy and is not removed
by ending private browsing.

Main pages are HTTPS-only, apart from an internal blank tab. Typed HTTP addresses
are upgraded without HTTP fallback. Certificate decisions stay with WebKit;
there is no bypass. An HTTPS indicator requires a committed, nonloading page
with server trust and only secure content; it does not certify a website's
identity or honesty. External-app schemes remain blocked, so some bank/2FA app
handoffs do not yet work. WebKit owns file uploads and authentication.

JavaScript dialogs identify the requesting security origin and are limited to
the foreground selected tab. Tab changes, closing and backgrounding dismiss
outstanding site dialogs. A window-level privacy cover also covers app sheets
when the app resigns active; device testing must verify snapshot timing. This
is not protection against every screenshot or a compromised operating system.

Downloads require user initiation and a secure origin, final response and
redirects. Generated blob downloads require a secure source frame. Files receive
bounded, sanitized names in protected temporary folders, never arbitrary paths.
Transfers are bounded in number; their file sizes are not capped. Temporary
files are purged at startup. Failed private-file removal is not a promise of
forensic erasure. Some asynchronous site-generated downloads may be refused.

State files have size, schema, identity and URL validation. Corruption,
unsupported data or inaccessible protected files are surfaced without resetting
them. Writes are atomic with iOS Complete Data Protection; local model storage
is excluded from backups. Retry startup after unlocking instead of deleting data.
WebKit manages its own website storage separately.

## Content blocking

The app bundles the pinned Brave iOS WebKit baseline and compiles it before the
first page. A compilation failure requires an explicit choice before browsing
without blocking. This is **not full Brave Shields**, an automatic filter
subscription service or a guarantee of GameStar compatibility. The unmodified
resource and provenance notice are retained. See `ThirdParty/BraveIOSProtection-NOTICE.txt`
for the distribution/license-review caveat.

## Release gate and maintenance

This remains a development build, not approved for real banking. Before using
sensitive accounts, validate invalid/expired certificates, redirect downgrade
attempts, deceptive addresses, popups, file uploads/downloads, authentication,
passkeys, bank 2FA, private/regular separation, background snapshots including
sheets, process termination, restart and both device postures on the actual
phone. Use test accounts, not live payment flows. Test iPad separately.

Keep iOS updated for system WebKit fixes. Review changes to the small native
session, URL policy, persistence and download code: OS updates do not repair
application-level logic mistakes. Keep the workflow action pinned, review
Dependabot changes, and update the bundled filter only with provenance and
WebKit compilation checks. Avoid adding custom networking, certificate handling,
credential storage, remote scripts or native JavaScript bridges.

See `Documentation/Architecture.md` for ownership and future platform boundaries.
`LICENSE`, `NOTICE`, `TRADEMARKS.md` and `Legal/LegacyThirdPartyNotices.md` retain
historical attribution; they do not imply linked legacy dependencies.
