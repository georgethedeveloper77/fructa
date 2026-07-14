import { supabaseAdmin } from "@/lib/supabase/server";
import { ConfigWorkspace } from "./ConfigWorkspace";
import type { ConfigRow } from "./actions";
import type { Board } from "./impact";

export const dynamic = "force-dynamic";

// Brand, SEO, store links and landing copy live under Settings, which has proper
// forms for them. Remote config stays operational: benchmarks, flags, the CMA
// market tables, search and onboarding.
const SETTINGS_NS = /^(brand|seo|links|landing)\./;

/** The published value of a rate key, for the "before" side of impact figures. */
function rateOf(rows: ConfigRow[], key: string, fallback: number): number {
  const v = rows.find((r) => r.key === key)?.value;
  const n = Number((v as { rate?: unknown } | undefined)?.rate);
  return Number.isFinite(n) ? n : fallback;
}

export default async function ConfigPage() {
  const db = supabaseAdmin();

  const [cfgRes, fundsRes] = await Promise.all([
    db.from("app_config").select("key,value,description,updated_at").order("key"),
    // The live board the impact figures are computed against: KES money market
    // funds with a real yield. basis = 'yield' excludes priced/NAV funds, which
    // have no rate to compare, and fund_type is the authoritative classifier.
    db
      .from("funds")
      .select("name,current_rate")
      .eq("fund_type", "mmf")
      .eq("currency", "KES")
      .eq("basis", "yield")
      .not("current_rate", "is", null)
      .order("current_rate", { ascending: false }),
  ]);

  const all = (cfgRes.data ?? []) as ConfigRow[];
  const rows = all.filter((r) => !SETTINGS_NS.test(r.key));

  const funds = (fundsRes.data ?? []) as { name: string; current_rate: number }[];
  const board: Board = {
    topName: funds[0]?.name ?? null,
    topRate: funds[0]?.current_rate ?? null,
    mmfRates: funds.map((f) => f.current_rate),
    wht: rateOf(all, "benchmark.wht_pct", 15),
    inflation: rateOf(all, "benchmark.inflation", 6.7),
  };

  const publishedAt =
    all.reduce<string | null>((mx, r) => (!mx || r.updated_at > mx ? r.updated_at : mx), null);

  // The workspace owns its own header, because the stale and due counts are
  // derived from the staged models on the client, not from the database rows.
  return (
    <div className="-m-6">
      <ConfigWorkspace rows={rows} board={board} publishedAt={publishedAt} />
    </div>
  );
}
