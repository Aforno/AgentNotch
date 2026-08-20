#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_NAME="Agents Notch"
EXECUTABLE_NAME="AgentsNotch"
BUNDLE_ID="com.afonsoferreira.AgentsNotch"
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
BUILD_NUMBER="${AGENTS_NOTCH_BUILD_NUMBER:-1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must contain a semantic version" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "AGENTS_NOTCH_BUILD_NUMBER must be a positive integer" >&2
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
HOOK_BINARY="$APP_RESOURCES/bin/agentsnotch-hook"
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
mkdir -p "$APP_MACOS" "$APP_RESOURCES/bin"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_BINARY"
cp "$BIN_DIR/AgentsNotchHook" "$HOOK_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
cp -R "$PROVIDER_ICONS_SOURCE" "$APP_RESOURCES/ProviderIcons.xcassets"
chmod 0755 "$APP_BINARY" "$HOOK_BINARY"

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
  <string>Agents Notch uses Apple Events to focus the terminal tab where an agent is running.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sign_arguments=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  sign_arguments+=(--options runtime --timestamp)
fi

codesign "${sign_arguments[@]}" "$HOOK_BINARY"
codesign "${sign_arguments[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
