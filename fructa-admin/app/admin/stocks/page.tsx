import { supabaseAdmin } from "@/lib/supabase/server";
import { StocksTable, type StockRow } from "./StocksTable";
import { AddStock } from "./AddStock";
import { ImportDividends } from "./ImportDividends";

export const dynamic = "force-dynamic";

type DivRow = { stock_id: string; financial_year: number; dps_kes: number };

export default async function StocksPage() {
  const db = supabaseAdmin();
  const [{ data: stockData, error }, { data: divData }, { data: cfg }] = await Promise.all([
    db.from("stocks")
      .select("id,ticker,name,sector,segment,logo_url,brand_color,shares_outstanding,active")
      .order("name"),
    db.from("stock_dividends").select("stock_id,financial_year,dps_kes"),
    db.from("app_config").select("value").eq("key", "stocks.prices_enabled").maybeSingle(),
  ]);

  const pricesEnabled = cfg?.value === true;

  // Latest financial year per stock, with all its kinds summed. Mirrors what
  // publish-snapshot computes, so admin and app agree on the headline dividend.
  const byStock = new Map<string, DivRow[]>();
  for (const d of (divData ?? []) as DivRow[]) {
    const arr = byStock.get(d.stock_id) ?? [];
    arr.push(d);
    byStock.set(d.stock_id, arr);
  }

  const rows: StockRow[] = ((stockData ?? []) as Omit<StockRow, "dps_latest" | "dps_year" | "div_count">[])
    .map((s) => {
      const divs = byStock.get(s.id) ?? [];
      const year = divs.length ? Math.max(...divs.map((d) => d.financial_year)) : null;
      const dps = year == null
        ? null
        : Number(divs.filter((d) => d.financial_year === year)
          .reduce((a, d) => a + Number(d.dps_kes), 0).toFixed(4));
      return { ...s, dps_latest: dps, dps_year: year, div_count: divs.length };
    });

  const total = rows.length;
  const live = rows.filter((s) => s.active).length;
  const withDiv = rows.filter((s) => s.dps_latest != null).length;
  const withShares = rows.filter((s) => s.shares_outstanding != null).length;
  const coverage = total ? Math.round((withDiv / total) * 100) : 0;

  const kpis: { label: string; value: number | string; sub?: string; tone?: "warn" | "ok" }[] = [
    { label: "Stocks", value: total },
    { label: "In app", value: live },
    { label: "With dividend", value: withDiv, sub: `${coverage}% coverage`, tone: coverage >= 60 ? "ok" : "warn" },
    { label: "Shares out set", value: withShares, sub: "needed for market cap" },
    { label: "Prices", value: pricesEnabled ? "on" : "off", tone: pricesEnabled ? "ok" : undefined },
  ];

  return (
    <div className="mx-auto max-w-6xl">
      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>
      )}

      {/* Licence state. This is the single most important thing on the page, so
          it is stated plainly rather than buried in a tooltip. */}
      {!pricesEnabled && (
        <div className="mb-3 rounded-xl border border-warn/30 bg-warn/5 px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-warn">Prices are off</div>
          <p className="mt-1 text-sm leading-relaxed text-mute">
            NSE price data needs a redistribution licence, so the snapshot publishes no price, day change, market cap,
            sparkline or dividend yield. Stock pages still show company facts, declared dividends and where to buy.
            Turn prices on with the <code className="text-faint">stocks.prices_enabled</code> config key once an
            agreement is in place, and the app picks them up on the next rebuild with no release.
          </p>
        </div>
      )}

      <div className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-5">
        {kpis.map((k) => (
          <div key={k.label} className="rounded-xl border border-line bg-panel px-4 py-3">
            <div className="text-[10px] uppercase tracking-wider text-faint">{k.label}</div>
            <div className={"mt-0.5 text-2xl font-semibold tnum " + (k.tone === "warn" ? "text-warn" : k.tone === "ok" ? "text-live" : "text-ink")}>
              {k.value}
            </div>
            {k.sub && <div className="text-[11px] text-faint">{k.sub}</div>}
          </div>
        ))}
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex flex-1 flex-wrap gap-x-5 gap-y-1 rounded-xl border border-line bg-panel px-4 py-2.5 text-xs text-mute">
          {["MIM", "AIM", "GEMS"].map((seg) => (
            <span key={seg}>
              <span className="tnum font-medium text-ink">{rows.filter((s) => s.segment === seg).length}</span> {seg}
            </span>
          ))}
        </div>
        <AddStock />
      </div>

      <ImportDividends />

      <StocksTable rows={rows} />
    </div>
  );
}
