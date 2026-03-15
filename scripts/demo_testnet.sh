#!/usr/bin/env bash
set -euo pipefail

: "${BASE_SEPOLIA_RPC_URL:?missing BASE_SEPOLIA_RPC_URL}"
: "${PRIVATE_KEY:?missing PRIVATE_KEY}"
: "${INITIAL_OWNER:?missing INITIAL_OWNER}"
: "${UNDERLYING_ASSET:?missing UNDERLYING_ASSET}"
: "${POOL_MANAGER:?missing POOL_MANAGER}"

forge script script/10_DeployStrategySystem.s.sol:DeployStrategySystemScript \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast

echo "explorer_base_url=${EXPLORER_BASE_URL:-TBD}"
echo "tx_hashes: check broadcast/ folder output"
