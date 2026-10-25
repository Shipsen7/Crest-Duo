# Fennavio

<img src="CrestShared/Resources/FennavioAssets.xcassets/FennavioPreview.imageset/icon.png" width="96" alt="Fennavio window-F app icon">

Fennavio is an independent, experimental browser project for iPhone, iPad and Mac,
based on the open-source [Crest browser](https://github.com/pauljoda/Crest).
It is not affiliated with or endorsed by Crest or Paul Davis.

The app is being prepared for personal use on the maintainer's own devices.
The source repository is public. No Fennavio app release is available.
The Duo layout, enhanced content blocking and synchronization with Fennavio's
own CloudKit container are requirements, not verified capabilities.

## Product direction

- Keep the address field and primary controls reachable at the bottom on an
  unfolded iPhone Duo, while preserving useful iPad and Mac behavior.
- Preserve Spaces, their tab organization and their privacy boundaries.
- Validate cross-device Space and tab synchronization on the fork's own Apple
  service identities.
- Evaluate compatible content-blocking extensions and maintained filter lists
  without breaking website functionality.

See [DUO_PROJECT.md](DUO_PROJECT.md) for maintained requirements and acceptance
criteria, [CONTRIBUTING.md](CONTRIBUTING.md) for development rules, and
[AGENTS.md](AGENTS.md) for AI-assisted work.

## Development and upstream updates

`main` is Fennavio's integration branch. Work on focused branches, review the
changes and run the affected checks before merging. Keep Crest connected as
`upstream` and follow the update process in [DUO_PROJECT.md](DUO_PROJECT.md).
Never replace the fork branch with an upstream snapshot or force a sync over
Fennavio's changes.

The internal `Crest*` directory, module and scheme names are retained to keep
upstream merges small. They identify implementation components, not the name
of an official distributed product. `project.yml` remains authoritative;
regenerate the Xcode project with `Scripts/bootstrap.sh`.

Development requires an Apple silicon Mac, Xcode with SDKs supporting the 26.1
deployment targets, XcodeGen and the .NET SDK pinned by `CrestCore/global.json`.
Use `CREST_ISOLATED_SESSION=1` for test launches.

## App identity and distribution

Fennavio must use its own name, app artwork, bundle identifiers, signing
identity, CloudKit container, update infrastructure and support channels.
Crest's managed Apple capabilities and service approvals do not transfer to
this fork. Register the fork's identities with the maintainer's own Apple
Developer team before signing a device build.

Inherited release, engine-publication and website-deployment workflows are
restricted to the original repository. They cannot publish Fennavio. Enabling
Fennavio distribution is a separate reviewed change after its branding,
licenses, signing, service configuration and platform validation are complete.
See the fork-specific notice in [Documentation/Distribution.md](Documentation/Distribution.md).

## Support and security

See [SUPPORT.md](SUPPORT.md) for the fork's support scope and
[SECURITY.md](SECURITY.md) for confidential security reporting.
Official Crest downloads, the Crest community and the Crest website are
upstream resources; they are not Fennavio downloads or support services.

The inherited GitHub Sponsor button supports Paul Davis's upstream work.
Donations through it do not fund Fennavio or imply upstream endorsement.

## License and attribution

The inherited source and modifications to covered files are available under
[MPL-2.0](LICENSE). Preserve [NOTICE](NOTICE), existing copyright and license
notices, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and component notices
under `ThirdParty/`. Crest's original code is Copyright 2026 Paul Davis.

Crest's name, app icon, logo and official distribution identity are governed by
[TRADEMARKS.md](TRADEMARKS.md), which grants no general trademark license.
Fennavio's proposed name and artwork require a separate rights review before
public app distribution. A future app release must identify where recipients
can obtain the corresponding MPL-covered source and its license.

The original project documentation is available in the
[upstream repository](https://github.com/pauljoda/Crest). Preserved engineering
documents describe inherited behavior and may require adaptation or validation
for Fennavio; they do not establish approval to use Crest's services.
