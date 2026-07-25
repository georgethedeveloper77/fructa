"use client";

import { useState } from "react";
import { updatePricing, setPrice, setPeriodReturn, deletePeriodReturn } from "./actions";

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
  ["return", "Return (realized, for a closed period)"],
  ["none", "None (no headline figure)"],
];

// What is ALREADY deducted from the quoted number, which is what decides whether
// the app deducts withholding tax on top. Offered on every basis, because an MMF
// quoting net of fees and gross of tax is making the same kind of statement and
// the app has been assuming it rather than reading it.
const NET_OF: [string, string][] = [
  ["fees", "Net of fees, gross of withholding tax (the usual case)"],
  ["fees_and_tax", "Net of fees AND tax (app must not deduct again)"],
  ["nothing", "Raw gross, before fees and before tax"],
];

const RETURN_PERIODS: [string, string][] = [
  ["quarter", "Quarter"],
  ["month", "Month"],
  ["half", "Half year"],
  ["year", "Year"],
  ["ytd", "Year to date"],
  ["since_inception", "Since inception"],
];

// mgmt_fee holds a number; this holds what to call it. A 5% p.a. financial
// services charge is not a management fee, and labelling it as one while the
// performance charge stayed invisible understated the cost of the fund twice.
const FEE_KINDS: [string, string][] = [
  ["mgmt", "Management fee"],
  ["service", "Financial services charge"],
  ["none", "No recurring charge published"],
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

// Labels for a stored return_history row. Kept beside the table that renders
// them rather than shared with RETURN_PERIODS above: that list is what a fund
// may be SET to, this is what a row already IS, and the two drifting apart is
// less costly than a shared constant that has to serve both.
const PERIOD_LABEL: Record<string, string> = {
  month: "Month",
  quarter: "Quarter",
  half: "Half",
  year: "Year",
  ytd: "YTD",
  since_inception: "Since inception",
};

// A row's own net-ness, abbreviated for a narrow column. Shown per row because
// it varies per row: a manager can publish quarters net of fees and an annual
// figure net of fees and tax on the same page.
const NET_OF_SHORT: Record<string, string> = {
  nothing: "gross",
  fees: "net fees",
  fees_and_tax: "net fees+tax",
};

export type NavMark = { as_of: string; price: number; source: string | null };

export type PeriodReturn = {
  period_end: string;
  period: string;
  net_pct: number;
  gross_pct: number | null;
  net_of: string;
};

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
  netOf: string | null;
  returnPeriod: string | null;
  returnAsOf: string | null;
  feeKind: string | null;
  perfFeePct: number | null;
  hurdlePct: number | null;
  classGroup: string | null;
  classLabel: string | null;
  returnHistory: PeriodReturn[];
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
  netOf,
  returnPeriod,
  returnAsOf,
  feeKind,
  perfFeePct,
  hurdlePct,
  classGroup,
  classLabel,
  returnHistory,
}: Props) {
  // No `?? "yield"` here. That default is what let a return-basis fund be
  // silently retyped: the select had no matching option, the browser submitted
  // the first one, and the server took it. The state now reflects what the row
  // actually says, and an unknown value renders as an empty select rather than
  // as a confident wrong answer.
  const [b, setB] = useState((basis ?? "") as string);
  const isNav = b === "nav";
  const isReturn = b === "return";

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
              <option value="">Not set</option>
              {BASES.map(([k, l]) => (
                <option key={k} value={k}>{l}</option>
              ))}
            </select>
          </label>

          <label className="field">
            <span>Quoted net of</span>
            <select name="net_of" defaultValue={netOf ?? ""} className="select">
              <option value="">Not set</option>
              {NET_OF.map(([k, l]) => (
                <option key={k} value={k}>{l}</option>
              ))}
            </select>
            <span className="hint">
              Read the fact sheet disclaimer, do not infer this. Etica&apos;s money market sheet says net of fees
              and gross of withholding tax; its Special Multi Asset sheet says net of all fees and taxes. Same
              manager, same page layout, opposite answers, and the app deducted 15% from both.
            </span>
          </label>

          {isReturn ? (
            <>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
                <label className="field">
                  <span>Period</span>
                  <select name="return_period" defaultValue={returnPeriod ?? "quarter"} className="select">
                    {RETURN_PERIODS.map(([k, l]) => (
                      <option key={k} value={k}>{l}</option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>Period ended</span>
                  <input name="return_as_of" type="date" defaultValue={returnAsOf ?? ""} className="input" />
                </label>
              </div>
              <span className="hint">
                This fund publishes a realized return for a closed period, not a yield. Leave the Rate box above
                empty: current_rate is the field the app taxes and compounds, and a quarterly figure sitting in it
                is what produced a two year projection off a fund with two quarters of history.
              </span>
            </>
          ) : null}

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 14 }}>
            <label className="field">
              <span>Fee is a</span>
              <select name="fee_kind" defaultValue={feeKind ?? ""} className="select">
                <option value="">Not set</option>
                {FEE_KINDS.map(([k, l]) => (
                  <option key={k} value={k}>{l}</option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Performance fee %</span>
              <input name="perf_fee_pct" type="number" step="any" min="0" defaultValue={perfFeePct ?? ""}
                className="input num-input" placeholder="10" />
            </label>
            <label className="field">
              <span>Hurdle %</span>
              <input name="hurdle_pct" type="number" step="any" min="0" defaultValue={hurdlePct ?? ""}
                className="input num-input" placeholder="25" />
            </label>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <label className="field">
              <span>Class group</span>
              <input name="class_group" defaultValue={classGroup ?? ""} className="input"
                placeholder="etica-special-wealth" />
            </label>
            <label className="field">
              <span>Class label</span>
              <input name="class_label" defaultValue={classLabel ?? ""} className="input" placeholder="A" />
            </label>
          </div>
          <span className="hint">
            Only for one product sold in several classes: same fund, different lock-in and fee and yield. Give every
            sibling the same group. Leave both empty otherwise, which is nearly always. A class group must contribute
            ONE row to any league table, never one per class, or the longest lock-in wins every yield sort by
            construction and pushes two real competitors off the board.
          </span>

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
              {pricePerUnit != null ? `${currency} ${Number(pricePerUnit).toFixed(2)}` : "-"}
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
                      <span className={"method " + (h.source === "manual" ? "manual" : "auto")}>{h.source ?? "-"}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {isReturn && (
        <div className="panelc">
          <div className="ph">
            <h3>Period returns</h3>
            <span className="sub">closed periods &middot; builds the chart</span>
          </div>

          <div className="pb">
            <form action={setPeriodReturn} style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
              <input type="hidden" name="id" value={id} />
              <label className="field">
                <span>Period</span>
                <select name="period" defaultValue="quarter" className="select">
                  {RETURN_PERIODS.map(([k, l]) => (
                    <option key={k} value={k}>{l}</option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>Period ended</span>
                <input name="period_end" type="date" className="input" required />
              </label>
              <label className="field">
                <span>Net return %</span>
                <input name="net_pct" type="number" step="any" placeholder="4.74"
                  className="input num-input" required />
              </label>
              <label className="field">
                <span>Gross return % (optional)</span>
                <input name="gross_pct" type="number" step="any" placeholder="9.74"
                  className="input num-input" />
              </label>
              <label className="field" style={{ gridColumn: "1 / -1" }}>
                <span>This row is quoted net of</span>
                <select name="net_of" defaultValue={netOf ?? "fees"} className="select">
                  {NET_OF.map(([k, l]) => (
                    <option key={k} value={k}>{l}</option>
                  ))}
                </select>
              </label>
              <div style={{ gridColumn: "1 / -1" }}>
                <button className="btn xs">Add period</button>
              </div>
            </form>

            <p style={{ marginTop: 10, fontSize: 11.5, color: "var(--faint)", lineHeight: 1.55 }}>
              A negative return is allowed and expected. MansaX posted 3.78% in one quarter and 6.05% two quarters
              later, and a rule that dropped the weak periods would leave a chart showing only the strong ones,
              which misleads more than no chart at all.
            </p>
            <p style={{ marginTop: 6, fontSize: 11.5, color: "var(--faint)", lineHeight: 1.55 }}>
              Do not enter an annualised figure. A quarter multiplied by four is not a year, and on a fund with two
              quarters behind it that number is a guess wearing a fact&rsquo;s clothes. Enter the closed periods the
              sheet prints, and if the manager publishes a since-inception total, add it as its own row so the
              growth card can use the manager&rsquo;s own endpoint instead of compounding an approximation of it.
            </p>
          </div>

          {returnHistory.length === 0 ? (
            <div className="pb" style={{ paddingTop: 0, color: "var(--muted)", fontSize: 13.5 }}>
              No periods yet. The chart needs at least four; below that the app states the holding period in words
              rather than drawing a trend through two points.
            </div>
          ) : (
            <table className="tbl">
              <tbody>
                {returnHistory.map((r) => (
                  <tr key={`${r.period}-${r.period_end}`}>
                    <td style={{ color: "var(--faint)" }}>{r.period_end}</td>
                    <td style={{ fontSize: 11, color: "var(--muted)" }}>{PERIOD_LABEL[r.period] ?? r.period}</td>
                    <td className="r num" style={{ color: r.net_pct < 0 ? "var(--bad)" : "var(--ink)" }}>
                      {Number(r.net_pct).toFixed(2)}%
                    </td>
                    <td className="r num" style={{ fontSize: 11, color: "var(--faint)" }}>
                      {r.gross_pct != null ? `${Number(r.gross_pct).toFixed(2)}% gr` : ""}
                    </td>
                    <td className="r" style={{ fontSize: 10.5, color: "var(--faint)" }}>
                      {NET_OF_SHORT[r.net_of] ?? r.net_of}
                    </td>
                    <td className="r">
                      <form action={deletePeriodReturn}>
                        <input type="hidden" name="id" value={id} />
                        <input type="hidden" name="period_end" value={r.period_end} />
                        <input type="hidden" name="period" value={r.period} />
                        <button className="btn xs" title="Remove this period">Remove</button>
                      </form>
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
