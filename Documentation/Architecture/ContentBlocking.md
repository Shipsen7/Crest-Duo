# Content blocking

Fennavio's Balanced protection applies native WebKit content rules from public filter subscriptions.
The portable core owns each Space's on/off choice. Private Spaces retain their
own browsing boundaries; enabling a filter never moves website data between
Spaces. Chromium continues to use extensions for blocking.

## Bundled WebKit protection

`Config/FennavioFilters.json` lists the sources: EasyList, EasyPrivacy, uBlock
filters and Privacy, Unbreak, AdGuard Mobile Ads, EasyList Cookie Notices,
uBlock Cookie Notices and EasyList Germany. A reviewed snapshot is converted
into `CrestShared/Resources/FennavioProtection.json`, which ships with the app.
The app downloads filter data and converts it locally. It does not execute remote filter code.

`BrowserContentRuleListProvider` validates the content-derived identifiers,
compiles the bundled data with `WKContentRuleListStore`, and reuses the compiled
lists. New content receives new identifiers so an app update cannot reuse stale
rules. A build without Fennavio's resource retains the core's small baseline.
Invalid bundled data reports a preparation error instead of silently disabling
protection. Space-level changes apply through the existing content-blocking
controller and preserve separately installed extension lists.

The native rules cover network blocking and supported CSS element hiding,
including regional advertising and cookie notices. They do not reproduce
uBlock's scriptlets, procedural cosmetic rules, HTML rewriting or all network
modifiers. Compatibility and visual results require testing on the actual
sites. A site can still contain advertisements or empty advertising spaces.
The current Space's Page Actions menu can turn protection off if a site breaks.

## Subscription updates

Settings > Privacy > Content blocking offers six individually selectable
subscription groups, a manual update, the last installed rule update and rule
count. The core owns the device-wide selection in app preferences; it never
syncs. Each Space retains its independent protection switch. Selection-specific
caches prevent disabled sources from being restored by another selection's cache.
The packaged raw source snapshot allows offline selection changes, including
turning every subscription off, without substituting the full bundled list.

Ordinary WebKit launches check for due sources hourly while a scene is active.
Each source follows its own `Expires` header (days, hours or minutes), bounded
to one hour through seven days; missing or invalid metadata uses uBlock's
five-day default. `Diff-Expires` belongs to a differential-download protocol
and is not used for full downloads. Fresh sources are reused, and download
timestamps survive restart. Manual updates fetch all selected sources. Failed
checks retry no more than once per hour; suspended apps do not run a timer.
A due update runs when the app next becomes active. No subscription
network or storage is activated in previews or isolated validation launches.

`BrowserFilterListRepository` uses a credential-free ephemeral URL session with
no browser cookies or cache. It bounds downloads, resolves same-directory
includes and parses Safari/mobile conditions without evaluating code.
SafariConverterLib converts the combined sources on its own actor. Exception
directives are repeated in every partition so exceptions survive list boundaries.
Only native network and CSS rules are used; advanced scriptlets remain disabled.

On iOS, a separate isolated-world compatibility script recovers scrolling on
HTTPS Reddit pages when native cosmetic rules hide a consent dialog but cannot
apply the list's accompanying overflow repair. It closes only hidden consent
dialogs and temporarily repairs root overflow. Visible consent, sign-in and
other modal dialogs retain their scroll locks. The script never makes a consent
choice, reads form values or sends website data to the app or a server.

Every candidate must convert within platform limits and all partitions must
compile with WebKit before the snapshot is written atomically. Downloads,
conversion, compilation and persistence failures retain the previous filters;
the app bundle provides the offline baseline on first launch. Changing selection
rebuilds from the selected packaged sources before attempting network refresh. Corresponding raw
source data is retained beside the converted cache in application support.
Successful updates swap only app-owned lists on resident pages, applying on the
next navigation without reloading forms. The Space's core-owned protection
choice and independently installed extension rules remain authoritative.

The converter is a pinned GPLv3 runtime dependency. The source-file MPL notices
remain; distribution of the combined binary also needs GPLv3 compliance. See
`THIRD_PARTY_NOTICES.md` and the packaged filter notices before distributing.

## Refreshing the bundled fallback

Build the external `ConverterTool` from the exact SafariConverterLib revision
in `Config/FennavioFilters.json`, then run:

```sh
python3 Scripts/update-fennavio-filters.py --converter /path/to/ConverterTool
```

The generator pins GitHub inputs to their current commit, resolves local
include directives, evaluates Safari/mobile conditions and preserves original
source files and hashes under `ThirdParty/FennavioFilters`. It repeats exception
directives in every partition because WebKit exceptions cannot override rules
in another compiled list. It rejects conversion that discards rules at the
platform limit. Unsupported source syntax is counted in the manifest and does
not become executable JavaScript.

Review the source and generated diff, compile every list with WebKit, run the
retained content-blocking tests and license audit, then validate representative
sites. The bundled fallback is refreshed through app builds independently of the
in-app subscription cache. The same pinned converter is used for both paths.
Attribution and GPL notices ship in `FennavioFilterNotices.txt`; exact source
snapshots remain available with the corresponding source tree.
