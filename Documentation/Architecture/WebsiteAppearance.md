# Website appearance on iOS

The page menu offers **Website Dark Mode** for HTTP and HTTPS documents. It is
off until enabled for an exact origin in the current browsing profile. Switching
it changes the existing document without reloading, submitting forms or changing
navigation history. Disabling it restores the website's own appearance.

The app bundles the MIT-licensed Dark Reader API in `CrestMobile/Resources`.
Its version and source revision are declared in `Config/ThirdPartyDependencies.json`;
the matching license is shipped beside the JavaScript. The renderer is never
downloaded from a CDN at runtime. WebKit evaluates it in the isolated client
world, without a native network or script-message bridge.

Dark Reader can read the document's styles and request referenced stylesheets
through WebKit's ordinary CORS boundary, without cross-origin credentials or a
referrer. No Dark Reader update service is installed. Image analysis and the
page-world stylesheet proxy are disabled; image, video and canvas content retain
their original colors. Cross-origin embedded documents and inaccessible styles
can retain their native appearance. A website that supplies a suitable dark
theme can keep using it with the app's switch off.

`MobileWebsiteDarkModePreferences` keeps appearance choices locally by profile
and canonical origin. It stores origins, never page paths or form values. It
does not add a CloudKit record or change core browsing state. Private browsing
has a separate memory-only store that is cleared when its session closes.
Deleting a Space through the mobile store registry removes its saved choices.
Isolated validation launches use memory-only preferences.

Each page owns its renderer. The shared preference store notifies resident
renderers weakly; future navigations receive only the enabled origins belonging
to that profile. Updating app-owned startup scripts retains every other user
script, including extension scripts. A popup inherits its opener's script
controller instead of installing duplicate startup scripts.

Phone safe areas and side controls use WebKit's document-derived background and
matching foreground contrast. A site's theme meta tag is only a fallback, so a
light theme tag does not force a white strip beside a dark document.
