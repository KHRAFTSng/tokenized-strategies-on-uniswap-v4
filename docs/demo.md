# Demo
Run:
```bash
make demo-local
make demo-yield
make demo-secondary
make demo-all
```

Judge flow:
1. Deploy core contracts.
2. Deposit -> mint yToken.
3. Run swaps -> accrue deterministic yield.
4. Apply yield -> share price increases.
5. Redeem shares.
6. Execute secondary market trade.
7. (Optional) collateralize yToken in lending adapter.
