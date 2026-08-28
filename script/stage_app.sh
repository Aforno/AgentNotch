#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_NAME="Agent Notch"
EXECUTABLE_NAME="AgentsNotch"
BUNDLE_ID="com.afonsoferreira.AgentNotch"
MIN_SYSTEM_VERSION="14.0"
CONFIGURATION="debug"
BUILD_ARCH=""
SIGN_IDENTITY="-"

usage() {
  echo "usage: $0 [--configuration debug|release] [--arch arm64] [--sign IDENTITY]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BUILD_ARCH="$2"
      shift 2
      ;;
    --sign)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${AGENT_NOTCH_BUILD_NUMBER:-1}"
SPARKLE_PUBLIC_KEY_FILE="$ROOT_DIR/Resources/SparklePublicEDKey"
SPARKLE_FEED_URL="https://github.com/Aforno/AgentNotch/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="$(tr -d '[:space:]' < "$SPARKLE_PUBLIC_KEY_FILE")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must contain a semantic version" >&2
  exit 1
fi
if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]+=*$ ]]; then
  echo "Resources/SparklePublicEDKey must contain a base64 EdDSA public key" >&2
  exit 1
fi
python3 - "$SPARKLE_PUBLIC_KEY" <<'PY'
import base64, sys
key = sys.argv[1]
try:
    decoded = base64.b64decode(key)
except Exception as error:
    raise SystemExit(f"Sparkle public key is not valid base64: {error}") from error
if len(decoded) != 32:
    raise SystemExit(f"Sparkle public key must decode to 32 bytes, not {len(decoded)}")
PY
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "AGENT_NOTCH_BUILD_NUMBER must be a positive integer" >&2
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
HOOK_BINARY="$APP_RESOURCES/bin/agentnotch-hook"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ENTITLEMENTS="$ROOT_DIR/Resources/AgentsNotch.entitlements"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon/AppIcon.icns"
PROVIDER_ICONS_SOURCE="$ROOT_DIR/Sources/AgentsNotch/Resources/ProviderIcons.xcassets"

swift_arguments=(-c "$CONFIGURATION")
if [[ -n "$BUILD_ARCH" ]]; then
  swift_arguments+=(--arch "$BUILD_ARCH")
fi

cd "$ROOT_DIR"
swift build "${swift_arguments[@]}" --product "$EXECUTABLE_NAME"
swift build "${swift_arguments[@]}" --product AgentsNotchHook
BIN_DIR="$(swift build "${swift_arguments[@]}" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/bin" "$APP_CONTENTS/Frameworks"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_BINARY"
cp "$BIN_DIR/AgentsNotchHook" "$HOOK_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
cp -R "$PROVIDER_ICONS_SOURCE" "$APP_RESOURCES/ProviderIcons.xcassets"
chmod 0755 "$APP_BINARY" "$HOOK_BINARY"

SPARKLE_FRAMEWORK_SOURCE="$(
  python3 - "$ROOT_DIR" "$BIN_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
bin_dir = Path(sys.argv[2])
candidates = [
    bin_dir / "Sparkle.framework",
    *sorted(root.glob(".build/artifacts/**/Sparkle.xcframework/macos-*/Sparkle.framework")),
]
for candidate in candidates:
    if (candidate / "Sparkle").exists() or (candidate / "Versions/Current/Sparkle").exists():
        print(candidate)
        raise SystemExit(0)
raise SystemExit("Sparkle.framework was not found in the Swift build artifacts")
PY
)"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_CONTENTS/Frameworks/Sparkle.framework"

if ! otool -l "$APP_BINARY" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Agent Notch uses Apple Events to focus the terminal tab where an agent is running.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

sign_arguments=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  sign_arguments+=(--options runtime --timestamp)
fi

sign_sparkle_framework() {
  local framework="$APP_CONTENTS/Frameworks/Sparkle.framework"
  local version_dir="$framework/Versions/Current"
  if [[ ! -d "$version_dir" ]]; then
    version_dir="$framework"
  fi
  local nested
  while IFS= read -r nested; do
    codesign "${sign_arguments[@]}" "$nested"
  done < <(find "$version_dir/XPCServices" -name '*.xpc' -maxdepth 1 2>/dev/null | sort)
  if [[ -d "$version_dir/Updater.app" ]]; then
    codesign "${sign_arguments[@]}" "$version_dir/Updater.app"
  fi
  if [[ -f "$version_dir/Autoupdate" ]]; then
    codesign "${sign_arguments[@]}" "$version_dir/Autoupdate"
  fi
  codesign "${sign_arguments[@]}" "$framework"
}

sign_sparkle_framework
codesign "${sign_arguments[@]}" "$HOOK_BINARY"
codesign "${sign_arguments[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
