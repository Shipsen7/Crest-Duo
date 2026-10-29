# Fennavio native WebKit preview

This folder owns a standalone iPhone/iPad browsing app. The
`FennavioNativePreview` Xcode target compiles only these Swift sources and
Apple frameworks. It does not link CrestCore, .NET, CrestShared, Chromium,
CloudKit, or the currently installed Fennavio browser's data stores.

## Current behavior

- Normal tab groups (Spaces) and their tabs can be renamed/reordered, and
  tabs can be moved between groups with their live page and back/forward
  history intact. All **regular groups intentionally share** WebKit's default,
  persistent cookie/website store, as Safari-style tab groups do. Deleting
  a group does **not** clear cookies shared with the other groups.
- Private browsing uses an independent, nonpersistent WebKit store and never
  writes its tab records to the local state file. Ending a private session
  releases its page views and private store. Runtime/device acceptance is
  required before claiming all private-site data is cleared.
- The address bar upgrades explicit HTTP addresses to HTTPS without falling
  back to HTTP if TLS fails. The WebKit navigation delegate rejects HTTP,
  local files, unknown schemes and credential-bearing URLs in main-frame
  navigation. Embedded resources still follow WebKit's own security policy.
  Popup windows and external-app links remain blocked in this preview: the
  browser cannot yet complete every sign-in or bank-authorization flow.
- Local tab/group metadata is validated before loading and saved atomically
  in its own app sandbox. On iOS its directory and state file use Complete
  Data Protection, and the local state directory is excluded from device
  backups. Tab URLs and titles can be sensitive, so the unencrypted JSON
  format is never copied to a cloud transport automatically. A local JSON
  file with unsupported or unsafe contents stops startup instead of being
  overwritten. The earlier prototype may contain HTTP tabs; those require
  a separately reviewed recovery or clean preview reset.
- When the app becomes inactive, a privacy cover is requested so the app
  switcher does not ordinarily display its current webpage. Verify capture
  timing on a real device; this is not a guarantee against all screenshots.
- A navigation callback from a detached or closed WKWebView is ignored, rather
  than allowing stale page state to overwrite an active tab's stored URL.

The preview has a distinct bundle identifier,
`io.github.shipsen7.fennavio.native-preview`, so it never reads or replaces
installed Fennavio history, bookmarks, passwords, session or website data.
Older identifier-backed WebKit stores from earlier native preview iterations
are not silently merged into the shared regular store.

## Development and safety gates

To build on macOS with a supported Xcode and XcodeGen:

```sh
xcodegen generate
xcodebuild -project Crest.xcodeproj -scheme FennavioNativePreview \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The native preview is **not approved for real online banking**. Before using
it for sensitive accounts, run iOS/macOS SDK builds, Xcode tests and physical
Duo acceptance; test HTTPS redirects, invalid certificates, phishing-like
URLs, privacy after backgrounding, regular/private cookies, WebKit permission
prompts, passkeys, HTTP authentication, bank login/2FA, secure bank app handoff,
popups, file uploads/downloads, navigation recovery and restart behavior.
Never override WebKit's certificate validation or silently downgrade to HTTP.

There is **no CloudKit or Windows synchronization in this preview yet**.
The production replacement must sync groups, ordering, tab IDs, URLs, and
membership between Duo, iPad, Mac **and the Windows companion from the first
supported cross-platform release**. Design an authenticated, reviewed
cross-platform transport and a conflict-tolerant offline change log with
tombstones, account switching and restore semantics. Any data leaving Apple
devices for the Windows client requires a reviewed encryption and key-sharing
model. Private tabs, passwords, cookies, WebKit data and authentication
secrets must never be sent through group sync. Do not access, overwrite or
reinterpret the existing CrestCore CloudKit schema without a separate,
reviewed migration. Enable no new CloudKit entitlements or production writes
until the Apple and Windows identity and authorization paths are tested.

This target still lacks passwords/keychain integration, bookmark/history
management, complete permission/popup handling, passkeys, downloads and
uploads, Brave filtering, and production accessibility and device tests. Do
not replace the installed app, merge this as a production cutover, or claim
banking safety before those capabilities and acceptance checks are complete.
