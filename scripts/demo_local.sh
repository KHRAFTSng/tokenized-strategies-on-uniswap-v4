#!/usr/bin/env bash
set -euo pipefail

forge test --match-test test_EndToEndYieldLifecycle -vvv
forge test --match-test test_SecondaryMarketPoolTrade -vvv
forge test --match-test test_OptionalLendingAdapterFlow -vvv

echo "deployed_addresses: ephemeral_test_environment"
echo "tx_hashes: TBD (forge test execution)"
echo "explorer_urls: TBD"
