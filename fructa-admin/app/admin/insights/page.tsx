import { supabaseAdmin } from "@/lib/supabase/server";
import { InsightsTabs } from "./InsightsTabs";
import { type Template } from "./SignalBank";
import { type MarketData } from "./MarketTab";

export const dynamic = "force-dynamic";

// Statutory withholding tax on interest. Stable Kenyan law, so it is a constant
// here rather than a query; repoint to benchmarks.wht once that table is wired.
const WHT_RATE = 0.15;

type FundLite = {
  id: string; name: string; manager: string;
  fund_type: string | null; currency: string;
  current_rate: number | null; status: string; basis: string | null;
};
type RH = { fund_id: string; rate: number; as_of: string };

const CLASS_LABEL: Record<string, string> = {
  mmf: "MMF", fixed_income: "Fixed income", equity: "Equity",
  balanced: "Balanced", special: "Special",
};

export default async function InsightsPage() {
  const db = supabaseAdmin();
  const cutoff = new Date(Date.now() - 180 * 864e5).toISOString().slice(0, 10);

  const [tmpl, fundsRes, rhRes] = await Promise.all([
    db.from("insight_templates").select("id,key,tag,template,active").order("key").order("id"),
    db.from("funds").select("id,name,manager,fund_type,currency,current_rate,status,basis").eq("kind", "fund"),
    db.from("rate_history").select("fund_id,rate,as_of").gte("as_of", cutoff),
  ]);

  const templates = (tmpl.data ?? []) as Template[];
  const funds = (fundsRes.data ?? []) as FundLite[];
  const rh = (rhRes.data ?? []) as RH[];

  // ── MMF (KES) universe: the headline market ────────────────────────────────
  const mmf = funds.filter(
    (f) => f.fund_type === "mmf" && f.currency === "KES" && f.status !== "hidden" && f.current_rate != null,
  );
  const rates = mmf.map((f) => f.current_rate as number);
  const top = mmf.reduce<{ name: string; rate: number } | null>(
    (a, f) => (a && a.rate >= (f.current_rate as number) ? a : { name: f.name, rate: f.current_rate as number }),
    null,
  );
  const avg = rates.length ? rates.reduce((a, b) => a + b, 0) / rates.length : null;
  const min = rates.length ? Math.min(...rates) : null;
  const spread = top && min != null ? top.rate - min : null;
  const netTop = top ? top.rate * (1 - WHT_RATE) : null;

  // ── distribution by rate band ──────────────────────────────────────────────
  const bands: { label: string; test: (r: number) => boolean }[] = [
    { label: "8-10", test: (r) => r < 10 },
    { label: "10-12", test: (r) => r >= 10 && r < 12 },
    { label: "12-14", test: (r) => r >= 12 && r < 14 },
    { label: "14+", test: (r) => r >= 14 },
  ];
  const distribution = bands.map((b) => ({ label: b.label, count: rates.filter(b.test).length }));

  // ── leaderboard ────────────────────────────────────────────────────────────
  const leaders = [...mmf]
    .sort((a, b) => (b.current_rate as number) - (a.current_rate as number))
    .slice(0, 6)
    .map((f) => ({ name: f.name, rate: f.current_rate as number }));

  // ── average yield by asset class (funds that quote a yield) ─────────────────
  const classMap = new Map<string, number[]>();
  for (const f of funds) {
    if (f.current_rate == null || f.basis === "none" || !f.fund_type) continue;
    classMap.set(f.fund_type, [...(classMap.get(f.fund_type) ?? []), f.current_rate]);
  }
  const byClass = [...classMap.entries()]
    .map(([ft, arr]) => ({ label: CLASS_LABEL[ft] ?? ft, avg: arr.reduce((a, b) => a + b, 0) / arr.length, count: arr.length }))
    .sort((a, b) => b.avg - a.avg);

  // ── trend: MMF rate_history bucketed by day ────────────────────────────────
  const mmfIds = new Set(mmf.map((f) => f.id));
  const byDay = new Map<string, number[]>();
  for (const r of rh) {
    if (!mmfIds.has(r.fund_id)) continue;
    byDay.set(r.as_of, [...(byDay.get(r.as_of) ?? []), r.rate]);
  }
  let series = [...byDay.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([date, arr]) => ({ date, avg: arr.reduce((a, b) => a + b, 0) / arr.length, top: Math.max(...arr) }));
  if (series.length > 14) {
    const step = (series.length - 1) / 13;
    series = Array.from({ length: 14 }, (_, i) => series[Math.round(i * step)]);
  }

  const topDelta = series.length > 1 ? series[series.length - 1].top - series[0].top : null;
  const avgDelta = series.length > 1 ? series[series.length - 1].avg - series[0].avg : null;

  const market: MarketData = {
    snapshotFunds: funds.filter((f) => f.status !== "hidden").length,
    mmfCount: mmf.length,
    top, avg, netTop, spread, topDelta, avgDelta,
    distribution, leaders, byClass, trend: series,
    benchmarks: null, // TODO: wire benchmarks table (inflation, cbr, tbill91/182/364, wht)
  };

  const dbError = fundsRes.error ?? rhRes.error ?? tmpl.error ?? null;

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-2">
        <h1 className="text-2xl font-semibold tracking-tight">Insights</h1>
        <p className="mt-1 text-sm text-mute">
          What the Kenyan money market looks like right now, read off the rate history the pipeline collects.
          The Signal bank tab holds the app phrasings.
        </p>
      </header>

      {dbError && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{dbError.message}</p>
      )}

      <InsightsTabs market={market} templates={templates} />
    </div>
  );
}
