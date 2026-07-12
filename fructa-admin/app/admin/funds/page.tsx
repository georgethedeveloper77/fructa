import { supabaseAdmin } from "@/lib/supabase/server";
import { FundsTable, type FundRow, type Co } from "./FundsTable";
import { ImportFundDetails } from "./ImportFundDetails";
import { AddFund } from "./AddFund";

export const dynamic = "force-dynamic";

const FT: [string, string][] = [
  ["mmf", "MMF"], ["fixed_income", "Fixed Income"], ["equity", "Equity"],
  ["balanced", "Balanced"], ["special", "Special"],
];

export default async function FundsPage() {
  const db = supabaseAdmin();
  const [{ data: fundsData, error }, { data: cos }, { data: rh }] = await Promise.all([
    db.from("funds")
      .select("id,name,manager,fund_type,category,currency,current_rate,status,verified,featured,retail,company_id,logo_domain,basis,price_per_unit,price_as_of,distribution_pct")
      .eq("kind", "fund")
      .order("name"),
    db.from("companies").select("id,name,logo_url,brand_color"),
    // Latest rate_history row per fund gives the current rate's provenance
    // (source) and freshness (as_of). Ordered newest-first; the first row seen
    // for each fund wins. onConflict(fund_id,as_of) keeps one row per day, so
    // "latest as_of" is unambiguous.
    db.from("rate_history").select("fund_id,source,as_of").order("as_of", { ascending: false }),
  ]);
  const funds = (fundsData ?? []) as FundRow[];
  const companies = (cos ?? []) as Co[];

  // fund_id -> { source, asOf } for the most recent rate. Plain object so it
  // serialises across the server/client boundary into FundsTable.
  const prov: Record<string, { source: string | null; asOf: string | null }> = {};
  for (const r of (rh ?? []) as { fund_id: string; source: string | null; as_of: string | null }[]) {
    if (!prov[r.fund_id]) prov[r.fund_id] = { source: r.source, asOf: r.as_of };
  }

  const total = funds.length;
  const missing = funds.filter((f) => f.current_rate == null).length;
  const priced = total - missing;
  const hidden = funds.filter((f) => f.status === "hidden").length;
  const retail = funds.filter((f) => f.retail).length;
  const coverage = total ? Math.round((priced / total) * 100) : 0;

  const kpis: { label: string; value: number; sub?: string; tone?: "warn" | "ok" }[] = [
    { label: "Funds", value: total },
    { label: "Priced", value: priced, sub: `${coverage}% coverage`, tone: coverage >= 80 ? "ok" : undefined },
    { label: "Missing rate", value: missing, tone: missing ? "warn" : "ok" },
    { label: "In app", value: retail },
    { label: "Hidden", value: hidden },
  ];
  const byType = FT.map(([k, l]) => ({ label: l, n: funds.filter((f) => f.fund_type === k).length }));

  return (
    <div className="mx-auto max-w-6xl">
      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>
      )}

      {/* KPIs */}
      <div className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-5">
        {kpis.map((k) => (
          <div key={k.label} className="rounded-xl border border-line bg-panel px-4 py-3">
            <div className="text-[10px] uppercase tracking-wider text-faint">{k.label}</div>
            <div className={"mt-0.5 text-2xl font-semibold tnum " + (k.tone === "warn" ? "text-warn" : k.tone === "ok" ? "text-live" : "text-ink")}>{k.value}</div>
            {k.sub && <div className="text-[11px] text-faint">{k.sub}</div>}
          </div>
        ))}
      </div>

      {/* type distribution + create */}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex flex-1 flex-wrap gap-x-5 gap-y-1 rounded-xl border border-line bg-panel px-4 py-2.5 text-xs text-mute">
          {byType.map((t) => (
            <span key={t.label}><span className="tnum font-medium text-ink">{t.n}</span> {t.label}</span>
          ))}
        </div>
        <AddFund companies={companies} />
      </div>

      <ImportFundDetails />

      <FundsTable rows={funds} companies={companies} prov={prov} />
    </div>
  );
}
