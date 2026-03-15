#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PIN_V4_PERIPHERY="3779387e5d296f39df543d23524b050f89a62917"
PIN_V4_CORE="59d3ecf53afa9264a16bba0e38f4c5d2231f80bc"

[[ -f foundry.lock ]] || { echo 'missing foundry.lock' >&2; exit 1; }
[[ -f package-lock.json ]] || { echo 'missing package-lock.json' >&2; exit 1; }

CURR_PERIPHERY="$(git -C lib/uniswap-hooks/lib/v4-periphery rev-parse HEAD)"
CURR_CORE="$(git -C lib/uniswap-hooks/lib/v4-core rev-parse HEAD)"

[[ "$CURR_PERIPHERY" == "$PIN_V4_PERIPHERY" ]] || { echo 'v4-periphery commit mismatch' >&2; exit 1; }
[[ "$CURR_CORE" == "$PIN_V4_CORE" ]] || { echo 'v4-core commit mismatch' >&2; exit 1; }

echo "dependency verification passed"
