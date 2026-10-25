#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

required_paths=(
  CrestShared
  CrestMac
  CrestMobile
  CrestTests
  CrestMobileTests
  CrestTestFixtures
  Documentation/ARCHITECTURE.md
  CrestShared/Resources/FennavioAssets.xcassets/Fennavio.appiconset
  project.yml
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    print -u2 "Missing required Crest path: $required_path"
    exit 1
  fi
done

prototype_root="Bro""wser"
prototype_tests="${prototype_root}Tests"
prototype_ui_tests="${prototype_root}UITests"
prototype_project="${prototype_root}.xcodeproj"

if [[ -e "$prototype_root" || -e "$prototype_tests" || -e "$prototype_ui_tests" || -e "$prototype_project" ]]; then
  print -u2 "A prototype-named top-level project path still exists."
  exit 1
fi

prototype_product="cae""lura"
prototype_bundle="com.pauldavis.${prototype_root:l}"
prototype_environment="${prototype_root:u}_"
prototype_import="@testable import ${prototype_root}"

if rg -n -i \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "${prototype_product}|${prototype_bundle}|${prototype_project}|${prototype_import}" \
  .; then
  print -u2 "Prototype product identity remains in the repository."
  exit 1
fi

if rg -n \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "(^|[^[:alnum:]_])${prototype_environment}" \
  .; then
  print -u2 "Prototype launch environment remains in the repository."
  exit 1
fi

rg -q '^name: Crest$' project.yml
rg -q '^  Crest:$' project.yml
rg -q '^  CrestMobile:$' project.yml
rg -q 'CREST_MAC_BUNDLE_IDENTIFIER: io\.github\.shipsen7\.fennavio$' project.yml
rg -q 'CREST_MOBILE_BUNDLE_IDENTIFIER: io\.github\.shipsen7\.fennavio$' project.yml
rg -q 'PRODUCT_MODULE_NAME: Crest$' project.yml
rg -q 'PRODUCT_MODULE_NAME: CrestMobile$' project.yml

# The fork must never silently regain upstream Apple services or update trust.
python3 - <<'PYTHON'
import plistlib
from pathlib import Path

identity = "io.github.shipsen7.fennavio"
for platform, filename in (("CrestMac", "Crest"), ("CrestMobile", "CrestMobile")):
    configuration = Path(platform) / "Configuration"
    with (configuration / (filename + "-Info.plist")).open("rb") as stream:
        info = plistlib.load(stream)
    with (configuration / (filename + ".entitlements")).open("rb") as stream:
        entitlements = plistlib.load(stream)
    assert info["CFBundleDisplayName"] == "Fennavio", "Incorrect product display name"
    assert info["CrestCloudKitContainerIdentifier"] == "iCloud." + identity, "Incorrect CloudKit configuration"
    assert entitlements["com.apple.developer.icloud-container-identifiers"] == ["iCloud." + identity], "Incorrect CloudKit entitlement"
    assert entitlements["keychain-access-groups"] == ["$(AppIdentifierPrefix)" + identity], "Incorrect keychain group"
    assert not entitlements.get("com.apple.developer.web-browser"), "The fork needs its own browser approval"
    assert not entitlements.get("com.apple.developer.web-browser.public-key-credential"), "The fork needs its own passkey approval"
    if platform == "CrestMac":
        assert not info.get("SUFeedURL") and not info.get("SUPublicEDKey"), "Private builds have no publisher trust"
        assert info.get("SUEnableAutomaticChecks") is False and info.get("SUAutomaticallyUpdate") is False
    else:
        assert info.get("CrestBrowserPasskeyManagedCapability") is False
        assert info.get("CrestSystemPasswordWriteThroughManagedCapability") is False
        schemes = [scheme for entry in info["CFBundleURLTypes"] for scheme in entry["CFBundleURLSchemes"]]
        assert "fennavio" in schemes and "crest" not in schemes, "Incorrect shared-link identity"
PYTHON

print "Fennavio identity validation passed."
