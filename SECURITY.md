# Security Policy

## Scope
This repository contains demo-ready, security-oriented protocol code for tokenized Uniswap v4 strategies.

## Supported Branch
- `main`

## Reporting
Send reports to: `jesuorobonosakhare873@gmail.com`

Include:
- impact
- PoC
- affected contracts/files
- remediation suggestion

## Hardening Checklist
- [x] Hook `onlyPoolManager` gate
- [x] Non-reentrant vault state transitions
- [x] Managed-asset accounting (donation mitigation)
- [x] Liquidity withdrawal bounds
- [x] Edge + fuzz + integration tests

## Disclaimer
This code is not guaranteed attack-proof. Independent audits are required before production deployment.
