# Fennavio native WebKit preview

This folder owns a standalone iPhone/iPad browsing app. The
`FennavioNativePreview` Xcode target compiles only these Swift sources and
Apple frameworks; it has no CrestCore, .NET, CrestShared, Chromium, CloudKit,
Crest browser storage, or other browser-app runtime dependency.

The preview provides normal tabs and Spaces, local tab/address restoration,
a distinct persistent WebKit website data store for each regular Space,
private tabs backed by a shared nonpersistent data store, address/search
navigation, WebKit back/forward/reload, and bottom-mounted controls.

Each app target has a **different bundle identifier**. The preview never
reads or migrates the installed Fennavio app's history, tabs, passwords, or
website data. It uses a versioned JSON state file in its own application
support directory. If that file cannot be decoded or has unknown schema,
launch stops rather than overwriting it. Deleting a Space records a durable
website-data deletion request and retries WebKit cleanup on the next launch
if the data store is still in use.

To build on macOS with a supported Xcode and XcodeGen:

```sh
xcodegen generate
xcodebuild -project Crest.xcodeproj -scheme FennavioNativePreview \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run `FennavioNativePreviewTests` on an iPhone/iPad simulator. Test folding,
rotation, keyboard entry, tabs, Space separation, private storage, web
navigation and tab recovery on the iPhone Duo before accepting changes.

This is **not** a substitute for the existing app yet. Important features
still to migrate and verify include encrypted credentials, bookmark/history
management, CloudKit Space sync and conflict recovery, the Brave content
blocker, downloads/uploads, browser permission workflows, popup handling,
migration of existing browsing data, accessibility and full device testing.
Do not replace the installed Fennavio target or merge as a production
cutover until these are implemented, tested, and explicitly approved.
