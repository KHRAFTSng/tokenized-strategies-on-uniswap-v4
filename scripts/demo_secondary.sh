#!/usr/bin/env bash
set -euo pipefail
forge test --match-test test_SecondaryMarketPoolTrade -vvv
echo "secondary pool trade executed"
