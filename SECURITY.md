# Fennavio security policy

Fennavio is an independent experimental fork, currently intended for personal
use. There is no supported public Fennavio release or promised security-update
cadence. Upstream Crest security fixes must be reviewed, integrated and
validated for the fork; their existence does not automatically update an
installed Fennavio build.

## Confidential reporting

Do not publish suspected vulnerabilities, credentials, browsing data or private
URLs in public issues or discussions. No external Fennavio security contact is
advertised until a working confidential channel has been configured. That
channel must be established and documented before external distribution.

For a defect confirmed in upstream Crest, use upstream's own
[security policy](https://github.com/pauljoda/Crest/blob/main/SECURITY.md) and its
confidential reporting route. Do not send fork-only support requests there.

## Boundaries

Preserve Space isolation, Keychain separation, WebKit and Chromium security,
update verification, archive validation and CloudKit authorization. Use the
fork's own identities and isolated sessions for validation. Follow
[DUO_PROJECT.md](DUO_PROJECT.md) when integrating upstream security updates.
