#!/bin/bash
set -euo pipefail

KIRA_BUILD_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$KIRA_BUILD_ROOT/scripts/ios_xcode_environment.sh"
kira_prepare_xcode_tools "$KIRA_BUILD_ROOT"

exec /bin/sh "${FLUTTER_ROOT:?FLUTTER_ROOT is missing; run scripts/ios.sh setup first.}/packages/flutter_tools/bin/xcode_backend.sh" "$@"
