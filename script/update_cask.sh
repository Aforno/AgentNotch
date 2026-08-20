#!/usr/bin/env bash
# Point Casks/agents-notch.rb at a packaged GitHub release.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK="$ROOT_DIR/Casks/agents-notch.rb"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
CHECKSUM_FILE=""
SHA256=""

usage() {
  cat >&2 <<'USAGE'
usage: update_cask.sh [--version VERSION] [--checksum-file PATH | --sha256 HEX]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --checksum-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CHECKSUM_FILE="$2"
      shift 2
      ;;
    --sha256)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SHA256="$2"
      shift 2
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

if [[ -n "$SHA256" && -n "$CHECKSUM_FILE" ]]; then
  echo "choose either --checksum-file or --sha256" >&2
  exit 2
fi

if [[ -z "$SHA256" ]]; then
  if [[ -z "$CHECKSUM_FILE" ]]; then
    CHECKSUM_FILE="$ROOT_DIR/dist/Agents-Notch-$VERSION-macOS-arm64.zip.sha256"
  fi
  if [[ ! -f "$CHECKSUM_FILE" ]]; then
    echo "checksum file not found: $CHECKSUM_FILE" >&2
    exit 1
  fi
  SHA256="$(awk '{print $1}' "$CHECKSUM_FILE")"
fi
SHA256="$(printf '%s' "$SHA256" | tr '[:upper:]' '[:lower:]')"

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "sha256 must be 64 hex characters" >&2
  exit 1
fi

if [[ ! -f "$CASK" ]]; then
  echo "missing cask: $CASK" >&2
  exit 1
fi

python3 - "$CASK" "$VERSION" "$SHA256" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
text = path.read_text()


def version_key(value: str) -> tuple:
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)(.*)$", value)
    if not match:
        raise SystemExit(f"invalid semantic version: {value}")
    major, minor, patch, rest = match.groups()
    return (int(major), int(minor), int(patch), rest == "", rest)


current_match = re.search(r'^  version "([^"]+)"', text, flags=re.M)
if current_match is None:
    raise SystemExit("cask must contain one version stanza")
current_version = current_match.group(1)
if version_key(current_version) > version_key(version):
    print(f"Skipping cask downgrade {current_version} -> {version}")
    raise SystemExit(0)

updated, version_count = re.subn(
    r'^  version "[^"]+"',
    f'  version "{version}"',
    text,
    count=1,
    flags=re.M,
)
updated, sha_count = re.subn(
    r'^  sha256 "[^"]+"',
    f'  sha256 "{sha256}"',
    updated,
    count=1,
    flags=re.M,
)
if version_count != 1 or sha_count != 1:
    raise SystemExit("cask must contain one version stanza and one sha256 stanza")
if updated != text:
    path.write_text(updated)
print(f"Cask {path} -> {version} ({sha256})")
PY
