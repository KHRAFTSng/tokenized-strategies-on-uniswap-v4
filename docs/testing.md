# Testing
```bash
forge test
forge test --match-test test_EndToEndYieldLifecycle -vvv
forge coverage
bash scripts/check_coverage.sh
```

Coverage includes:
- unit tests
- edge-case tests
- fuzz tests
- integration tests against v4 test harness
