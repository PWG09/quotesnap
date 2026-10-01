"use client";

import { useState } from "react";

type CalculatorClientProps = { type: string };

export default function CalculatorClient({ type }: CalculatorClientProps) {
  const [sqft, setSqft] = useState("2000");
  const [rate, setRate] = useState("2.5");
  const total = (Number(sqft) || 0) * (Number(rate) || 0);
  const title = type.replaceAll("-", " ");

  return (
    <main className="container section">
      <h1>{title} estimate calculator</h1>
      <p className="muted">Enter details to get a starting estimate.</p>
      <div className="card" style={{ maxWidth: 600, marginTop: 25 }}>
        <label htmlFor="sqft">Square footage</label>
        <input
          id="sqft"
          className="input"
          inputMode="decimal"
          value={sqft}
          onChange={(event) => setSqft(event.target.value)}
        />
        <label htmlFor="rate" style={{ display: "block", marginTop: 16 }}>
          Price per sq ft
        </label>
        <input
          id="rate"
          className="input"
          inputMode="decimal"
          value={rate}
          onChange={(event) => setRate(event.target.value)}
        />
        <div style={{ marginTop: 25 }}>
          <span className="muted">Estimated total</span>
          <div className="price">{"$" + total.toLocaleString()}</div>
        </div>
      </div>
    </main>
  );
}
