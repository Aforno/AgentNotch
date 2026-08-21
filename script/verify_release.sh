#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Agents Notch.app"
REQUIRE_NOTARIZED=false

usage() {
  echo "usage: $0 [--app PATH] [--require-notarized]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      APP_BUNDLE="$2"
      shift 2
      ;;
    --require-notarized)
      REQUIRE_NOTARIZED=true
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/AgentsNotch"
HOOK_BINARY="$APP_BUNDLE/Contents/Resources/bin/agentsnotch-hook"

for required_path in "$INFO_PLIST" "$APP_BINARY" "$HOOK_BINARY"; do
  if [[ ! -f "$required_path" ]]; then
    echo "missing release artifact: $required_path" >&2
    exit 1
  fi
done

if [[ ! -x "$APP_BINARY" || ! -x "$HOOK_BINARY" ]]; then
  echo "release executables must be executable" >&2
  exit 1
fi

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "bundle version $ACTUAL_VERSION does not match VERSION $EXPECTED_VERSION" >&2
  exit 1
fi

if ! APPLE_EVENTS_USAGE_DESCRIPTION="$(
  plutil -extract NSAppleEventsUsageDescription raw "$INFO_PLIST" 2>/dev/null
)" || [[ -z "$APPLE_EVENTS_USAGE_DESCRIPTION" ]]; then
  echo "release app must explain why it sends Apple events" >&2
  exit 1
fi

APP_FILE_DESCRIPTION="$(file "$APP_BINARY")"
HOOK_FILE_DESCRIPTION="$(file "$HOOK_BINARY")"
if [[ "$APP_FILE_DESCRIPTION" != *arm64* ]]; then
  echo "release app must contain an arm64 executable" >&2
  exit 1
fi
if [[ "$HOOK_FILE_DESCRIPTION" != *arm64* ]]; then
  echo "release hook must contain an arm64 executable" >&2
  exit 1
fi

# Do not use grep -q here: under pipefail it exits before strings finishes,
# strings receives SIGPIPE (141), and the condition incorrectly fails open.
if strings "$APP_BINARY" | grep -F 'Enable debug simulator' >/dev/null; then
  echo "release app contains debug-only simulator UI" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

APP_ENTITLEMENTS_PLIST="$(mktemp "${TMPDIR:-/tmp}/agentsnotch-entitlements.XXXXXX")"
trap 'rm -f "$APP_ENTITLEMENTS_PLIST"' EXIT
codesign --display --entitlements "$APP_ENTITLEMENTS_PLIST" --xml "$APP_BUNDLE" 2>/dev/null
if [[ "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.automation.apple-events' \
    "$APP_ENTITLEMENTS_PLIST" \
    2>/dev/null || true
)" != "true" ]]; then
  echo "release app must be signed with the Apple Events automation entitlement" >&2
  exit 1
fi

if [[ "$REQUIRE_NOTARIZED" == true ]]; then
  xcrun stapler validate "$APP_BUNDLE"
  spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
fi

echo "Release verification passed: $APP_BUNDLE"
