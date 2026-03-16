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
FALLBACK_RPC_URL="${FALLBACK_RPC_URL:-https://sepolia.unichain.org}"

if [[ -z "${RPC_URL}" || -z "${PRIVATE_KEY_VAL}" || -z "${OWNER}" || -z "${POOL_MANAGER_VAL}" ]]; then
  echo "missing required env vars: RPC, private key, owner, pool manager" >&2
  exit 1
fi

if ! cast block-number --rpc-url "$RPC_URL" >/tmp/demo_rpc_check.log 2>&1; then
  echo "primary_rpc_unreachable: ${RPC_URL}"
  cat /tmp/demo_rpc_check.log || true
  if cast block-number --rpc-url "$FALLBACK_RPC_URL" >/tmp/demo_rpc_fallback_check.log 2>&1; then
    RPC_URL="$FALLBACK_RPC_URL"
    echo "using_fallback_rpc: ${RPC_URL}"
  else
    echo "fallback_rpc_unreachable: ${FALLBACK_RPC_URL}" >&2
    cat /tmp/demo_rpc_fallback_check.log >&2 || true
    exit 1
  fi
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
  local output
  local attempt=1
  local max_attempts=4

  while (( attempt <= max_attempts )); do
    if output="$(cast send "$@" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY_VAL" --json 2>/tmp/demo_cast_send_err.log)"; then
      tx_hash="$(echo "$output" | jq -r '.transactionHash')"
      print_tx "$label" "$tx_hash"
      return 0
    fi
    echo "retry_send_${label}: attempt ${attempt}/${max_attempts}"
    cat /tmp/demo_cast_send_err.log || true
    sleep $(( attempt * 2 ))
    attempt=$(( attempt + 1 ))
  done

  echo "failed tx: ${label}" >&2
  cat /tmp/demo_cast_send_err.log >&2 || true
  exit 1
}

call_value() {
  local output
  local attempt=1
  local max_attempts=4

  while (( attempt <= max_attempts )); do
    if output="$(cast call "$@" --rpc-url "$RPC_URL" 2>/tmp/demo_cast_call_err.log)"; then
      echo "$output" | awk '{print $1}'
      return 0
    fi
    echo "retry_call: attempt ${attempt}/${max_attempts}" >&2
    cat /tmp/demo_cast_call_err.log >&2 || true
    sleep $(( attempt * 2 ))
    attempt=$(( attempt + 1 ))
  done

  echo "failed call: $*" >&2
  cat /tmp/demo_cast_call_err.log >&2 || true
  exit 1
}

is_set_addr() {
  local addr="$1"
  if [[ -z "$addr" || "$addr" == "null" || "$addr" == "0x0000000000000000000000000000000000000000" ]]; then
    return 1
  fi
  return 0
}

echo "== Phase 0: Preflight =="
echo "chain_id: ${CHAIN_ID_VAL}"
echo "owner: ${OWNER}"
echo "pool_manager: ${POOL_MANAGER_VAL}"
echo "explorer_base: ${EXPLORER_TX_BASE}"

UNDERLYING_ASSET_VAL="${UNDERLYING_ASSET:-}"
VAULT_ADDRESS="${STRATEGY_VAULT:-}"
YTOKEN_ADDRESS="${YIELD_TOKEN:-}"
HOOK_ADDRESS="${STRATEGY_HOOK:-}"
REGISTRY_ADDRESS="${STRATEGY_REGISTRY:-}"
LENDING_ADDRESS="${LENDING_ADAPTER:-}"
SECONDARY_ADDRESS="${SECONDARY_MARKET:-}"

echo "== Phase 1: Ensure underlying token =="
if is_set_addr "$UNDERLYING_ASSET_VAL"; then
  echo "reuse_underlying: ${UNDERLYING_ASSET_VAL}"
  echo "deploy_demo_underlying: skipped (existing deployment detected)"
else
  echo "deploy_demo_underlying: required"
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
fi

echo "== Phase 2: Ensure strategy system =="
if is_set_addr "$VAULT_ADDRESS" \
  && is_set_addr "$YTOKEN_ADDRESS" \
  && is_set_addr "$HOOK_ADDRESS" \
  && is_set_addr "$REGISTRY_ADDRESS" \
  && is_set_addr "$LENDING_ADDRESS" \
  && is_set_addr "$SECONDARY_ADDRESS"; then
  echo "strategy_deploy: skipped (existing deployments detected in .env)"
  echo "deploy_tx: skipped"
else
  echo "strategy_deploy: required"
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

  echo "== Deployment tx hashes =="
  jq -r '.transactions[]?.hash' "$DEPLOY_RUN_FILE" | while read -r h; do
    [[ -n "$h" && "$h" != "null" ]] && print_tx "deploy_tx" "$h"
  done
fi

# yToken can always be derived from vault; keep this consistent even in reuse mode.
YTOKEN_FROM_VAULT="$(call_value "$VAULT_ADDRESS" "yieldToken()(address)")"
if is_set_addr "$YTOKEN_FROM_VAULT"; then
  YTOKEN_ADDRESS="$YTOKEN_FROM_VAULT"
fi

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

echo "== Phase 3: User-perspective demo flow =="
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"
DEPOSIT_AMOUNT="1000000000000000000000"        # 1000
FEE_YIELD_AMOUNT="50000000000000000000"         # 50
RESERVE_AMOUNT="100000000000000000000"          # 100
NOTIONAL_AMOUNT="5000000000000000000000"        # 5000
SHARES_BEFORE="$(call_value "$YTOKEN_ADDRESS" "balanceOf(address)" "$OWNER")"
SHARE_PRICE_BEFORE="$(call_value "$VAULT_ADDRESS" "sharePrice()")"

send_tx "approve_vault_deposit" "$UNDERLYING_ASSET_VAL" "approve(address,uint256)" "$VAULT_ADDRESS" "$MAX_UINT"
send_tx "deposit_into_vault" "$VAULT_ADDRESS" "deposit(uint256,address)" "$DEPOSIT_AMOUNT" "$OWNER"

SHARES_AFTER_DEPOSIT="$(call_value "$YTOKEN_ADDRESS" "balanceOf(address)" "$OWNER")"
SHARES_MINTED_DEC="$(python3 - <<PY
before=int("$(cast to-dec "$SHARES_BEFORE")")
after=int("$(cast to-dec "$SHARES_AFTER_DEPOSIT")")
print(max(0, after-before))
PY
)"

SECONDARY_LIQUIDITY_AMOUNT="$(python3 - <<PY
minted=int("${SHARES_MINTED_DEC}")
print(max(1, minted // 4))
PY
)"

SECONDARY_SWAP_IN="$(python3 - <<PY
liq=int("${SECONDARY_LIQUIDITY_AMOUNT}")
print(max(1, liq // 5))
PY
)"

LENDING_COLLATERAL_AMOUNT="$(python3 - <<PY
swap_in=int("${SECONDARY_SWAP_IN}")
print(max(1, swap_in // 2))
PY
)"

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
send_tx "add_secondary_liquidity" "$SECONDARY_ADDRESS" "addLiquidity(uint256,uint256)" "$SECONDARY_LIQUIDITY_AMOUNT" "$SECONDARY_LIQUIDITY_AMOUNT"
send_tx "secondary_swap_trade" "$SECONDARY_ADDRESS" "swapExactIn(address,uint256,uint256)" "$YTOKEN_ADDRESS" "$SECONDARY_SWAP_IN" "1"

send_tx "approve_lending_ytoken" "$YTOKEN_ADDRESS" "approve(address,uint256)" "$LENDING_ADDRESS" "$MAX_UINT"
send_tx "lending_deposit_collateral" "$LENDING_ADDRESS" "depositCollateral(uint256)" "$LENDING_COLLATERAL_AMOUNT"
MAX_BORROW_RAW="$(call_value "$LENDING_ADDRESS" "maxBorrow(address)" "$OWNER")"
MAX_BORROW_DEC="$(cast to-dec "$MAX_BORROW_RAW")"
BORROW_AMOUNT="$(python3 - <<PY
max_borrow=int("$(cast to-dec "$MAX_BORROW_RAW")")
# Keep a buffer below max to avoid edge-case rounding reverts.
print((max_borrow * 90) // 100)
PY
)"
if [[ "$BORROW_AMOUNT" != "0" ]]; then
  send_tx "lending_borrow" "$LENDING_ADDRESS" "borrow(uint256)" "$BORROW_AMOUNT"

  DEBT_TOKEN_ADDRESS="$(call_value "$LENDING_ADDRESS" "debtToken()(address)")"
  send_tx "approve_lending_repay" "$DEBT_TOKEN_ADDRESS" "approve(address,uint256)" "$LENDING_ADDRESS" "$MAX_UINT"
  send_tx "lending_repay" "$LENDING_ADDRESS" "repay(uint256)" "$BORROW_AMOUNT"
else
  echo "lending_borrow: skipped (maxBorrow=${MAX_BORROW_DEC})"
fi
send_tx "lending_withdraw_collateral" "$LENDING_ADDRESS" "withdrawCollateral(uint256)" "$LENDING_COLLATERAL_AMOUNT"

OWNER_SHARES_AFTER_FLOW="$(call_value "$YTOKEN_ADDRESS" "balanceOf(address)" "$OWNER")"
REDEEM_SHARES="$(python3 - <<PY
minted=int("${SHARES_MINTED_DEC}")
owner_bal=int("$(cast to-dec "$OWNER_SHARES_AFTER_FLOW")")
target=max(1, minted // 2) if minted > 0 else 1
print(min(owner_bal, target))
PY
)"
ASSET_BAL_BEFORE="$(call_value "$UNDERLYING_ASSET_VAL" "balanceOf(address)" "$OWNER")"
send_tx "redeem_from_vault" "$VAULT_ADDRESS" "redeem(uint256,address)" "$REDEEM_SHARES" "$OWNER"
ASSET_BAL_AFTER="$(call_value "$UNDERLYING_ASSET_VAL" "balanceOf(address)" "$OWNER")"

REDEEM_AMOUNT="$(python3 - <<PY
before=int("$(cast to-dec "$ASSET_BAL_BEFORE")")
after=int("$(cast to-dec "$ASSET_BAL_AFTER")")
print(after-before)
PY
)"

SHARE_PRICE_BEFORE_DEC="$(cast to-dec "$SHARE_PRICE_BEFORE")"
SHARE_PRICE_AFTER_DEC="$(cast to-dec "$SHARE_PRICE_AFTER")"
SHARE_PRICE_DELTA_BPS="$(python3 - <<PY
before=int("${SHARE_PRICE_BEFORE_DEC}")
after=int("${SHARE_PRICE_AFTER_DEC}")
if before == 0:
  print(0)
else:
  print(((after - before) * 10000) // before)
PY
)"

echo "== Judge summary =="
echo "deposit amount: ${DEPOSIT_AMOUNT}"
echo "shares minted (this run): ${SHARES_MINTED_DEC}"
echo "share price before: ${SHARE_PRICE_BEFORE_DEC} (raw ${SHARE_PRICE_BEFORE})"
echo "share price after: ${SHARE_PRICE_AFTER_DEC} (raw ${SHARE_PRICE_AFTER})"
echo "share price delta (bps): ${SHARE_PRICE_DELTA_BPS}"
echo "redeem amount: ${REDEEM_AMOUNT}"
echo "secondary pool trade executed: yes"
echo "secondary liquidity amount: ${SECONDARY_LIQUIDITY_AMOUNT}"
echo "secondary swap input: ${SECONDARY_SWAP_IN}"
echo "lending collateral amount: ${LENDING_COLLATERAL_AMOUNT}"
echo "max borrow: ${MAX_BORROW_DEC}"
echo "borrow/repay summary: borrowed ${BORROW_AMOUNT}, repaid ${BORROW_AMOUNT}"
echo "updated .env with deployed addresses"
