#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p shared/abis
forge build >/dev/null

contracts=(
  StrategyVault
  StrategyHook
  YieldToken
  StrategyRegistry
  LendingAdapterMock
  SecondaryMarketMock
)

for c in "${contracts[@]}"; do
  in="out/${c}.sol/${c}.json"
  out="shared/abis/${c}.json"
  if [[ -f "$in" ]]; then
    jq '{abi: .abi}' "$in" > "$out"
    echo "exported $out"
  fi
done
