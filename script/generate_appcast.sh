#!/usr/bin/env bash
# Sign a Sparkle appcast for the packaged GitHub release.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
ARCHIVE="$ROOT_DIR/dist/Agent-Notch-$VERSION-macOS-arm64.dmg"
OUTPUT=""
ED_KEY_FILE=""
DOWNLOAD_PREFIX=""
PREVIEW_UPDATES=false
SPARKLE_VERSION="2.9.6"
SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Aforno/AgentNotch}"

usage() {
  cat >&2 <<'USAGE'
usage: generate_appcast.sh [--archive PATH] [--output PATH] [--ed-key-file PATH]
                           [--download-url-prefix URL] [--preview-updates]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ARCHIVE="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    --ed-key-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ED_KEY_FILE="$2"
      shift 2
      ;;
    --download-url-prefix)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      DOWNLOAD_PREFIX="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --preview-updates)
      PREVIEW_UPDATES=true
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must contain a semantic version" >&2
  exit 1
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "release archive not found: $ARCHIVE" >&2
  exit 1
fi
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$(dirname "$ARCHIVE")/appcast.xml"
fi

PRIVATE_KEY=""
if [[ -n "$ED_KEY_FILE" ]]; then
  PRIVATE_KEY="$(tr -d '[:space:]' < "$ED_KEY_FILE")"
elif [[ "$PREVIEW_UPDATES" == true ]]; then
  PRIVATE_KEY="$(printf '%s' "${SPARKLE_PREVIEW_ED_PRIVATE_KEY:?missing preview update signing key}" | tr -d '[:space:]')"
elif [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  PRIVATE_KEY="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | tr -d '[:space:]')"
else
  echo "generate_appcast.sh requires SPARKLE_ED_PRIVATE_KEY or --ed-key-file" >&2
  exit 1
fi

printf '%s\n' "$PRIVATE_KEY" | python3 -c '
import base64, sys
try:
    decoded = base64.b64decode(sys.stdin.readline().strip(), validate=True)
except Exception as error:
    raise SystemExit(f"Sparkle private key is not valid base64: {error}") from error
if len(decoded) != 32:
    raise SystemExit(f"Sparkle private key must decode to 32 bytes, not {len(decoded)}")
'

if [[ "$PREVIEW_UPDATES" == true ]]; then
  # Sparkle signs with the seed even if it does not match the public key in the app.
  printf '%s\n' "$PRIVATE_KEY" | swift -e '
import CryptoKit
import Foundation

guard let input = readLine(),
      let seed = Data(base64Encoded: input),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
      key.publicKey.rawRepresentation.base64EncodedString() == CommandLine.arguments[1] else {
    FileHandle.standardError.write(Data("Preview Sparkle public and private keys do not match.\n".utf8))
    exit(1)
}
' "${SPARKLE_PREVIEW_ED_PUBLIC_KEY:?missing preview update public key}"
fi

TOOLS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentnotch-sparkle-tools.XXXXXX")"
ARCHIVES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentnotch-sparkle-archives.XXXXXX")"
cleanup() {
  rm -rf "$TOOLS_DIR" "$ARCHIVES_DIR"
}
trap cleanup EXIT

TARBALL="$TOOLS_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
curl -fsSL -o "$TARBALL" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
ACTUAL_SHA256="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$SPARKLE_TARBALL_SHA256" ]]; then
  echo "Sparkle tools tarball checksum mismatch: $ACTUAL_SHA256" >&2
  exit 1
fi
tar -xJf "$TARBALL" -C "$TOOLS_DIR"
GENERATE_APPCAST="$(find "$TOOLS_DIR" -name generate_appcast -type f | head -n 1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "generate_appcast was not in the Sparkle tools tarball" >&2
  exit 1
fi
chmod +x "$GENERATE_APPCAST"

cp "$ARCHIVE" "$ARCHIVES_DIR/$(basename "$ARCHIVE")"
if [[ -z "$DOWNLOAD_PREFIX" ]]; then
  if [[ "$PREVIEW_UPDATES" == true ]]; then
    DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/nightly-preview/"
  else
    DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/v${VERSION}/"
  fi
fi
printf '%s\n' "$PRIVATE_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --maximum-deltas 0 \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/${GITHUB_REPOSITORY}" \
  --disable-signing-warning \
  -o "$OUTPUT" \
  "$ARCHIVES_DIR"

if [[ ! -s "$OUTPUT" ]]; then
  echo "Sparkle appcast was not written: $OUTPUT" >&2
  exit 1
fi
if ! grep -q 'sparkle:edSignature=' "$OUTPUT"; then
  echo "Sparkle appcast is missing an EdDSA signature" >&2
  exit 1
fi
echo "Created $OUTPUT"
