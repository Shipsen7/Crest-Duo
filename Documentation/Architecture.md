# Architecture and ownership

## Small native composition

`NativeBrowserSession` is the main-actor owner of tab/group state, the page
library, WebKit runtimes and downloads. Mutations of regular state validate and
save a copy before replacing the live model. Runtime removal follows successful
persistence, so a failed write does not silently close the only live page.
`NativeTabRuntime` owns one WebKit view, its observations and delegates. It
cancels pending dialog completions exactly once when detached. Queued callbacks
must still match their session's current runtime before changing state.

The SwiftPM target compiles the same `State/` sources as the iOS app; it does
not provide a second implementation. UIKit/WebKit integration tests run only
inside the iOS application test host. No third-party package is linked to the
app. XcodeGen is a development-time project generator, not a runtime component.

## Trust boundaries

`NativeBrowserAddress` validates navigation and persisted URLs. Local/executable
schemes and credential-bearing URLs never become main documents. Subframes
cannot navigate to HTTP or local/external schemes; inline blob/data/about frames
remain under WebKit's origin policy. Embedded subresources follow WebKit and ATS,
not an application-maintained network stack. Certificate challenges use default
platform handling, with no user exception path.

Only committed documents update saved URLs/history. WebKit observations refresh
back/forward/loading state and the conservative HTTPS indicator. Website text
and arbitrary transport error details are not trusted browser status messages.
A terminated content process requires explicit reload; forms are not replayed
automatically. Website-provided downloads never choose a filesystem directory.

Regular groups intentionally share the default website store; private tabs use
one independently owned nonpersistent store per private session. The schema-1
`pendingDataStoreDeletions` field is retained only to finish cleanup left by early
native preview versions with named stores. New group deletions never enqueue a
website-store deletion. This is not migration from the former browser's storage.

## Intentionally absent surfaces

No credential extraction, custom HTTP client, JavaScript message bridge,
certificate exceptions, telemetry, cloud writes, automatic filter download,
legacy update feed or executable plugin system is installed. This reduces code
that the app itself must maintain; it is not proof that the remaining code is
free of vulnerabilities. HTTPS does not establish that a site is trustworthy.

## Future platforms and synchronization

The first target is iPhone, with iPad layout support requiring separate device
acceptance. A native Mac target is separate future work, not a hidden Catalyst
promise. Cross-device group synchronization remains a future requirement,
including the Windows companion for the first supported cross-platform release.
Use a reviewed authenticated transport, encrypted metadata and key sharing,
conflict-tolerant offline changes, deletion tombstones and account isolation.
Never synchronize private tabs, passwords, cookies or website authentication
state. Do not reuse an old CloudKit schema or enable production capabilities
without an explicit migration, identity design and acceptance tests.
