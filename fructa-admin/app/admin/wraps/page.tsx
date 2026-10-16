import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase/server";
import {
  deleteWrap,
  rebuildWrap,
  runWrapsNow,
  saveStoryThresholds,
  setWrapStatus,
} from "./actions";

export const dynamic = "force-dynamic";

// Wraps publish themselves: build-wraps runs hourly, puts a day live when
// something moved, publishes the week on Friday evening with its push, and
// closes months, quarters and years. This page is for stepping in.

type Row = {
  id: string;
  period: string;
  period_start: string;
  period_end: string;
  status: "draft" | "live" | "held";
  lead: string | null;
  edited: boolean;
  stories: unknown[];
  built_at: string | null;
  published_at: string | null;
  pushed_at: string | null;
};

const STATUS_TICK: Record<Row["status"], string> = { live: "tick ok", draft: "tick warn", held: "tick bad" };

const THRESHOLDS: { key: string; label: string; step: string; dflt: number }[] = [
  { key: "story.daily_ratio", label: "Daily: move against the fund's normal week (times)", step: "0.1", dflt: 3 },
  { key: "story.daily_min_move", label: "Daily: smallest move (pts)", step: "0.01", dflt: 0.25 },
  { key: "story.daily_max", label: "Daily: most stories", step: "1", dflt: 3 },
  { key: "story.weekly_max", label: "Week and longer: most stories", step: "1", dflt: 8 },
  { key: "story.repeat_weeks", label: "Weeks before the same story repeats", step: "1", dflt: 3 },
  { key: "story.breadth_min", label: "Funds moving together for a market story", step: "1", dflt: 8 },
  { key: "story.weekly_publish_dow", label: "Weekly publish day (0 Sun to 6 Sat)", step: "1", dflt: 5 },
  { key: "story.weekly_publish_hour", label: "Weekly publish hour, Nairobi", step: "1", dflt: 18 },
];

function when(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleString("en-GB", { timeZone: "Africa/Nairobi", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

function label(r: Row): string {
  const fmt = (s: string) => new Date(s + "T00:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });
  switch (r.period) {
    case "day": return fmt(r.period_end);
    case "week": return `${fmt(r.period_start)} to ${fmt(r.period_end)}`;
    case "month": return new Date(r.period_end + "T00:00:00Z").toLocaleDateString("en-GB", { month: "long", year: "numeric", timeZone: "UTC" });
    case "quarter": return r.id.replace(/^quarter-(\d{4})-q(\d)$/, "Q$2 $1");
    default: return r.period_end.slice(0, 4);
  }
}

export default async function WrapsPage() {
  const db = supabaseAdmin();
  const [{ data }, { data: cfgRows }, { count: held }] = await Promise.all([
    db.from("wraps")
      .select("id,period,period_start,period_end,status,lead,edited,stories,built_at,published_at,pushed_at")
      .order("period_end", { ascending: false })
      .order("period", { ascending: true })
      .limit(80),
    db.from("app_config").select("key,value").like("key", "story.%"),
    db.from("rate_review").select("id", { count: "exact", head: true }).eq("status", "pending"),
  ]);
  const rows = (data ?? []) as Row[];
  const cfg = new Map((cfgRows ?? []).map((r) => [r.key as string, r.value as unknown]));
  const on = (k: string, d: boolean) => (cfg.has(k) ? cfg.get(k) === true : d);

  return (
    <>
      <div className="toolrow">
        <span style={{ fontSize: 12.5, color: "var(--mute)" }}>
          Publishes on its own, from approved rates only. Step in here when you need to.
        </span>
        <div className="spacer" />
        <form action={runWrapsNow}>
          <button className="btn xs">Run now</button>
        </form>
      </div>

      {(held ?? 0) > 0 && (
        <div className="panelc" style={{ padding: "10px 14px", marginBottom: 14, borderColor: "var(--gold)", color: "var(--gold)", fontSize: 13 }}>
          {held} rate {held === 1 ? "change is" : "changes are"} held in{" "}
          <Link href="/admin/review" style={{ textDecoration: "underline" }}>Review</Link>.
          {" "}They stay out of every story until approved.
        </div>
      )}

      <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1.6fr) minmax(0, 1fr)", gap: 16, alignItems: "start" }}>
        <div className="panelc">
          <table className="tbl">
            <thead>
              <tr>
                <th>Period</th>
                <th>Lead story</th>
                <th>Status</th>
                <th className="r" />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>
                    <div className="fn">{label(r)}</div>
                    <div className="fm">{r.period} · {r.stories.length} {r.stories.length === 1 ? "story" : "stories"}</div>
                  </td>
                  <td>
                    <div>{r.lead ?? <span className="text-faint">No stories</span>}</div>
                    <div className="fm">
                      {r.published_at ? `published ${when(r.published_at)}` : `built ${when(r.built_at)}`}
                      {r.pushed_at ? ` · pushed ${when(r.pushed_at)}` : ""}
                      {r.edited ? " · edited" : ""}
                    </div>
                  </td>
                  <td><span className={STATUS_TICK[r.status]}>{r.status}</span></td>
                  <td className="r">
                    <div style={{ display: "flex", gap: 6, justifyContent: "flex-end", flexWrap: "wrap" }}>
                      <Link className="btn xs" href={`/admin/wraps/${r.id}`}>Edit</Link>
                      <form action={rebuildWrap}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs">Rebuild</button>
                      </form>
                      <form action={setWrapStatus}>
                        <input type="hidden" name="id" value={r.id} />
                        <input type="hidden" name="status" value={r.status === "held" ? "live" : "held"} />
                        <button className="btn xs">{r.status === "held" ? "Release" : "Hold"}</button>
                      </form>
                      <form action={deleteWrap}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs" style={{ color: "var(--bad)" }}>Delete</button>
                      </form>
                    </div>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr>
                  <td colSpan={4}>
                    <div className="ph-empty" style={{ border: "none", padding: "28px 0" }}>
                      No wraps yet. The first builds within the hour, or press Run now.
                    </div>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <form action={saveStoryThresholds} className="panelc" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ fontSize: 11, fontWeight: 800, letterSpacing: "0.08em", color: "var(--faint)" }}>WHAT COUNTS AS A STORY</div>
          {THRESHOLDS.map((t) => (
            <label key={t.key} className="field">
              <span>{t.label}</span>
              <input
                className="input num-input"
                type="number"
                name={t.key}
                step={t.step}
                defaultValue={Number(cfg.get(t.key) ?? t.dflt)}
              />
            </label>
          ))}
          <label className="flex items-center gap-2" style={{ fontSize: 13 }}>
            <input type="hidden" name="story.enabled:present" value="1" />
            <input type="checkbox" name="story.enabled" defaultChecked={on("story.enabled", true)} className="accent-gold" />
            Build and publish automatically
          </label>
          <label className="flex items-center gap-2" style={{ fontSize: 13 }}>
            <input type="hidden" name="story.weekly_push:present" value="1" />
            <input type="checkbox" name="story.weekly_push" defaultChecked={on("story.weekly_push", true)} className="accent-gold" />
            Send the weekly push when the week publishes
          </label>
          <button className="btn xs" style={{ alignSelf: "flex-start", background: "var(--gold-soft)", borderColor: "var(--gold)", color: "var(--gold)" }}>
            Save thresholds
          </button>
          <span className="text-xs text-faint">Saved as story.* keys in Config. The next run uses them.</span>
        </form>
      </div>
    </>
  );
}
