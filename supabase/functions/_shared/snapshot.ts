import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type {
  SnapshotAgent,
  SnapshotCompany,
  SnapshotEvent,
  SnapshotFx,
  SnapshotInsurer,
  SnapshotTemplate,
  SnapshotV2,
} from "./types.ts";

// Publishes ONE static snapshot the app reads cache-first, instead of the app
// querying Supabase on every open. Called at the end of every scrape run, and
// standalone via the publish-snapshot function.
//
// v2: adds companies/agents/insurers/fx/insight_templates/events. Every v1
// field is preserved; the app reads `schema` and falls back to v1 parsing.

const BUCKET = "snapshots";
const FILE = "funds-snapshot.json";

const FUND_FIELDS =
  "id,name,manager,category,fund_type,currency,basis,retail,current_rate,tax_free,min_invest,mgmt_fee,site_url,invest_url,contact_url,logo_domain,verified,featured,company_id";

const INSURER_FIELDS =
  "id,name,company_id,currency,plans,min_premium,excess_pct,excess_min,claims_days,rating,motor_rate,benefits,logo_domain";

// Sibling composition array (migration 0017: funds.composition jsonb +
// aum_kes + aum_as_of + composition_source_url). Keyed by fund_id and kept
// OUT of the funds rows — mirrors the deltas pattern, so the app's Fund
// model and rates path stay untouched.
type SnapshotComposition = {
  fund_id: string;
  classes: Record<string, number>; // 8 CMA classes, absolute KES
  aum_kes: number | null;
  as_of: string | null;
  source_url: string | null;
};

export async function publishSnapshot(
  db: SupabaseClient,
): Promise<{ count: number; url: string }> {
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT day

  // Funds (kind='fund') — the app's rate list.
  const { data: funds, error } = await db
    .from("funds")
    .select(FUND_FIELDS)
    .eq("kind", "fund")
    .neq("status", "hidden")
    .order("category", { ascending: true })
    .order("current_rate", { ascending: false, nullsFirst: false });
  if (error) throw new Error(`snapshot funds query failed: ${error.message}`);

  // C2 — compact per-fund sparkline (≤20 points, trailing 180 days) attached
  // to each fund row, so app tiles stop fetching per-fund history on scroll.
  // Full-resolution history stays behind getHistory for hero/Company/Compare.
  // 180d (not 90d): while marks are sparse (Apr/Jun 2026 backfill + scrapes),
  // a 90d window can leave a single point and every sparkline hides itself.
  const cutoff = new Date(Date.now() - 180 * 86_400_000)
    .toISOString()
    .slice(0, 10);
  const { data: histRows } = await db
    .from("rate_history")
    .select("fund_id,rate,as_of")
    .gte("as_of", cutoff)
    .order("as_of", { ascending: true })
    .limit(20000);
  const histByFund = new Map<string, number[]>();
  for (const h of histRows ?? []) {
    const arr = histByFund.get(h.fund_id) ?? [];
    arr.push(h.rate);
    histByFund.set(h.fund_id, arr);
  }
  const downsample = (xs: number[], n = 20): number[] => {
    if (xs.length <= n) return xs;
    const out: number[] = [];
    for (let i = 0; i < n; i++) {
      out.push(xs[Math.round((i * (xs.length - 1)) / (n - 1))]);
    }
    return out;
  };
  const fundsWithSpark = (funds ?? []).map((f) => {
    const h = histByFund.get((f as { id: string }).id);
    return h && h.length >= 2 ? { ...f, spark: downsample(h) } : f;
  });

  // Insurers (kind='insurance') — separate array, kept out of the rate list.
  const { data: insurers } = await db
    .from("funds")
    .select(INSURER_FIELDS)
    .eq("kind", "insurance")
    .neq("status", "hidden");

  const { data: companies } = await db
    .from("companies")
    .select(
      "id,name,type,brand_color,logo_url,website,verified,aum_kes,market_share,rank,aum_as_of",
    );

  // Agents + their company mapping.
  const { data: agentRows } = await db
    .from("agents")
    .select("id,name,role,phone,whatsapp,photo_url,is_free")
    .eq("active", true);
  const { data: joins } = await db
    .from("agent_companies")
    .select("agent_id,company_id");
  const byAgent = new Map<string, string[]>();
  for (const j of joins ?? []) {
    const arr = byAgent.get(j.agent_id) ?? [];
    arr.push(j.company_id);
    byAgent.set(j.agent_id, arr);
  }
  const agents: SnapshotAgent[] = (agentRows ?? []).map((a) => ({
    ...a,
    company_ids: byAgent.get(a.id) ?? [],
  }));

  // FX — latest row per pair.
  const { data: fxRows } = await db
    .from("fx_rates")
    .select("pair,rate,as_of")
    .order("as_of", { ascending: false });
  const fxByPair = new Map<string, SnapshotFx>();
  for (const r of fxRows ?? []) {
    if (!fxByPair.has(r.pair)) fxByPair.set(r.pair, r);
  }

  const { data: templates } = await db
    .from("insight_templates")
    .select("key,tag,template")
    .eq("active", true);

  const { data: events } = await db
    .from("market_events")
    .select("type,category,fund_id,payload,created_at")
    .order("created_at", { ascending: false })
    .limit(10);

  // Remote config (V6): admin-edited key/values ride in the snapshot.
  const { data: configRows } = await db.from("app_config").select("key,value");
  const config: Record<string, unknown> = Object.fromEntries(
    (configRows ?? []).map((r) => [r.key, r.value]),
  );

  // Composition — only funds that actually carry a breakdown.
  const { data: compRows } = await db
    .from("funds")
    .select("id,composition,aum_kes,aum_as_of,composition_source_url")
    .eq("kind", "fund")
    .neq("status", "hidden")
    .not("composition", "is", null);
  const composition: SnapshotComposition[] = (compRows ?? [])
    .filter((r) =>
      r.composition && typeof r.composition === "object" &&
      Object.values(r.composition as Record<string, unknown>).some((v) =>
        typeof v === "number" && v > 0
      )
    )
    .map((r) => ({
      fund_id: r.id,
      classes: r.composition as Record<string, number>,
      aum_kes: r.aum_kes ?? null,
      as_of: r.aum_as_of ?? null,
      source_url: r.composition_source_url ?? null,
    }));

  const snapshot:
    & SnapshotV2
    & { composition: SnapshotComposition[]; config: Record<string, unknown> } = {
    schema: 2,
    as_of: asOf,
    funds: fundsWithSpark as SnapshotV2["funds"],
    insurers: (insurers ?? []) as SnapshotInsurer[],
    companies: (companies ?? []) as SnapshotCompany[],
    agents,
    fx: [...fxByPair.values()],
    insight_templates: (templates ?? []) as SnapshotTemplate[],
    events: (events ?? []) as SnapshotEvent[],
    composition,
    config,
  };

  const body = new TextEncoder().encode(JSON.stringify(snapshot));
  const { error: upErr } = await db.storage.from(BUCKET).upload(FILE, body, {
    upsert: true,
    contentType: "application/json",
    // 60s, not 1h. The file changes on every scrape/admin edit, so a long
    // max-age made a fresh publish take up to an hour to reach devices even
    // though the app revalidates via ETag. 60s lets fetch-if-changed actually
    // run soon after a republish; unchanged fetches still return a cheap 304.
    cacheControl: "60",
  });
  if (upErr) throw new Error(`snapshot upload failed: ${upErr.message}`);

  const base = Deno.env.get("SUPABASE_URL");
  return {
    count: funds?.length ?? 0,
    url: `${base}/storage/v1/object/public/${BUCKET}/${FILE}`,
  };
}
