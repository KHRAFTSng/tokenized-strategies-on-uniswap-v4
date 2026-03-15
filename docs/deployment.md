# Deployment
## Environment
Create `.env` from `.env.example`.

## Local
```bash
anvil
forge script script/10_DeployStrategySystem.s.sol:DeployStrategySystemScript --rpc-url http://127.0.0.1:8545 --broadcast
```

## Testnet (Base Sepolia preferred)
```bash
forge script script/10_DeployStrategySystem.s.sol:DeployStrategySystemScript --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
```

Explorer links: use `https://sepolia.basescan.org/tx/<hash>` where applicable.
