#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  LICENSE
  README.md
  SECURITY.md
  CONTRIBUTING.md
  CHANGELOG.md
  THIRD_PARTY_NOTICES.md
  VERSION
  .github/workflows/ci.yml
  .github/workflows/release.yml
)

for required_file in "${required_files[@]}"; do
  if [[ ! -s "$required_file" ]]; then
    echo "missing required public repository file: $required_file" >&2
    exit 1
  fi
done

for script in script/*.sh; do
  bash -n "$script"
  if [[ ! -x "$script" ]]; then
    echo "script is not executable: $script" >&2
    exit 1
  fi
done

for ignored_path in .build dist .firecrawl .grok; do
  if ! git check-ignore -q "$ignored_path/.agentsnotch-ignore-check"; then
    echo "generated path is not ignored: $ignored_path" >&2
    exit 1
  fi
done

if git ls-files | grep -Eq '(^|/)(\.build|dist|\.firecrawl|\.grok)(/|$)'; then
  echo "generated build or scrape output is tracked" >&2
  exit 1
fi

if rg -n --hidden \
  -g '!.git/**' \
  -g '!.build/**' \
  -g '!dist/**' \
  -g '!.firecrawl/**' \
  '(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' \
  .; then
  echo "possible embedded credential found" >&2
  exit 1
fi

local_path_matches="$(
  rg -n --hidden \
    -g '!.git/**' \
    -g '!.build/**' \
    -g '!dist/**' \
    -g '!.firecrawl/**' \
    '/Users/[A-Za-z0-9._-]+' \
    . \
    | rg -v '/Users/(demo|me|example)(/|"|$)' \
    || true
)"
if [[ -n "$local_path_matches" ]]; then
  printf '%s\n' "$local_path_matches"
  echo "developer-specific absolute path found" >&2
  exit 1
fi

if rg -n --hidden \
  -g '!.git/**' \
  -g '!.build/**' \
  -g '!dist/**' \
  -g '!.firecrawl/**' \
  -g '*.swift' \
  -g '*.md' \
  -g '*.sh' \
  -g '*.yml' \
  -g '*.yaml' \
  -g '*.json' \
  -g '*.toml' \
  '[[:blank:]]+$' \
  .; then
  echo "trailing whitespace found" >&2
  exit 1
fi

git diff --check
echo "Repository hygiene checks passed"
