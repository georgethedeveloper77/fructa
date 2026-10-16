import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase/server";
import { rebuildWrap, saveWrapStories, setWrapStatus } from "../actions";

export const dynamic = "force-dynamic";

// One wrap's stories. The words a story card shows are editable and any story
// can be dropped; figures and charts stay as built. Saving marks the wrap
// edited, so the hourly run leaves it alone until "Rebuild from data".

type Story = {
  key: string;
  type: string;
  tag_key: string;
  fund_id: string | null;
  title: string;
  big: string;
  unit: string;
  line: string;
  tone: string;
  stats?: { ratio?: number | null; trend_weeks?: number | null };
};

const TONE: Record<string, string> = { up: "var(--ok)", down: "var(--bad)", tbill: "var(--gold)", accent: "var(--gold)", info: "var(--mute)" };

export default async function WrapDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data } = await supabaseAdmin()
    .from("wraps")
    .select("id,period,period_end,status,edited,stories,lead")
    .eq("id", id)
    .maybeSingle();
  if (!data) notFound();
  const stories = (data.stories ?? []) as Story[];

  return (
    <>
      <div className="toolrow">
        <Link className="btn xs" href="/admin/wraps">All wraps</Link>
        <span style={{ fontSize: 12.5, color: "var(--mute)", marginLeft: 8 }}>
          {data.id} · {data.status}{data.edited ? " · edited" : ""}
        </span>
        <div className="spacer" />
        <form action={setWrapStatus}>
          <input type="hidden" name="id" value={data.id} />
          <input type="hidden" name="status" value={data.status === "held" ? "live" : "held"} />
          <button className="btn xs">{data.status === "held" ? "Release" : "Hold"}</button>
        </form>
        <form action={rebuildWrap}>
          <input type="hidden" name="id" value={data.id} />
          <input type="hidden" name="force" value="1" />
          <button className="btn xs">Rebuild from data</button>
        </form>
      </div>

      <form action={saveWrapStories} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <input type="hidden" name="id" value={data.id} />
        {stories.map((s, i) => (
          <div key={s.key} className="panelc" style={{ padding: 14 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
              <span className="tnum text-xs text-faint">{i + 1}</span>
              <span style={{ fontSize: 11, fontWeight: 800, letterSpacing: "0.08em", color: TONE[s.tone] ?? "var(--mute)" }}>
                {s.type.replace(/_/g, " ").toUpperCase()}
              </span>
              {s.stats?.ratio != null && (
                <span className="text-xs text-faint">{s.stats.ratio.toFixed(1)}x normal week</span>
              )}
              <div className="spacer" style={{ flex: 1 }} />
              <label className="flex items-center gap-2" style={{ fontSize: 12.5, color: "var(--bad)" }}>
                <input type="checkbox" name={`drop:${s.key}`} value="1" className="accent-gold" />
                Drop this story
              </label>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <label className="field"><span>Title</span><input className="input" name={`title:${s.key}`} defaultValue={s.title} /></label>
              <label className="field"><span>Figure</span><input className="input" name={`big:${s.key}`} defaultValue={s.big} /></label>
              <label className="field"><span>Under the figure</span><input className="input" name={`unit:${s.key}`} defaultValue={s.unit} /></label>
              <label className="field"><span>Line</span><input className="input" name={`line:${s.key}`} defaultValue={s.line} /></label>
            </div>
          </div>
        ))}
        {stories.length === 0 && (
          <div className="ph-empty">This wrap has no stories.</div>
        )}
        {stories.length > 0 && (
          <button className="btn xs" style={{ alignSelf: "flex-start", background: "var(--gold-soft)", borderColor: "var(--gold)", color: "var(--gold)" }}>
            Save stories
          </button>
        )}
      </form>
    </>
  );
}
