# Fennavio product and maintenance requirements

## Identity and scope

Fennavio is an independent adaptation of the open-source
[Crest browser](https://github.com/pauljoda/Crest) for iPhone, iPad and Mac,
with an emphasis on the iPhone Duo. It is not affiliated with or endorsed by
Crest or Paul Davis. The current purpose is personal installation on the
maintainer's own devices. Public source availability is distinct from app
publication. No published Fennavio build or verified Duo acceptance is claimed.

Preserve the MPL-2.0 notices and third-party attribution. Use independent
product artwork, signing, identifiers, Apple services, updates and support
before distributing a build, as required by [TRADEMARKS.md](TRADEMARKS.md).
Private signing must also keep Fennavio separate from the official app and its data.

## Product requirements

1. **Reachable bottom controls (required).** On the **unfolded iPhone Duo**, the address field and primary browser actions (Back, Forward, Tabs/Spaces and Menu) must stay at the **bottom**, not move to the iPad-style top chrome. Keep the folded phone experience comfortable too. Offer a stable user preference rather than deriving top versus bottom solely from screen size. Preserve useful tablet capabilities and responsive page space.
2. **Spaces are tab groups (required).** Retain Crest's Spaces, tabs, folders and existing browsing behavior. Maintain names, tab ownership, order and reopening/restoration. Respect the existing isolation of cookies, credentials, history, private browsing and website data per Space.
3. **Actual cross-device group synchronization (required).** Sync the Space structure and tab membership/order, not merely a list of remote open URLs. Reuse Crest's existing architecture and CloudKit sync pipeline where viable; **do not replace it without evidence**. Distributed modified builds must use their **own** bundle ID, signing identity and CloudKit container, with entitlements approved for that identity; do not presume it can sync with the official Crest app or other browsers. Verify this explicitly on at least two devices, including offline edits and conflicts.
4. **High-quality blocking (required).** Aim for blocking quality comparable to **Safari with uBlock Origin Lite** while preserving website functionality. First assess whether WebKit web-extension support permits a compatible, legally redistributable uBlock Origin Lite integration into Crest; do not assume drop-in compatibility. If not feasible, evaluate a mature rule-list/cosmetic-filter solution with regularly updated lists and documented tradeoffs. Keep filtering and its storage scoped correctly to Spaces.
5. **Sustainable maintenance (required).** Keep upstream updates feasible, minimize changes to CrestCore and engine adapters, and use the existing SwiftUI design system. Do not sacrifice security, privacy, compatibility or updates just to achieve a layout.

## Acceptance scenarios

- On an actual iPhone Duo, open and close the device, rotate it, open the keyboard, change Spaces and open the tab grid: the address field and core actions remain reachable at the bottom in the unfolded layout; controls avoid the keyboard, hinge and safe areas, with no loss of tab or navigation state.
- Create, rename, reorder and delete Spaces and their tabs on device A; verify the **group structure and tab membership** appear on device B, remain after restart, and behave correctly with offline edits. Private Spaces must **not** sync.
- Compare **Safari + uBlock Origin Lite**, unmodified Crest and this fork on:
  - https://www.notebookcheck.com/
  - https://www.gamestar.de/
  - https://maxroll.gg/
  Check advertising, cosmetic remnants, overlays, page speed and functionality. Do not break article reading, sign-ins, navigation or Maxroll's interactive builds/guides.
- Verify downloads, uploads, authentication, privacy boundaries, regular browsing, and application restoration before calling the fork usable as the daily browser.

## Engineering rules for Codex and other agents

- Read [AGENTS.md](AGENTS.md), [the required Crest contribution skill](.agents/skills/crest-contribution/SKILL.md), [CONTRIBUTING.md](CONTRIBUTING.md), [RepositoryGuardrails](Documentation/RepositoryGuardrails.md), and [architecture](Documentation/ARCHITECTURE.md) **before changing code, tests, documentation or pull request text**. Preserve their validation, release-note, versioning and coding conventions.
- The shared `CrestCore` owns Spaces, tabs and synchronization state. The Swift UI renders and sends intents; no direct mutation of shared session state.
- Keep the initial product changes focused on `CrestMobile` and necessary shared presentation/adapters. Do not modify Chromium host/engine inputs or published release workflows without a demonstrated need.
- Treat signing, certificates, GitHub Actions credentials, CloudKit entitlement changes, and distribution as **separate, security-sensitive tasks**. Never commit private keys, credentials, access tokens, real browsing data or signing exports. Public product identifiers belong in reviewed configuration; keep personal team and provisioning setup local.
- For code changes, build with a supported macOS/Xcode/SDK environment and run the appropriate repository checks. Use an iPhone Duo simulator for layout where available, but do not claim real-device success without a real-device test.
- Make a focused commit/PR for each functional change. Report measured results and unresolved issues explicitly; do not describe planned or untested features as completed.
- Use `main` as Fennavio's integration branch. Develop on focused branches and preserve the upstream commit history. Do not rename internal modules solely for product branding.

## Maintaining the upstream relationship

- Keep the original Git history and configure `upstream` to
  `https://github.com/pauljoda/Crest.git`. `main` contains the reviewed Fennavio
  integration; an unchanged upstream copy is not the fork's public landing page.
- Fetch upstream changes and review security advisories, release notes and the
  actual diff. Integrate a selected upstream revision on a focused update
  branch, resolve conflicts and validate the affected platforms before merging.
- For an urgent fix, review its dependencies before choosing a targeted
  cherry-pick or a full upstream merge. Do not claim security parity from a
  version number or an unattended sync alone.
- During every update, recheck Fennavio's identifiers, app artwork, signing,
  CloudKit, keychain namespaces, support links and disabled publication paths.
  Upstream must not restore official credentials, services or automatic updates.
- Keep independent product changes small. Preserve upstream licenses, required
  validation, versioning and release-note rules. Do not force-reset Fennavio's
  branch or rewrite published history as a shortcut to synchronization.
