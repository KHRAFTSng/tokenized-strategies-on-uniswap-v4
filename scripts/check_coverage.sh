#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LCOV_OUT="/tmp/strategy_coverage.lcov"
# Work around a Foundry macOS panic in online signature lookup by running coverage offline.
FOUNDRY_OFFLINE=true forge coverage --report lcov --exclude-tests --no-match-coverage "(script/|test/|src/interfaces/)" -r "$LCOV_OUT" >/tmp/strategy_coverage.log 2>&1

python3 - <<'PY'
import sys
from pathlib import Path
lcov = Path('/tmp/strategy_coverage.lcov')
if not lcov.exists():
    print('coverage lcov file missing', file=sys.stderr)
    sys.exit(1)

current = None
metrics = {}
for line in lcov.read_text().splitlines():
    if line.startswith('SF:'):
        current = line[3:]
        metrics[current] = {'LF':0,'LH':0,'BRF':0,'BRH':0,'FNF':0,'FNH':0}
    elif current is not None and ':' in line:
        k,v = line.split(':',1)
        if k in metrics[current]:
            metrics[current][k] = int(v)

failures = []
for sf,m in metrics.items():
    if '/src/' not in sf:
        continue
    if '/src/interfaces/' in sf:
        continue
    if not (m['LF']==m['LH'] and m['BRF']==m['BRH'] and m['FNF']==m['FNH']):
        failures.append((sf,m))

if failures:
    print('Coverage below 100% for:')
    for sf,m in failures:
        print(f"- {sf}: lines {m['LH']}/{m['LF']} branches {m['BRH']}/{m['BRF']} funcs {m['FNH']}/{m['FNF']}")
    sys.exit(1)

print('coverage check passed: 100% for src contracts')
PY
