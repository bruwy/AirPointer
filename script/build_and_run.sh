#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--build-only|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${AIRPOINTER_DERIVED_DATA:-$ROOT_DIR/DerivedData}"
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
/usr/bin/xcodebuild -version >/dev/null
cd "$ROOT_DIR"
if [[ "$MODE" != --build-only ]]; then
  pkill -x AirPointer >/dev/null 2>&1 || true
fi
/usr/bin/xcodebuild -project AirPointer.xcodeproj -scheme AirPointer \
  -configuration Debug -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" -jobs 1 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  'OTHER_CODE_SIGN_FLAGS=--options runtime' \
  ENABLE_DEBUG_DYLIB=NO COMPILER_INDEX_STORE_ENABLE=NO build
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/AirPointer.app"
case "$MODE" in
  --build-only) echo "Built: $APP_BUNDLE" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) /usr/bin/xcrun lldb -- "$APP_BUNDLE/Contents/MacOS/AirPointer" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "BSC.AirPointer"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x AirPointer >/dev/null
    ;;
esac
