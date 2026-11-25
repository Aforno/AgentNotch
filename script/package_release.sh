#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Agent Notch.app"
DMG_NAME="Agent-Notch-$VERSION-macOS-arm64.dmg"
SIGN_IDENTITY=""
USE_ADHOC=false
NOTARIZE=false
KEYCHAIN_PROFILE=""
API_KEY_PATH=""
API_KEY_ID=""
API_ISSUER_ID=""

usage() {
  cat >&2 <<'USAGE'
usage: package_release.sh (--identity IDENTITY | --adhoc) [--notarize]
                          [--keychain-profile PROFILE]
                          [--api-key-path PATH --api-key-id ID --api-issuer-id ID]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --adhoc)
      USE_ADHOC=true
      shift
      ;;
    --notarize)
      NOTARIZE=true
      shift
      ;;
    --keychain-profile)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --api-key-path)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      API_KEY_PATH="$2"
      shift 2
      ;;
    --api-key-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      API_KEY_ID="$2"
      shift 2
      ;;
    --api-issuer-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      API_ISSUER_ID="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -n "$SIGN_IDENTITY" && "$USE_ADHOC" == true ]]; then
  echo "choose either --identity or --adhoc" >&2
  exit 2
fi
if [[ -z "$SIGN_IDENTITY" && "$USE_ADHOC" != true ]]; then
  echo "release packaging requires --identity or an explicit --adhoc" >&2
  exit 2
fi
if [[ "$USE_ADHOC" == true ]]; then
  SIGN_IDENTITY="-"
fi
if [[ "$NOTARIZE" == true && "$SIGN_IDENTITY" == "-" ]]; then
  echo "notarization requires a Developer ID Application identity" >&2
  exit 2
fi
if [[ "$NOTARIZE" == true && -z "$KEYCHAIN_PROFILE" ]]; then
  if [[ -z "$API_KEY_PATH" || -z "$API_KEY_ID" || -z "$API_ISSUER_ID" ]]; then
    echo "notarization requires a keychain profile or all App Store Connect API key options" >&2
    exit 2
  fi
fi

"$ROOT_DIR/script/validate_version.sh"
"$ROOT_DIR/script/stage_app.sh" \
  --configuration release \
  --arch arm64 \
  --sign "$SIGN_IDENTITY"

WORK_DIR="$(mktemp -d "$DIST_DIR/.package.XXXXXX")"
IMAGE_ROOT="$WORK_DIR/image"
MOUNT_POINT="$WORK_DIR/mount"
DMG="$WORK_DIR/$DMG_NAME"
MOUNTED=false

cleanup() {
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_POINT" || return
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir "$IMAGE_ROOT" "$MOUNT_POINT"
ditto "$APP_BUNDLE" "$IMAGE_ROOT/Agent Notch.app"
ln -s /Applications "$IMAGE_ROOT/Applications"
hdiutil create -srcfolder "$IMAGE_ROOT" -volname "Agent Notch" \
  -fs HFS+ -format UDZO "$DMG"

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG"
MOUNTED=true
if [[ ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != /Applications ]]; then
  echo "disk image must contain an Applications shortcut" >&2
  exit 1
fi
"$ROOT_DIR/script/verify_release.sh" --app "$MOUNT_POINT/Agent Notch.app"
hdiutil detach "$MOUNT_POINT"
MOUNTED=false

if [[ "$USE_ADHOC" != true ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

if [[ "$NOTARIZE" == true ]]; then
  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
  else
    xcrun notarytool submit "$DMG" \
      --key "$API_KEY_PATH" \
      --key-id "$API_KEY_ID" \
      --issuer "$API_ISSUER_ID" \
      --wait
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
fi

hdiutil verify "$DMG"
(cd "$WORK_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
mv -f "$DMG" "$DMG.sha256" "$DIST_DIR/"
echo "Created $DIST_DIR/$DMG_NAME"
echo "Created $DIST_DIR/$DMG_NAME.sha256"
