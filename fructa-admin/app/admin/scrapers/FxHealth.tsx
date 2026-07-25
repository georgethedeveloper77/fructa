import { supabaseAdmin } from "@/lib/supabase/server";

/**
 * The FX lane, on the Scrapers page.
 *
 * It is not a Fleet entry because it is not a scraper. The USD/KES call rides
 * inside ke-aggregator's run, so it has no schedule of its own, no
 * scraper_runs row of its own, and nothing to press. Listing it beside the
 * aggregator would imply all three.
 *
 * It is not on the Sources page either. That page answers "where did each RATE
 * come from", one row per fund. An exchange rate is not a fund and has no
 * fund_id, so it would have to be special-cased into a table whose whole shape
 * is per-fund.
 *
 * What it needs instead is exactly this: is the key alive, how much quota is
 * left, and how deep is the history. All three come from tables, so this reads
 * no secrets and calls no external API.
 *
 * WHY THE QUOTA MATTERS MORE THAN IT LOOKS. Open Exchange Rates caps the free
 * plan at 1,000 requests a month. Past that it stops answering, the last rate
 * stays in fx_rates, and the currency card keeps rendering a stale number that
 * is pixel identical to a fresh one. Nothing breaks, nothing errors, and the
 * app quietly lies. The readout below is the only warning that comes before it.
 */

const FX_SOURCES = ["openexchangerates", "open-er-api"];
const PAIR = "USD/KES";

type Health = {
  source: string;
  consecutive_failures: number;
  blocked_until: string | null;
  last_ok_at: string | null;
  last_error: string | null;
  note: string | null;
  updated_at: string;
};

function ago(iso: string | null): string {
  if (!iso) return "never";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return `${Math.round(s)}s ago`;
  if (s < 5400) return `${Math.round(s / 60)}m ago`;
  if (s < 172800) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

/** "2026-07-24" to "Jul 2026". Unparseable passes through. */
function month(iso: string | null): string {
  if (!iso) return "none";
  const m = iso.match(/^(\d{4})-(\d{2})/);
  if (!m) return iso;
  const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const i = Number(m[2]) - 1;
  return i >= 0 && i < 12 ? `${names[i]} ${m[1]}` : iso;
}

/** Pull the used/quota pair back out of the note for a progress bar. */
function quotaPct(note: string | null): number | null {
  if (!note) return null;
  const m = note.match(/^(\d+)\s*\/\s*(\d+)/);
  if (!m) return null;
  const used = Number(m[1]);
  const quota = Number(m[2]);
  if (!quota) return null;
  return Math.min(100, Math.round((used / quota) * 100));
}

export async function FxHealth() {
  const db = supabaseAdmin();

  const [healthRes, latestRes, oldestRes, countRes] = await Promise.all([
    db
      .from("source_health")
      .select("source,consecutive_failures,blocked_until,last_ok_at,last_error,note,updated_at")
      .in("source", FX_SOURCES),
    db
      .from("fx_rates")
      .select("rate,as_of,source")
      .eq("pair", PAIR)
      .order("as_of", { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from("fx_rates")
      .select("as_of")
      .eq("pair", PAIR)
      .order("as_of", { ascending: true })
      .limit(1)
      .maybeSingle(),
    db
      .from("fx_rates")
      .select("as_of", { count: "exact", head: true })
      .eq("pair", PAIR),
  ]);

  const health = (healthRes.data ?? []) as Health[];
  const primary = health.find((h) => h.source === "openexchangerates") ?? null;
  const latest = latestRes.data as { rate: number; as_of: string; source: string | null } | null;
  const oldest = oldestRes.data as { as_of: string } | null;
  const rows = countRes.count ?? 0;

  const pct = quotaPct(primary?.note ?? null);
  const failing = health.some((h) => h.consecutive_failures > 0);

  // fx_series needs 13 month-end points before the currency card will describe
  // a regime. Below that the whole section is hidden in the app, and saying so
  // here is the difference between "not built yet" and "not fed yet".
  const monthsCovered = new Set<string>();
  if (oldest && latest) {
    // Cheap approximation from the span rather than a second query: enough to
    // tell 2 months from 60, which is the only distinction that matters.
    const a = new Date(oldest.as_of);
    const b = new Date(latest.as_of);
    const span = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 +
      (b.getUTCMonth() - a.getUTCMonth()) + 1;
    for (let i = 0; i < Math.max(0, span); i++) monthsCovered.add(String(i));
  }
  const months = monthsCovered.size;
  const enough = months >= 13;

  return (
    <div className="mb-6 overflow-hidden rounded-xl border border-line bg-panel">
      <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
        <span className="text-[11px] uppercase tracking-wider text-faint">
          Exchange rate
        </span>
        <span className="text-[11px] text-faint">
          Runs inside the MMF aggregator
        </span>
      </div>

      <div className="grid gap-px bg-line/60 sm:grid-cols-3">
        <div className="bg-panel px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-faint">
            {PAIR}
          </div>
          <div className="mt-1 text-lg font-semibold tnum">
            {latest ? latest.rate.toFixed(4) : "none"}
          </div>
          <div className="mt-0.5 text-[11px] text-mute">
            {latest ? `${latest.as_of} via ${latest.source ?? "unknown"}` : "no row in fx_rates"}
          </div>
        </div>

        <div className="bg-panel px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-faint">
            History
          </div>
          <div className={"mt-1 text-lg font-semibold tnum " + (enough ? "" : "text-warn")}>
            {rows} {rows === 1 ? "row" : "rows"}
          </div>
          <div className="mt-0.5 text-[11px] text-mute">
            {oldest ? `${month(oldest.as_of)} onward, about ${months} months` : "empty"}
          </div>
        </div>

        <div className="bg-panel px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-faint">
            Quota
          </div>
          <div className="mt-1 text-lg font-semibold tnum">
            {primary?.note ? primary.note.replace(/\s*requests this month$/, "") : "unknown"}
          </div>
          {pct != null && (
            <div className="mt-2 h-1 overflow-hidden rounded-full bg-line">
              <div
                className={"h-full rounded-full " + (pct >= 85 ? "bg-bad" : pct >= 60 ? "bg-warn" : "bg-live")}
                style={{ width: `${pct}%` }}
              />
            </div>
          )}
          <div className="mt-1 text-[11px] text-mute">
            {primary?.last_ok_at ? `Last good ${ago(primary.last_ok_at)}` : "Never succeeded"}
          </div>
        </div>
      </div>

      {/* The two states worth interrupting for. Both are silent failures: the
          app keeps rendering either way, so nothing else surfaces them. */}
      {!enough && (
        <div className="border-t border-line px-4 py-2.5 text-[11px] leading-relaxed text-warn">
          The currency card needs 13 month-end points before it will show. It is
          hidden in the app right now. Run backfill-fx-oxr.ts, or load the CBK
          CSV with backfill-fx.ts.
        </div>
      )}

      {failing && (
        <div className="border-t border-line px-4 py-2.5">
          {health
            .filter((h) => h.consecutive_failures > 0)
            .map((h) => (
              <div key={h.source} className="text-[11px] leading-relaxed text-bad">
                <code className="text-faint">{h.source}</code> has failed{" "}
                {h.consecutive_failures}{" "}
                {h.consecutive_failures === 1 ? "time" : "times"} in a row.{" "}
                {h.last_error}
              </div>
            ))}
        </div>
      )}
    </div>
  );
}
