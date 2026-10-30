#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The same Foundation sources are compiled by SwiftPM and the iOS application.
swift test
find FennavioNative FennavioNativeTests -name '*.swift' -print0 |
  while IFS= read -r -d '' source; do swiftc -frontend -parse "$source"; done
# Full Apple SDK type checking and WebKit tests are performed by ci-apple.sh.
