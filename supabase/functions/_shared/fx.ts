// USD/KES, fetched server-side by the aggregator and upserted into fx_rates so
// the app stays keyless.
//
// Replaces cbk-fx.ts. Two things changed and both were deliberate.
//
// 1. THE CBK PAGE PARSE IS GONE. It looked for a US DOLLAR row and took the
//    first plausible looking number out of the next 200 characters. Its own
//    comment told you to verify it against a fixture before trusting it. A
//    number produced by guessing is worse than a missing one, because nothing
//    downstream can tell the two apart. CBK history now enters through the CSV
//    backfill, which reads named columns and is exact.
//
// 2. OPEN EXCHANGE RATES IS PRIMARY. It has an account, a key, a status page
//    and a published quota, none of which the keyless endpoint has.
//    open.er-api.com stays as the fallback, because a fallback with no account
//    is exactly the right shape for a fallback.
//
// Secrets (Supabase function secrets, never in the app or the admin):
//   OXR_APP_ID   Open Exchange Rates app id. Absent means fallback only.
//
// WHAT THIS RETURNS IS A MID-MARKET RATE. Not a bank counter quote, and not
// CBK's indicative buy and sell. Nothing here populates fx_rates.bid or .ask,
// so the app keeps deriving the retail spread from the `fx.spread_pct` config
// key, which is an assumption and is labelled as one on screen.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.85.0";

export interface FxPoint {
  pair: string; // 'USD/KES'
  rate: number;
  as_of: string; // YYYY-MM-DD (EAT)
  source: string; // openexchangerates | open-er-api
}

export interface FxResult {
  point: FxPoint | null;
  /// Which source answered, or which one failed last. Always a source_health key.
  source: string;
  error: string | null;
  /// Short operator-facing status for source_health.note, e.g. the OXR quota.
  note: string | null;
}

export const OXR_SOURCE = "openexchangerates";
export const FALLBACK_SOURCE = "open-er-api";
export const FX_SOURCES = [OXR_SOURCE, FALLBACK_SOURCE];

const PAIR = "USD/KES";
const OXR_BASE = "https://openexchangerates.org/api";

/// The day the rate is recorded against. EAT is UTC+3.
function eatToday(): string {
  return new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10);
}

/// USD/KES has run roughly 100 to 165 over the last decade. Anything outside
/// this band is a broken response, a different pair, or a rate quoted the other
/// way up, and none of those should reach the database.
function plausible(n: unknown): number | null {
  return typeof n === "number" && Number.isFinite(n) && n >= 90 && n <= 250
    ? Number(n.toFixed(4))
    : null;
}

/// Open Exchange Rates. Shape: { base: "USD", rates: { KES: <num>, ... } }.
///
/// No `symbols` filter on purpose. Filtering is a paid-plan feature on some
/// tiers, and it saves nothing: a request costs one unit of quota whether it
/// returns one currency or two hundred.
async function fromOxr(appId: string): Promise<{ rate: number } | { error: string }> {
  try {
    const res = await fetch(`${OXR_BASE}/latest.json?app_id=${appId}`);
    if (!res.ok) {
      // 401 is a bad or revoked app id, 429 is the monthly quota. Both freeze
      // the rate silently if reported as a generic failure, so name them.
      const hint = res.status === 401
        ? "OXR_APP_ID is wrong or revoked"
        : res.status === 429
        ? "monthly request quota exhausted"
        : (await res.text()).slice(0, 160);
      return { error: `HTTP ${res.status}. ${hint}` };
    }
    const j = await res.json();
    const rate = plausible(j?.rates?.KES);
    if (rate == null) return { error: "no plausible KES rate in the response" };
    return { rate };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}

/// Free, no key. Shape: { result, rates: { KES: <num>, ... } }.
async function fromOpenErApi(): Promise<{ rate: number } | { error: string }> {
  try {
    const res = await fetch("https://open.er-api.com/v6/latest/USD");
    if (!res.ok) return { error: `HTTP ${res.status}` };
    const j = await res.json();
    const rate = plausible(j?.rates?.KES);
    if (rate == null) return { error: "no plausible KES rate in the response" };
    return { rate };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}

/// OXR's quota readout. Free, and it does NOT count against the quota, so it
/// can be called on every run. Returns a short display string or null.
///
/// This is the whole early warning system for this lane: past 1,000 requests
/// OXR stops answering and the rate freezes at whatever it last was, while the
/// currency card keeps rendering and keeps looking authoritative. Seeing
/// "940 / 1000" a week beforehand is the difference between noticing and not.
export async function fetchOxrUsage(appId: string): Promise<string | null> {
  try {
    const res = await fetch(`${OXR_BASE}/usage.json?app_id=${appId}`);
    if (!res.ok) return null;
    const j = await res.json();
    const u = j?.data?.usage;
    const used = Number(u?.requests);
    const quota = Number(u?.requests_quota);
    if (!Number.isFinite(used)) return null;
    // An unlimited plan reports -1 for both.
    if (quota < 0) return `${used} requests this month, unlimited plan`;
    return `${used} / ${quota} requests this month`;
  } catch {
    return null;
  }
}

/// Today's rate, from the best source that answers.
///
/// Never throws. A dead FX source must not take down a scrape run whose main
/// job is fund rates, so every failure comes back as data.
export async function fetchUsdKes(): Promise<FxResult> {
  const as_of = eatToday();
  const appId = Deno.env.get("OXR_APP_ID");

  if (appId) {
    const [r, note] = await Promise.all([fromOxr(appId), fetchOxrUsage(appId)]);
    if ("rate" in r) {
      return {
        point: { pair: PAIR, rate: r.rate, as_of, source: OXR_SOURCE },
        source: OXR_SOURCE,
        error: null,
        note,
      };
    }
    // OXR failed. Try the fallback, but keep OXR's error: that is the one
    // worth surfacing, because it is the source someone is paying attention to.
    const f = await fromOpenErApi();
    if ("rate" in f) {
      return {
        point: { pair: PAIR, rate: f.rate, as_of, source: FALLBACK_SOURCE },
        source: OXR_SOURCE,
        error: `${r.error} (fell back to ${FALLBACK_SOURCE})`,
        note,
      };
    }
    return {
      point: null,
      source: OXR_SOURCE,
      error: `${r.error}; fallback also failed: ${f.error}`,
      note,
    };
  }

  const f = await fromOpenErApi();
  if ("rate" in f) {
    return {
      point: { pair: PAIR, rate: f.rate, as_of, source: FALLBACK_SOURCE },
      source: FALLBACK_SOURCE,
      error: null,
      note: "OXR_APP_ID not set, running on the keyless fallback",
    };
  }
  return { point: null, source: FALLBACK_SOURCE, error: f.error, note: null };
}

/// Record what happened in source_health, so a dead key shows up in admin
/// instead of the rate quietly going stale.
///
/// Mirrors the backoff shape 0057 established for the NSE lane, with one
/// difference: FX is NOT put into cooldown. The aggregator runs once a weekday
/// and the FX call is a single request, so skipping it saves nothing worth
/// having, and a source that has recovered should start working again on its
/// own rather than waiting out a timer we invented.
export async function recordFxHealth(
  db: SupabaseClient,
  result: FxResult,
): Promise<void> {
  const now = new Date().toISOString();
  const ok = result.point != null && result.error == null;

  if (ok) {
    await db.from("source_health").upsert({
      source: result.source,
      consecutive_failures: 0,
      blocked_until: null,
      last_ok_at: now,
      last_error: null,
      note: result.note,
      updated_at: now,
    }, { onConflict: "source" });
    return;
  }

  // Read before write: the increment needs the current count, and there is no
  // atomic bump without an RPC. A lost update here costs one off-by-one in a
  // display counter, which is not worth a migration.
  const { data } = await db
    .from("source_health")
    .select("consecutive_failures")
    .eq("source", result.source)
    .maybeSingle();

  const failures = Number(data?.consecutive_failures ?? 0) + 1;

  await db.from("source_health").upsert({
    source: result.source,
    consecutive_failures: failures,
    last_error: result.error ?? "unknown failure",
    note: result.note,
    updated_at: now,
  }, { onConflict: "source" });
}
