import { adminClient } from "../_shared/supabase.ts";
import { validate } from "../_shared/validate.ts";
import type { RatePoint, SourceAdapter } from "../_shared/types.ts";
import { industryTableAdapter } from "./adapters/industry-table.ts";
import { eticaSiteAdapter } from "./adapters/etica-site.ts";
import { pressMmfAdapter } from "./adapters/press-mmf.ts";
import { serrariMmfAdapter } from "./adapters/serrari-mmf.ts";
import { KES_MMF_NAME_MAP, USD_MMF_NAME_MAP, normalize } from "./adapters/fund-name-map.ts";
import { publishSnapshot } from "../_shared/snapshot.ts";
import { fetchUsdKes, recordFxHealth } from "../_shared/fx.ts";

// Backbone scraper: one structured source -> many funds, once daily.
// Invoked by pg_cron (see migrations/0004_cron.sql) and by the admin's
// manual "re-run" button. Never retried automatically, so it logs every run.
Deno.serve(async (req) => {
  // Auth: only pg_cron / the admin (both send the shared secret) may run it.
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  // Who fired this run? pg_cron posts {} (=> cron); the admin re-run posts
  // {"trigger":"manual"}. Read defensively so a missing/empty body is fine.
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const trigger = body?.trigger === "manual" ? "manual" : "cron";

  const db = adminClient();
  const source = "ke-aggregator";
  const startedAt = new Date().toISOString();
  // "Today" in EAT (UTC+3): the day the rate is recorded against.
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10);

  const errors: string[] = [];
  const unmapped: string[] = [];
  const points: RatePoint[] = [];

  // 1. Fetch every configured source, map its rows to fund_ids via one merged
  //    name map. Official per-provider sources (Etica) run LAST so they win the
  //    upsert over the press aggregate for the same fund/day.
  const NAME_MAP: Record<string, string> = { ...KES_MMF_NAME_MAP, ...USD_MMF_NAME_MAP };
  const env = (k: string) => Deno.env.get(k);
  const adapters = [
    env("AGGREGATOR_URL_KES") && industryTableAdapter(env("AGGREGATOR_URL_KES")!, "KES"),
    env("AGGREGATOR_URL_USD") && industryTableAdapter(env("AGGREGATOR_URL_USD")!, "USD"),
    env("PRESS_MMF_CSV_URL") && pressMmfAdapter(env("PRESS_MMF_CSV_URL")!),
    env("SERRARI_MMF_URL") && serrariMmfAdapter(env("SERRARI_MMF_URL")!),
    env("ETICA_URL") && eticaSiteAdapter(env("ETICA_URL")!),
  ].filter(Boolean) as SourceAdapter[];

  for (const adapter of adapters) {
    try {
      const rows = await adapter.fetchRows();
      for (const row of rows) {
        const id = NAME_MAP[normalize(row.name)];
        if (!id) { unmapped.push(`${adapter.id}:${row.name}`); continue; }
        // Provenance: record which source produced the point.
        points.push({ fund_id: id, rate: row.rate, as_of: row.asOf ?? asOf, source: adapter.id });
      }
    } catch (e) {
      errors.push(`${adapter.id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  // 2. Validate against last-known rates.
  const { data: latest } = await db
    .from("rate_history").select("fund_id, rate, as_of").order("as_of", { ascending: false });
  const prev: Record<string, number> = {};
  for (const r of latest ?? []) if (prev[r.fund_id] == null) prev[r.fund_id] = r.rate;

  // 2b. Reconcile the sources per fund into one point (consensus). When two or
  //     more sources report the same fund, agreement within CONSENSUS_TOL_PP
  //     applies the median; disagreement holds the fund for manual review
  //     (reason "conflict") and applies nothing. A single source passes through
  //     to the normal jump check.
  const CONSENSUS_TOL_PP = 0.25;
  const median = (xs: number[]) => { const s = [...xs].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };

  const bySrc = new Map<string, RatePoint[]>();
  for (const pt of points) { const a = bySrc.get(pt.fund_id) ?? []; a.push(pt); bySrc.set(pt.fund_id, a); }

  const reconciled: RatePoint[] = [];
  const conflicts: { fund_id: string; as_of: string; mid: number; spread: number; label: string }[] = [];
  for (const [fund_id, pts] of bySrc) {
    if (pts.length === 1) { reconciled.push(pts[0]); continue; }
    const rates = pts.map((p) => p.rate);
    const spread = Math.max(...rates) - Math.min(...rates);
    if (spread <= CONSENSUS_TOL_PP) {
      const mid = median(rates);
      const chosen = pts.reduce((b, p) => Math.abs(p.rate - mid) < Math.abs(b.rate - mid) ? p : b);
      reconciled.push({ ...chosen, rate: mid }); // consensus value, provenance of the nearest source
    } else {
      conflicts.push({
        fund_id, as_of: pts[0].as_of, mid: median(rates), spread,
        label: pts.map((p) => `${p.source} ${p.rate}`).join(" vs "),
      });
    }
  }

  const { ok, rejected, review } = validate(reconciled, prev);

  // 3. Write accepted points; refresh current_rate + mark live.
  if (ok.length) {
    await db.from("rate_history").upsert(ok, { onConflict: "fund_id,as_of" });
    for (const p of ok) {
      await db.from("funds").update({ current_rate: p.rate, status: "live" }).eq("id", p.fund_id);
    }
  }

  // 3.1 Hold for manual approval: surprising single-source jumps AND cross-source
  //     conflicts. Disjoint by fund (conflicts never reach validate), so merge.
  const reviewRows = [
    ...review.map((r) => ({
      fund_id: r.point.fund_id, source: r.point.source, old_rate: r.old_rate,
      new_rate: r.point.rate, delta_bps: r.delta_bps, as_of: r.point.as_of,
      reason: r.reason, status: "pending",
    })),
    ...conflicts.map((c) => ({
      fund_id: c.fund_id, source: c.label, old_rate: prev[c.fund_id] ?? null,
      new_rate: c.mid, delta_bps: Math.round(c.spread * 100), as_of: c.as_of,
      reason: "conflict", status: "pending",
    })),
  ];
  if (reviewRows.length) {
    await db.from("rate_review").upsert(reviewRows, { onConflict: "fund_id,as_of" });
  }

  // 3.5 USD/KES. Open Exchange Rates primary (OXR_APP_ID), keyless
  //     open.er-api.com fallback. Non-fatal, and upserted before the snapshot
  //     so it ships in the same publish.
  //
  //     It records its own health, because the failure mode here is silent:
  //     past its monthly quota OXR simply stops answering, the last rate stays
  //     in the table, and the currency card keeps rendering a stale number that
  //     looks exactly like a fresh one. source_health carries the quota readout
  //     so admin can see it coming.
  let fx: string | null = null;
  try {
    const result = await fetchUsdKes();
    if (result.point) {
      await db.from("fx_rates").upsert(result.point, {
        onConflict: "pair,as_of",
      });
      fx = `${result.point.pair} ${result.point.rate} (${result.point.source})`;
    }
    if (result.error) errors.push(`fx: ${result.error}`);
    await recordFxHealth(db, result);
  } catch (e) {
    errors.push(`fx: ${e instanceof Error ? e.message : String(e)}`);
  }

  // 4. Refresh the app snapshot (one static file, read cache-first by the app).
  let snapshot = null;
  if (ok.length || fx) {
    try { snapshot = await publishSnapshot(db); }
    catch (e) { errors.push(`snapshot: ${e instanceof Error ? e.message : String(e)}`); }
  }

  // 5. Emit events (writes market_events + pushes) for any fund whose rate moved.
  const changed = ok.filter((p) => prev[p.fund_id] != null && prev[p.fund_id] !== p.rate);
  if (changed.length) {
    const ids = changed.map((p) => p.fund_id);
    const { data: named } = await db.from("funds").select("id,name").in("id", ids);
    const nameById: Record<string, string> = Object.fromEntries((named ?? []).map((r) => [r.id, r.name]));
    try {
      await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/emit-events`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-cron-secret": Deno.env.get("CRON_SECRET") ?? "" },
        body: JSON.stringify({
          changes: changed.map((p) => ({
            fundId: p.fund_id,
            name: nameById[p.fund_id] ?? p.fund_id,
            oldRate: prev[p.fund_id],
            newRate: p.rate,
          })),
        }),
      });
    } catch (_) { /* non-fatal */ }
  }

  // 6. Log the run for the admin's scraper-health view.
  await db.from("scraper_runs").insert({
    source,
    trigger,
    started_at: startedAt,
    finished_at: new Date().toISOString(),
    written: ok.length,
    rejected: rejected.length,
    unmapped,
    errors: [...errors, ...rejected.map((r) => `${r.point.fund_id}: ${r.reason}`)],
    ok: errors.length === 0,
  });

  return Response.json({ source, trigger, written: ok.length, rejected: rejected.length, held: reviewRows.length, conflicts: conflicts.length, unmapped, fx, snapshot, errors });
});
