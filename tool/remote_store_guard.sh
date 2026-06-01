#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ALLOWED_IMPORT_PATHS_REGEX='^lib/core/remote_store/|^lib/core/di/injection_module\.dart$'

violations=0

check_pattern() {
  local pattern="$1"
  local title="$2"
  local matches
  matches="$(rg -n "$pattern" lib || true)"
  if [[ -z "$matches" ]]; then
    return
  fi

  while IFS= read -r line; do
    local file
    file="$(echo "$line" | cut -d: -f1)"
    if [[ ! "$file" =~ $ALLOWED_IMPORT_PATHS_REGEX ]]; then
      if [[ $violations -eq 0 ]]; then
        echo "Remote store guard violations:"
      fi
      echo "  [$title] $line"
      violations=$((violations + 1))
    fi
  done <<< "$matches"
}

check_pattern "\\.collection\\(" "raw collection call"
check_pattern "collection:\\s*['\\\"]" "raw collection literal"
check_pattern "remoteStoreClient\\.(getById|setDoc|updateDoc|deleteDoc|addDoc)\\(\\s*['\\\"]" "raw collection literal"

if [[ $violations -gt 0 ]]; then
  echo "Total Remote store guard violations: $violations"
  exit 1
fi

echo "Remote store guard passed."
