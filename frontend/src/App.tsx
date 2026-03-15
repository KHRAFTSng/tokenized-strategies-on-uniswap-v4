import { useMemo, useState } from "react";

export function App() {
  const [deposit, setDeposit] = useState("1000");
  const [shares, setShares] = useState(1000);
  const [sharePrice, setSharePrice] = useState(1);
  const [logs, setLogs] = useState<string[]>([]);

  const nav = useMemo(() => (shares * sharePrice).toFixed(4), [shares, sharePrice]);

  const addLog = (message: string) => setLogs((prev) => [message, ...prev].slice(0, 8));

  const onDeposit = () => {
    const amount = Number(deposit);
    if (!Number.isFinite(amount) || amount <= 0) return;
    setShares((s) => s + amount / sharePrice);
    addLog(`deposit: ${amount.toFixed(2)} underlying -> minted ${(amount / sharePrice).toFixed(2)} yTOKEN`);
  };

  const onRedeem = () => {
    const redeemShares = Math.min(shares, Number(deposit));
    if (redeemShares <= 0) return;
    setShares((s) => s - redeemShares);
    addLog(`redeem: ${redeemShares.toFixed(2)} shares -> ${(redeemShares * sharePrice).toFixed(2)} underlying`);
  };

  const runSwapYield = () => {
    setSharePrice((p) => Number((p * 1.0125).toFixed(6)));
    addLog("swap activity simulated: AMM fee yield + deterministic strategy yield applied");
  };

  const runSecondaryTrade = () => {
    addLog("secondary pool trade executed: yTOKEN/underlying swap complete");
  };

  const runLendingDemo = () => {
    addLog("lending demo: yTOKEN collateral deposited, borrow + repay complete");
  };

  return (
    <main className="page">
      <section className="hero card">
        <p className="eyebrow">Strategy Studio</p>
        <h1>Tokenized Uniswap v4 Yield</h1>
        <p className="sub">Create, mint, redeem, and demo composability for liquidity-backed yield tokens.</p>
      </section>

      <section className="grid">
        <article className="card">
          <h2>Vault Actions</h2>
          <label>Amount</label>
          <input value={deposit} onChange={(e) => setDeposit(e.target.value)} />
          <div className="row">
            <button onClick={onDeposit}>Deposit / Mint</button>
            <button className="ghost" onClick={onRedeem}>Redeem / Burn</button>
          </div>
          <div className="metrics">
            <p>Share Price: <strong>{sharePrice.toFixed(6)}</strong></p>
            <p>Total Shares: <strong>{shares.toFixed(4)}</strong></p>
            <p>NAV: <strong>{nav}</strong></p>
          </div>
        </article>

        <article className="card">
          <h2>Demo Controls</h2>
          <button onClick={runSwapYield}>Run Swap Yield Demo</button>
          <button onClick={runSecondaryTrade}>Run Secondary Trade</button>
          <button onClick={runLendingDemo}>Run Lending Demo</button>
          <p className="small">Connect this UI to contracts in `shared/abis/` for live chain actions.</p>
        </article>
      </section>

      <section className="card">
        <h2>Execution Log</h2>
        <ul>
          {logs.map((item, i) => <li key={`${item}-${i}`}>{item}</li>)}
        </ul>
      </section>
    </main>
  );
}
