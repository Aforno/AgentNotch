#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$ROOT_DIR/dist/Agents Notch.app"
ARCHIVE="$ROOT_DIR/dist/Agents-Notch-$VERSION-macOS-arm64.zip"
CHECKSUM="$ARCHIVE.sha256"
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

rm -f "$ARCHIVE" "$CHECKSUM"
"$ROOT_DIR/script/validate_version.sh"
"$ROOT_DIR/script/stage_app.sh" \
  --configuration release \
  --arch arm64 \
  --sign "$SIGN_IDENTITY"
"$ROOT_DIR/script/verify_release.sh" --app "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
unzip -tq "$ARCHIVE" >/dev/null

if [[ "$NOTARIZE" == true ]]; then
  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$ARCHIVE" --keychain-profile "$KEYCHAIN_PROFILE" --wait
  else
    xcrun notarytool submit "$ARCHIVE" \
      --key "$API_KEY_PATH" \
      --key-id "$API_KEY_ID" \
      --issuer "$API_ISSUER_ID" \
      --wait
  fi
  xcrun stapler staple "$APP_BUNDLE"
  "$ROOT_DIR/script/verify_release.sh" --app "$APP_BUNDLE" --require-notarized
  rm -f "$ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
  unzip -tq "$ARCHIVE" >/dev/null
fi

(cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
echo "Created $ARCHIVE"
echo "Created $CHECKSUM"
