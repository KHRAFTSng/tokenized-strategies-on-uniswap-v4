# Contributing

## Setup
```bash
bash scripts/bootstrap.sh
npm install
forge test
```

## Standards
- Solidity: strict pragmas, custom errors, no relative imports.
- Tests: unit + edge + fuzz + integration for all state-changing paths.
- Docs: update `README.md`, `spec.md`, and relevant files under `docs/`.

## Commit Style
Use conventional prefixes:
- `feat:`
- `fix:`
- `test:`
- `docs:`
- `chore:`

## Validation
```bash
forge build
forge test
forge coverage
npm --workspace frontend run build
bash scripts/verify_deps.sh
bash scripts/verify_commits.sh 78
```
