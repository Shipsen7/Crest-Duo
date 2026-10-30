# Fennavio contribution guidance

This branch is a standalone SwiftUI/UIKit/WebKit iPhone/iPad application.
The maintainer explicitly removed the former multi-engine architecture. Do not
reintroduce it through modules, project generation, helper executables or CI.
Read README.md and Documentation/Architecture.md before changing ownership.

Keep code small and platform-native. Foundation models own validation and are
compiled unchanged by the app and SwiftPM tests. Main-actor session code owns
runtime lifetimes and privacy transitions. WebKit owns networking, certificates,
authentication and uploads. Never add a TLS bypass or a silent HTTP fallback.

Preserve legal attribution and Git history. Do not change production identifiers,
provisioning, entitlements, cloud schemas, main or releases without authorization.
Use the preview identifier for development. Private state must never be serialized.
Add durable tests for persistence, authorization and privacy boundaries, not
screenshots or brittle source-text assertions. Do not remove a failing test just
to obtain a green result. Test physical-device behavior before claiming it works.

Run Scripts/check.sh and, on macOS, Scripts/ci-apple.sh. Report actual results;
syntax parsing is not Apple SDK type checking. Maintain project.yml rather than
editing the generated Xcode project. Use swift format with .swift-format for
changed Swift files. Advance Config/Version.xcconfig's patch version and append
an entry to Documentation/ReleaseNotes.json for app/architecture changes. Do not
change distributed build numbers for routine commits.

Keep investigation logs, dated audit reports, screenshots and task-closeout
artifacts outside the source tree. Maintained product documentation belongs here;
validation evidence belongs in the commit/PR discussion. Changes are AI-assisted
when applicable; never describe untested work as banking-safe.
