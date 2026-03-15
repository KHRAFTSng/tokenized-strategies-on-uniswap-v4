#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PIN_V4_PERIPHERY="3779387e5d296f39df543d23524b050f89a62917"
PIN_V4_CORE="59d3ecf53afa9264a16bba0e38f4c5d2231f80bc"

printf '[bootstrap] initializing git submodules\n'
git submodule update --init --recursive

printf '[bootstrap] pinning uniswap dependencies\n'
git -C lib/uniswap-hooks/lib/v4-periphery fetch --all --tags >/dev/null 2>&1 || true
git -C lib/uniswap-hooks/lib/v4-core fetch --all --tags >/dev/null 2>&1 || true
git -C lib/uniswap-hooks/lib/v4-periphery checkout "$PIN_V4_PERIPHERY" >/dev/null
git -C lib/uniswap-hooks/lib/v4-core checkout "$PIN_V4_CORE" >/dev/null
git -C lib/uniswap-hooks/lib/v4-periphery/lib/v4-core checkout "$PIN_V4_CORE" >/dev/null

CURR_PERIPHERY="$(git -C lib/uniswap-hooks/lib/v4-periphery rev-parse HEAD)"
CURR_CORE="$(git -C lib/uniswap-hooks/lib/v4-core rev-parse HEAD)"

if [[ "$CURR_PERIPHERY" != "$PIN_V4_PERIPHERY" ]]; then
  echo "[bootstrap] v4-periphery pin mismatch" >&2
  exit 1
fi

if [[ "$CURR_CORE" != "$PIN_V4_CORE" ]]; then
  echo "[bootstrap] v4-core pin mismatch" >&2
  exit 1
fi

printf '[bootstrap] running foundry build\n'
forge build

printf '[bootstrap] done\n'
