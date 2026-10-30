#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Apple SDK validation requires macOS and Xcode." >&2; exit 1; }
phase="${1:-all}"
case "$phase" in
  all|build|test) ;;
  *) echo "Usage: $0 [all|build|test]" >&2; exit 2 ;;
esac
if [[ "$phase" != test ]]; then
  ./Scripts/bootstrap.sh
  ./Scripts/check.sh
  xcodebuild -version
  # Type-check both SDK targets before spending time booting a simulator.
  xcodebuild -project Fennavio.xcodeproj -scheme FennavioNativePreview \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
    CODE_SIGNING_ALLOWED=NO build-for-testing
  xcodebuild -project Fennavio.xcodeproj -scheme FennavioNativePreview \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
fi
[[ "$phase" != build ]] || exit 0
# Use a disposable simulator, never a person's installed app or existing simulator data.
selection="$(python3 - <<'PY'
import json, subprocess
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
valid = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['identifier']
         and tuple(map(int, r['version'].split('.'))) >= (26, 1)]
if not valid:
    raise SystemExit('Install an iOS 26.1 or newer simulator runtime in Xcode.')
runtime = max(valid, key=lambda r: tuple(map(int, r['version'].split('.'))))
types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
version = (tuple(map(int, runtime['version'].split('.'))) + (0, 0))[:3]
encoded = (version[0] << 16) | (version[1] << 8) | version[2]
phones = [t for t in types if t['name'].startswith('iPhone')
          and t.get('minRuntimeVersion', 0) <= encoded <= t.get('maxRuntimeVersion', 0xFFFFFFFF)]
if not phones:
    raise SystemExit('No compatible iPhone simulator device type is installed.')
print(phones[-1]['identifier'], runtime['identifier'])
PY
)"
read -r device_type runtime <<< "$selection"
device="$(xcrun simctl create "Fennavio Validation $$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  xcrun simctl delete "$device" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcodebuild -project Fennavio.xcodeproj -scheme FennavioNativePreview \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test-without-building
