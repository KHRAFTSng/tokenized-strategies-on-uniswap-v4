#!/usr/bin/env bash
set -euo pipefail

EXPECTED="${1:-78}"
COUNT="$(git rev-list --count HEAD)"

if [[ "$COUNT" -ne "$EXPECTED" ]]; then
  echo "commit count mismatch: expected $EXPECTED, got $COUNT" >&2
  exit 1
fi

echo "commit count OK: $COUNT"
