#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || {
  echo "Install XcodeGen (brew install xcodegen), then run this script again." >&2
  exit 1
}
xcodegen generate --spec project.yml
