# iPhone Duo browser adaptation — project brief

## Identity and origin

This repository is an **unofficial, independently maintained adaptation of the open-source [Crest browser](https://github.com/pauljoda/Crest), focused on the iPhone Duo**. It is **not** an official Crest release, and is not affiliated with or endorsed by the Crest project or Paul Davis. The repository name `Crest-Duo` identifies the GitHub fork; it is **not** approval to ship a modified app under Crest's protected product name, icons, bundle IDs or services. Before distributing a build, choose independent product branding and signing identifiers, follow [TRADEMARKS.md](TRADEMARKS.md), and retain MPL-2.0 attribution and third-party notices.

- **Upstream repository:** https://github.com/pauljoda/Crest
- **Preserved fork baseline (`main`):** `c27d743b929d43914e3a3d5daf8051871d0a1440` (same upstream commit when the project was initialized).
- **Feature branch:** `feature/duo-browser-ui`.
- **Current stage:** Project setup and requirements. This document does **not** mean the Duo UI, improved ad blocker or fork-specific iCloud sync has been implemented or tested.

## Product requirements

1. **Reachable bottom controls (required).** On the **unfolded iPhone Duo**, the address field and primary browser actions (Back, Forward, Tabs/Spaces and Menu) must stay at the **bottom**, not move to the iPad-style top chrome. Keep the folded phone experience comfortable too. Offer a stable user preference rather than deriving top versus bottom solely from screen size. Preserve useful tablet capabilities and responsive page space.
2. **Spaces are tab groups (required).** Retain Crest's Spaces, tabs, folders and existing browsing behavior. Maintain names, tab ownership, order and reopening/restoration. Respect the existing isolation of cookies, credentials, history, private browsing and website data per Space.
3. **Actual cross-device group synchronization (required).** Sync the Space structure and tab membership/order, not merely a list of remote open URLs. Reuse Crest's existing architecture and CloudKit sync pipeline where viable; **do not replace it without evidence**. A fork may require its **own** bundle ID, entitlements and CloudKit container; do not presume it can sync with the official Crest app or other browsers. Verify this explicitly on at least two devices, including offline edits and conflicts.
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

- Read [AGENTS.md](AGENTS.md), [the required Crest contribution skill](.agents/skills/crest-contribution/SKILL.md), [CONTRIBUTING.md](CONTRIBUTING.md), [RepositoryGuardrails](Documentation/RepositoryGuardrails.md), and [architecture](Documentation/ARCHITECTURE.md) **before touching app code**. Preserve their validation, release-note, versioning and coding conventions.
- The shared `CrestCore` owns Spaces, tabs and synchronization state. The Swift UI renders and sends intents; no direct mutation of shared session state.
- Keep the initial product changes focused on `CrestMobile` and necessary shared presentation/adapters. Do not modify Chromium host/engine inputs or published release workflows without a demonstrated need.
- Treat signing, certificates, GitHub Actions credentials, CloudKit entitlement changes, and distribution as **separate, security-sensitive tasks**. Never commit secrets, developer identifiers, access tokens, real browsing data or signing exports.
- For code changes, build with a supported macOS/Xcode/SDK environment and run the appropriate repository checks. Use an iPhone Duo simulator for layout where available, but do not claim real-device success without a real-device test.
- Make a focused commit/PR for each functional change. Report measured results and unresolved issues explicitly; do not describe planned or untested features as completed.
- Do not change the fork's preserved `main` baseline during project setup. Initial work happens on `feature/duo-browser-ui`.

## Initial setup checklist (scope limited to steps 1–3)

1. [x] Preserve and document the upstream baseline on `main`.
2. [x] Create the `feature/duo-browser-ui` branch.
3. [x] Document fork identity, requirements and Codex-specific instructions.
4. [ ] Create separate GitHub tasks for Duo bottom UI, content blocking, and CloudKit sync validation. **Not authorized in this setup stage.**
5. [ ] Review cloud macOS/Xcode build feasibility and CI configuration. **Not authorized in this setup stage.**

The original Crest README, license, trademark policy and instructions remain part of this fork. Their references to upstream releases, official app downloads and branding are **not** references to distributed builds of this adaptation.
