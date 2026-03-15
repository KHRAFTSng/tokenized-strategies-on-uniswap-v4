# Security
## Attack Surfaces
- share inflation/donation attacks
- sandwich around mint/redeem
- pool price manipulation affecting strategy behavior
- insolvency from locked liquidity
- admin misconfiguration

## Mitigations
- managed-assets accounting (ignores unsolicited donations)
- deterministic policy checks in hook
- non-reentrant mint/redeem
- explicit locked liquidity cap on redemption
- strict owner-only configuration controls
