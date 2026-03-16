#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

RPC_URL="${unichain_SEPOLIA_RPC_URL:-${SEPOLIA_RPC_URL:-${BASE_SEPOLIA_RPC_URL:-}}}"
PRIVATE_KEY_VAL="${SEPOLIA_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
OWNER="${OWNER_ADDRESS:-${INITIAL_OWNER:-}}"
POOL_MANAGER_VAL="${POOL_MANAGER_ADDRESS:-${POOL_MANAGER:-}}"
CHAIN_ID_VAL="${SEPOLIA_CHAIN_ID:-1301}"
EXPLORER_TX_BASE="${EXPLORER_BASE_URL:-https://unichain-sepolia.blockscout.com/tx/}"

if [[ -z "${RPC_URL}" || -z "${PRIVATE_KEY_VAL}" || -z "${OWNER}" || -z "${POOL_MANAGER_VAL}" ]]; then
  echo "missing required env vars: RPC, private key, owner, pool manager" >&2
  exit 1
fi

upsert_env() {
  local key="$1"
  local value="$2"
  touch .env
  if grep -q "^${key}=" .env; then
    perl -0777 -i -pe "s#^${key}=.*#${key}=${value}#mg" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

print_tx() {
  local label="$1"
  local hash="$2"
  echo "${label}: ${hash}"
  echo "${label}_url: ${EXPLORER_TX_BASE}${hash}"
}

send_tx() {
  local label="$1"
  shift
  local tx_hash
  tx_hash="$(cast send "$@" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY_VAL" --json | jq -r '.transactionHash')"
  print_tx "$label" "$tx_hash"
}

call_value() {
  cast call "$@" --rpc-url "$RPC_URL" | awk '{print $1}'
}

echo "== Phase 1: Deploy demo underlying token =="
DEPLOY_TOKEN_OUT="$(forge create src/mocks/DemoERC20.sol:DemoERC20 --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY_VAL" --broadcast --constructor-args "Demo USD" "dUSD" "$OWNER" 2>&1)"
echo "$DEPLOY_TOKEN_OUT"
UNDERLYING_ASSET_VAL="$(echo "$DEPLOY_TOKEN_OUT" | awk '/Deployed to:/{print $3}' | tail -n1)"
UNDERLYING_DEPLOY_TX="$(echo "$DEPLOY_TOKEN_OUT" | awk '/Transaction hash:/{print $3}' | tail -n1)"
if [[ -z "$UNDERLYING_ASSET_VAL" ]]; then
  echo "failed to deploy DemoERC20" >&2
  exit 1
fi
echo "UNDERLYING_ASSET=${UNDERLYING_ASSET_VAL}"
if [[ -n "$UNDERLYING_DEPLOY_TX" ]]; then
  print_tx "deploy_demo_underlying" "$UNDERLYING_DEPLOY_TX"
fi

echo "== Phase 2: Deploy strategy system =="
INITIAL_OWNER="$OWNER" UNDERLYING_ASSET="$UNDERLYING_ASSET_VAL" POOL_MANAGER="$POOL_MANAGER_VAL" \
  forge script script/10_DeployStrategySystem.s.sol:DeployStrategySystemScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY_VAL" \
  --broadcast

DEPLOY_RUN_FILE="broadcast/10_DeployStrategySystem.s.sol/${CHAIN_ID_VAL}/run-latest.json"
if [[ ! -f "$DEPLOY_RUN_FILE" ]]; then
  echo "missing deploy broadcast file: $DEPLOY_RUN_FILE" >&2
  exit 1
fi

VAULT_ADDRESS="$(jq -r '.transactions[] | select(.contractName=="StrategyVault") | .contractAddress' "$DEPLOY_RUN_FILE" | tail -n1)"
YTOKEN_ADDRESS="$(cast call "$VAULT_ADDRESS" "yieldToken()(address)" --rpc-url "$RPC_URL" 2>/dev/null || true)"
HOOK_ADDRESS="$(jq -r '.transactions[] | select(.contractName=="StrategyHook") | .contractAddress' "$DEPLOY_RUN_FILE" | tail -n1)"
REGISTRY_ADDRESS="$(jq -r '.transactions[] | select(.contractName=="StrategyRegistry") | .contractAddress' "$DEPLOY_RUN_FILE" | tail -n1)"
LENDING_ADDRESS="$(jq -r '.transactions[] | select(.contractName=="LendingAdapterMock") | .contractAddress' "$DEPLOY_RUN_FILE" | tail -n1)"
SECONDARY_ADDRESS="$(jq -r '.transactions[] | select(.contractName=="SecondaryMarketMock") | .contractAddress' "$DEPLOY_RUN_FILE" | tail -n1)"

for var in VAULT_ADDRESS YTOKEN_ADDRESS HOOK_ADDRESS REGISTRY_ADDRESS LENDING_ADDRESS SECONDARY_ADDRESS; do
  if [[ -z "${!var}" || "${!var}" == "null" ]]; then
    echo "missing ${var} from deployment output" >&2
    exit 1
  fi
done

upsert_env UNDERLYING_ASSET "$UNDERLYING_ASSET_VAL"
upsert_env STRATEGY_VAULT "$VAULT_ADDRESS"
upsert_env YIELD_TOKEN "$YTOKEN_ADDRESS"
upsert_env STRATEGY_HOOK "$HOOK_ADDRESS"
upsert_env STRATEGY_REGISTRY "$REGISTRY_ADDRESS"
upsert_env LENDING_ADAPTER "$LENDING_ADDRESS"
upsert_env SECONDARY_MARKET "$SECONDARY_ADDRESS"
upsert_env POOL_MANAGER "$POOL_MANAGER_VAL"
upsert_env INITIAL_OWNER "$OWNER"

echo "== Deployment addresses =="
echo "underlying: $UNDERLYING_ASSET_VAL"
echo "vault: $VAULT_ADDRESS"
echo "yToken: $YTOKEN_ADDRESS"
echo "hook: $HOOK_ADDRESS"
echo "registry: $REGISTRY_ADDRESS"
echo "lending: $LENDING_ADDRESS"
echo "secondary: $SECONDARY_ADDRESS"

echo "== Deployment tx hashes =="
jq -r '.transactions[]?.hash' "$DEPLOY_RUN_FILE" | while read -r h; do
  [[ -n "$h" && "$h" != "null" ]] && print_tx "deploy_tx" "$h"
done

echo "== Phase 3: User-perspective demo flow =="
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"
DEPOSIT_AMOUNT="1000000000000000000000"        # 1000
FEE_YIELD_AMOUNT="50000000000000000000"         # 50
RESERVE_AMOUNT="100000000000000000000"          # 100
NOTIONAL_AMOUNT="5000000000000000000000"        # 5000
SECONDARY_SWAP_IN="100000000000000000000"       # 100

send_tx "approve_vault_deposit" "$UNDERLYING_ASSET_VAL" "approve(address,uint256)" "$VAULT_ADDRESS" "$MAX_UINT"
send_tx "deposit_into_vault" "$VAULT_ADDRESS" "deposit(uint256,address)" "$DEPOSIT_AMOUNT" "$OWNER"

SHARES_MINTED="$(call_value "$YTOKEN_ADDRESS" "balanceOf(address)" "$OWNER")"
SHARE_PRICE_BEFORE="$(call_value "$VAULT_ADDRESS" "sharePrice()")"

send_tx "approve_fee_yield" "$UNDERLYING_ASSET_VAL" "approve(address,uint256)" "$VAULT_ADDRESS" "$MAX_UINT"
send_tx "report_amm_fee_yield" "$VAULT_ADDRESS" "reportAmmFeeYield(uint256)" "$FEE_YIELD_AMOUNT"
send_tx "fund_rebate_reserve" "$VAULT_ADDRESS" "fundRebateReserve(uint256)" "$RESERVE_AMOUNT"

# Simulate hook callback on testnet demo path to demonstrate deterministic yield path
send_tx "set_hook_to_owner_for_demo" "$VAULT_ADDRESS" "setHook(address)" "$OWNER"
send_tx "notify_swap_volume_demo" "$VAULT_ADDRESS" "notifySwapVolume(bytes32,uint256,address)" "0x0000000000000000000000000000000000000000000000000000000000000001" "$NOTIONAL_AMOUNT" "$OWNER"
send_tx "apply_deterministic_yield" "$VAULT_ADDRESS" "applyDeterministicYield(uint256)" "0"

SHARE_PRICE_AFTER="$(call_value "$VAULT_ADDRESS" "sharePrice()")"

send_tx "approve_secondary_ytoken" "$YTOKEN_ADDRESS" "approve(address,uint256)" "$SECONDARY_ADDRESS" "$MAX_UINT"
send_tx "approve_secondary_underlying" "$UNDERLYING_ASSET_VAL" "approve(address,uint256)" "$SECONDARY_ADDRESS" "$MAX_UINT"
send_tx "add_secondary_liquidity" "$SECONDARY_ADDRESS" "addLiquidity(uint256,uint256)" "500000000000000000000" "500000000000000000000"
send_tx "secondary_swap_trade" "$SECONDARY_ADDRESS" "swapExactIn(address,uint256,uint256)" "$YTOKEN_ADDRESS" "$SECONDARY_SWAP_IN" "1"

send_tx "approve_lending_ytoken" "$YTOKEN_ADDRESS" "approve(address,uint256)" "$LENDING_ADDRESS" "$MAX_UINT"
send_tx "lending_deposit_collateral" "$LENDING_ADDRESS" "depositCollateral(uint256)" "$SECONDARY_SWAP_IN"
MAX_BORROW_RAW="$(call_value "$LENDING_ADDRESS" "maxBorrow(address)" "$OWNER")"
BORROW_AMOUNT="$(python3 - <<PY
max_borrow=int("$(cast to-dec "$MAX_BORROW_RAW")")
# Keep a buffer below max to avoid edge-case rounding reverts.
print(max(1, (max_borrow * 90) // 100))
PY
)"
send_tx "lending_borrow" "$LENDING_ADDRESS" "borrow(uint256)" "$BORROW_AMOUNT"

DEBT_TOKEN_ADDRESS="$(call_value "$LENDING_ADDRESS" "debtToken()(address)")"
send_tx "approve_lending_repay" "$DEBT_TOKEN_ADDRESS" "approve(address,uint256)" "$LENDING_ADDRESS" "$MAX_UINT"
send_tx "lending_repay" "$LENDING_ADDRESS" "repay(uint256)" "$BORROW_AMOUNT"
send_tx "lending_withdraw_collateral" "$LENDING_ADDRESS" "withdrawCollateral(uint256)" "$SECONDARY_SWAP_IN"

REDEEM_SHARES="$(call_value "$YTOKEN_ADDRESS" "balanceOf(address)" "$OWNER")"
ASSET_BAL_BEFORE="$(call_value "$UNDERLYING_ASSET_VAL" "balanceOf(address)" "$OWNER")"
send_tx "redeem_from_vault" "$VAULT_ADDRESS" "redeem(uint256,address)" "$REDEEM_SHARES" "$OWNER"
ASSET_BAL_AFTER="$(call_value "$UNDERLYING_ASSET_VAL" "balanceOf(address)" "$OWNER")"

REDEEM_AMOUNT="$(python3 - <<PY
before=int("$(cast to-dec "$ASSET_BAL_BEFORE")")
after=int("$(cast to-dec "$ASSET_BAL_AFTER")")
print(after-before)
PY
)"

echo "== Judge summary =="
echo "deposit amount: ${DEPOSIT_AMOUNT}"
echo "shares minted: ${SHARES_MINTED}"
echo "share price before: ${SHARE_PRICE_BEFORE}"
echo "share price after: ${SHARE_PRICE_AFTER}"
echo "redeem amount: ${REDEEM_AMOUNT}"
echo "secondary pool trade executed: yes"
echo "borrow/repay summary: borrowed ${BORROW_AMOUNT}, repaid ${BORROW_AMOUNT}"
echo "updated .env with deployed addresses"
