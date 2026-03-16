# Demo

## Run
```bash
make demo-testnet
```

The script:
- reuses deployed contracts from `.env` when present
- deploys missing pieces only
- prints every tx hash + explorer URL
- prints a judge summary at the end

## End-to-end flow (what gets proven)
1. **Preflight**
Validates RPC, owner, pool-manager settings and selects fallback RPC if primary is unreachable.

2. **Ensure Underlying**
Reuses `UNDERLYING_ASSET` if already set; otherwise deploys `DemoERC20` and records address.

3. **Ensure Strategy System**
Reuses `STRATEGY_VAULT`, `YIELD_TOKEN`, `STRATEGY_HOOK`, `STRATEGY_REGISTRY`, `LENDING_ADAPTER`, `SECONDARY_MARKET` from `.env`; if missing, deploys and stores them.

4. **User Deposit / Mint**
User approves underlying and deposits to `StrategyVault`; yToken shares are minted.

5. **Yield Accrual**
AMM fee yield is reported to vault and deterministic strategy yield is applied via notional swap-volume callback path.

6. **Secondary Market Composability**
User adds yToken/underlying liquidity in `SecondaryMarketMock`, then executes a yToken trade.

7. **Lending Composability**
User deposits yToken collateral to `LendingAdapterMock`, borrows within `maxBorrow`, repays, and withdraws collateral.

8. **Redeem**
User redeems shares from vault and receives underlying.

9. **Judge Summary**
Script prints:
- deposit amount
- shares minted (this run)
- share price before/after + delta (bps)
- redeem amount
- secondary trade confirmation
- lending borrow/repay details
