# API
## StrategyVault
- `deposit(uint256 assets, address receiver)`
- `redeem(uint256 shares, address receiver)`
- `reportAmmFeeYield(uint256 assetsAdded)`
- `fundRebateReserve(uint256 assetsAdded)`
- `applyDeterministicYield(uint256 maxAmount)`
- `notifySwapVolume(bytes32 poolId, uint256 notionalAmount, address sender)`

## StrategyHook
- `setPoolPolicy(...)`
- `setSenderAllowlist(...)`
- `setVault(...)`

## StrategyRegistry
- `registerStrategy(...)`
- `updateStrategy(...)`
