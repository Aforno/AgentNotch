#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
TAG="${1:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must contain a semantic version" >&2
  exit 1
fi

if [[ -n "$TAG" && "$TAG" != "v$VERSION" ]]; then
  echo "tag $TAG does not match VERSION v$VERSION" >&2
  exit 1
fi

echo "Version verified: $VERSION"
