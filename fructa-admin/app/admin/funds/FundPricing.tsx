"use client";

import { useState } from "react";
import { updatePricing, setPrice } from "./actions";

// Field-scoped Pricing card. Owns `basis` and the fact-sheet fields a priced
// fund carries; the yield rate stays with the Rate box / setRate. Choosing NAV
// reveals them; Yield/None hides them and a save clears them server-side, so a
// fund flipped off NAV cannot keep a stale unit price. Mirrors the
// updateContact / updateCustody field-scoping pattern.
//
// TWO FORMS, ON PURPOSE.
//
// "Save pricing" writes metadata: the basis, the distribution, the duration, the
// credit split. It does not set a price.
//
// "Add NAV mark" is the only thing that sets a price, and it appends to
// nav_history at the same time. That separation is the whole point: a price on
// the row with no dated mark behind it is a point that never joins the series,
// and a fund whose chart disagrees with its own headline is worse than a fund
// with no chart. It is the exact relationship setRate has with rate_history.
const BASES: [string, string][] = [
  ["yield", "Yield (quotes an annual rate)"],
  ["nav", "NAV (quotes a unit price)"],
  ["none", "None (no headline figure)"],
];

// The credit ladder, best standing first. Stored as jsonb, shaped like
// funds.composition. Everything that is not `gov` is where the extra income
// comes from, and it is also the part that can default.
const CREDIT: [string, string][] = [
  ["gov", "Government"],
  ["aa", "Corporate AA"],
  ["a", "Corporate A"],
  ["bbb", "Corporate BBB"],
  ["unrated", "Unrated"],
];

export type NavMark = { as_of: string; price: number; source: string | null };

type Props = {
  id: string;
  currency: string;
  basis: string | null;
  pricePerUnit: number | null;
  priceAsOf: string | null;
  distributionPct: number | null;
  durationYears: number | null;
  creditQuality: Record<string, number> | null;
  navHistory: NavMark[];
};

export function FundPricing({
  id,
  currency,
  basis,
  pricePerUnit,
  priceAsOf,
  distributionPct,
  durationYears,
  creditQuality,
  navHistory,
}: Props) {
  const [b, setB] = useState((basis ?? "yield") as string);
  const isNav = b === "nav";

  const credTotal = CREDIT.reduce((s, [k]) => s + (creditQuality?.[k] ?? 0), 0);

  return (
    <>
      <form action={updatePricing} className="panelc">
        <input type="hidden" name="id" value={id} />
        <div className="ph">
          <h3>Pricing</h3>
          <span className="sub">basis · publishes to snapshot</span>
        </div>

        <div className="pb" style={{ display: "grid", gap: 14 }}>
          <label className="field">
            <span>Basis</span>
            <select name="basis" value={b} onChange={(e) => setB(e.target.value)} className="select">
              {BASES.map(([k, l]) => (
                <option key={k} value={k}>{l}</option>
              ))}
            </select>
          </label>

          {isNav ? (
            <>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
                <label className="field">
                  <span>Distribution %</span>
                  <input name="distribution_pct" type="number" step="any" defaultValue={distributionPct ?? ""}
                    className="input num-input" placeholder="4.10" />
                </label>
                <label className="field">
                  <span>Duration (years)</span>
                  <input name="duration_years" type="number" step="any" min="0" defaultValue={durationYears ?? ""}
                    className="input num-input" placeholder="3.2" />
                </label>
              </div>

              <p style={{ fontSize: 11.5, color: "var(--faint)", margin: 0, lineHeight: 1.55 }}>
                Duration is the rate sensitivity of a bond fund. Rates up 1 point, unit price down about this many
                percent. It is why a fund paying 5.1% income can post a <span style={{ color: "var(--bad)" }}>negative</span>{" "}
                total return while one paying 4.4% posts +12.6%. Leave blank for equity and balanced funds; blank renders
                as unknown, never as zero.
              </p>

              <div style={{ borderTop: "1px solid var(--line)", paddingTop: 12 }}>
                <span style={{ fontFamily: "var(--mono)", fontSize: 10.5, letterSpacing: "1.4px", textTransform: "uppercase", color: "var(--faint)" }}>
                  Credit quality
                </span>
                <p style={{ fontSize: 11.5, color: "var(--faint)", margin: "4px 0 10px", lineHeight: 1.55 }}>
                  Percentages, roughly summing to 100. A government cannot run out of shillings; a company can.
                  {credTotal > 0 && (
                    <span className="num" style={{ color: credTotal > 101 || credTotal < 99 ? "var(--warn)" : "var(--live)", marginLeft: 6 }}>
                      currently {credTotal.toFixed(0)}%
                    </span>
                  )}
                </p>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 }}>
                  {CREDIT.map(([k, label]) => (
                    <label key={k} className="field">
                      <span style={{ fontSize: 9.5 }}>{label}</span>
                      <input name={`credit_${k}`} type="number" step="any" min="0" max="100"
                        defaultValue={creditQuality?.[k] ?? ""} className="input num-input" placeholder="0" />
                    </label>
                  ))}
                </div>
              </div>

              <p style={{ fontSize: 12, color: "var(--faint)", margin: 0 }}>
                This fund quotes a unit price, not a yield. Leave the Rate box above empty. The price itself is set
                below, as a dated mark.
              </p>
            </>
          ) : (
            <p style={{ fontSize: 12, color: "var(--faint)", margin: 0 }}>
              Yield funds set their rate in the Rate box above. Switch to NAV for bond / equity / priced special funds
              that quote a unit price.
            </p>
          )}
        </div>

        <div className="pb" style={{ paddingTop: 0 }}>
          <button className="btn gold">Save pricing</button>
        </div>
      </form>

      {isNav && (
        <div className="panelc">
          <div className="ph">
            <h3>NAV marks</h3>
            <span className="sub">{currency} per unit · builds the chart</span>
          </div>

          <div className="pb">
            <p className="num" style={{ fontSize: 30, fontWeight: 600, color: "var(--gold)", margin: "0 0 2px", letterSpacing: "-1px" }}>
              {pricePerUnit != null ? `${currency} ${Number(pricePerUnit).toFixed(2)}` : "—"}
            </p>
            <p style={{ fontSize: 11.5, color: "var(--faint)", margin: "0 0 12px" }}>
              {priceAsOf ? `as of ${priceAsOf}` : "no price published yet"}
            </p>

            <form action={setPrice} style={{ display: "flex", alignItems: "flex-end", gap: 8 }}>
              <input type="hidden" name="id" value={id} />
              <label className="field" style={{ flex: 1 }}>
                <span>Price ({currency})</span>
                <input name="price" type="number" step="any" min="0" placeholder="10.42"
                  className="input num-input" required />
              </label>
              <label className="field" style={{ flex: 1 }}>
                <span>Fact-sheet date</span>
                <input name="as_of" type="date" className="input" required />
              </label>
              <button className="btn xs" style={{ marginBottom: 2 }}>Add</button>
            </form>

            <p style={{ marginTop: 8, fontSize: 11.5, color: "var(--faint)", lineHeight: 1.55 }}>
              The date is the fact sheet&rsquo;s, not today&rsquo;s. A June NAV keyed in during July is a June mark, and
              stamping it &ldquo;today&rdquo; would bend the series. Two marks are enough to draw a line.
            </p>
          </div>

          {navHistory.length === 0 ? (
            <div className="pb" style={{ paddingTop: 0, color: "var(--muted)", fontSize: 13.5 }}>
              No marks yet. The chart, the sparkline and the growth backtest all need at least two.
            </div>
          ) : (
            <table className="tbl">
              <tbody>
                {navHistory.map((h) => (
                  <tr key={h.as_of}>
                    <td style={{ color: "var(--faint)" }}>{h.as_of}</td>
                    <td className="r num">{Number(h.price).toFixed(2)}</td>
                    <td className="r" style={{ fontSize: 11, color: "var(--faint)" }}>
                      <span className={"method " + (h.source === "manual" ? "manual" : "auto")}>{h.source ?? "—"}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </>
  );
}
