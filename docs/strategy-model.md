# Strategy Model
## Yield Formula
- Source A (AMM fee yield): `totalManagedAssets += feeInflow`
- Source B (strategy yield): `pending += notional * rebateBps / 10000`, then applied from funded reserve.

## Share Price
`sharePrice = totalManagedAssets / totalSupply`

## Rounding
Conversion functions use mulDiv with explicit rounding direction in `AccountingLibrary`.
