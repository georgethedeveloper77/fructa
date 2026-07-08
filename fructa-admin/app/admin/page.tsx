import { supabaseAdmin } from "@/lib/supabase/server";
import { IconExternal, IconArrowRight } from "./_icons";

export const dynamic = "force-dynamic"; // admin data is always live, never cached

type Fund = { id: string; name: string; category: string; currency: string; current_rate: number | null; status: string };
type Run = { source: string; started_at: string; finished_at: string | null; written: number; rejected: number; ok: boolean; unmapped: string[]; errors: string[] };

const CAT: Record<string, string> = {
  mmf_kes: "MMF · KES", mmf_usd: "MMF · USD", tbill: "T-Bills",
  bond: "Bonds", sacco: "SACCO", stock: "NSE Stocks",
};

function ago(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}
function clock(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
function dayKey(d: Date): string { return d.toISOString().slice(0, 10); }

export default async function Dashboard() {
  const db = supabaseAdmin();
  let funds: Fund[] = [];
  let runs: Run[] = [];
  let error: string | null = null;

  try {
    const [f, r] = await Promise.all([
      db.from("funds").select("id,name,category,currency,current_rate,status"),
      db.from("scraper_runs")
        .select("source,started_at,finished_at,written,rejected,ok,unmapped,errors")
        .order("started_at", { ascending: false }).limit(200),
    ]);
    if (f.error) throw f.error;
    if (r.error) throw r.error;
    funds = (f.data ?? []) as Fund[];
    runs = (r.data ?? []) as Run[];
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  // ── derive ────────────────────────────────────────────────────────────
  const total = funds.length;
  const live = funds.filter((x) => x.status === "live").length;
  const stale = funds.filter((x) => x.status === "stale");
  const hidden = funds.filter((x) => x.status === "hidden").length;

  const lastBySource = new Map<string, Run>();
  for (const r of runs) if (!lastBySource.has(r.source)) lastBySource.set(r.source, r);
  const sources = [...lastBySource.keys()];

  const unmapped = [...new Set(runs.flatMap((s) => s.unmapped ?? []))];

  // MMF KES average (live rates)
  const mmf = funds.filter((x) => x.category === "mmf_kes" && x.current_rate != null);
  const mmfAvg = mmf.length ? mmf.reduce((a, b) => a + (b.current_rate ?? 0), 0) / mmf.length : null;

  // scrape success over last 14 days
  const now = Date.now();
  const within14 = runs.filter((r) => now - new Date(r.started_at).getTime() < 14 * 864e5);
  const runOk = within14.filter((r) => r.ok).length;
  const successPct = within14.length ? Math.round((runOk / within14.length) * 100) : null;

  // 14-day heatmap: per source × day → ok | bad | skip
  const days: Date[] = [];
  for (let i = 13; i >= 0; i--) { const d = new Date(now - i * 864e5); d.setHours(0, 0, 0, 0); days.push(d); }
  const grid: Record<string, Record<string, "ok" | "bad" | "skip">> = {};
  for (const src of sources) {
    grid[src] = {};
    for (const d of days) grid[src][dayKey(d)] = "skip";
  }
  for (const r of within14) {
    const k = dayKey(new Date(r.started_at));
    if (grid[r.source] && grid[r.source][k] !== undefined) {
      if (!r.ok) grid[r.source][k] = "bad";
      else if (grid[r.source][k] !== "bad") grid[r.source][k] = "ok";
    }
  }

  // funds by category with average live rate
  const byCat = Object.keys(CAT).map((key) => {
    const rows = funds.filter((x) => x.category === key);
    const rated = rows.map((x) => x.current_rate).filter((v): v is number => v != null);
    const avg = rated.length ? rated.reduce((a, b) => a + b, 0) / rated.length : null;
    return { key, label: CAT[key], count: rows.length, avg };
  }).filter((c) => c.count > 0);

  // attention items
  type Att = { tone: string; t: string; d: string };
  const attention: Att[] = [];
  for (const s of [...lastBySource.values()].filter((r) => !r.ok)) {
    attention.push({ tone: "var(--bad)", t: `Scrape failed · ${s.source}`, d: (s.errors?.[0] ?? "unknown error") });
  }
  if (stale.length) {
    attention.push({ tone: "var(--warn)", t: `${stale.length} stale ${stale.length === 1 ? "fund" : "funds"}`, d: stale.slice(0, 4).map((x) => x.name).join(" · ") + (stale.length > 4 ? " …" : "") });
  }
  if (unmapped.length) {
    attention.push({ tone: "var(--warn)", t: `${unmapped.length} unmapped names`, d: unmapped.slice(0, 4).join(" · ") + (unmapped.length > 4 ? " …" : "") });
  }

  const recent = runs.slice(0, 8);
  const snapshotUrl = `${process.env.SUPABASE_URL ?? ""}/storage/v1/object/public/snapshots/funds-snapshot.json`;

  // ── render ────────────────────────────────────────────────────────────
  return (
    <>
      {error && (
        <div className="panelc" style={{ borderColor: "var(--bad)", marginBottom: 16 }}>
          <div className="pb">
            <p style={{ color: "var(--bad)", fontWeight: 600 }}>Can&apos;t reach the database.</p>
            <p style={{ color: "var(--muted)", marginTop: 4 }}>
              Set <code>SUPABASE_URL</code> and <code>SUPABASE_SERVICE_ROLE_KEY</code> in{" "}
              <code>fructa-admin/.env.local</code>, then reload.
            </p>
            <p className="num" style={{ color: "var(--faint)", marginTop: 8, fontSize: 11 }}>{error}</p>
          </div>
        </div>
      )}

      {/* stat strip */}
      <div className="statstrip">
        <div className="stt">
          <div className="k">Funds live</div>
          <div className="v">{live}<small>/ {total}</small></div>
          <div className="s">
            {stale.length ? <span className="tick warn">{stale.length} stale</span> : <span className="tick ok">all fresh</span>}
            {hidden ? ` · ${hidden} hidden` : ""}
          </div>
        </div>
        <div className="stt">
          <div className="k">MMF avg · KES</div>
          <div className="v">{mmfAvg != null ? mmfAvg.toFixed(2) : "—"}<small>%</small></div>
          <div className="s">across {mmf.length} live {mmf.length === 1 ? "fund" : "funds"}</div>
        </div>
        <div className="stt">
          <div className="k">Scrape success · 14d</div>
          <div className="v">{successPct != null ? successPct : "—"}<small>%</small></div>
          <div className="s">{within14.length} runs · {within14.length - runOk} fail</div>
        </div>
        <div className="stt">
          <div className="k">Snapshot on CDN</div>
          <div className="v" style={{ fontSize: 17, marginTop: 11 }}>funds-snapshot.json</div>
          <div className="s">
            <a className="tick mut" href={snapshotUrl} target="_blank" rel="noreferrer" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              open <IconExternal size={11} />
            </a>
          </div>
        </div>
      </div>

      <div className="g2">
        {/* scraper health */}
        <div className="panelc">
          <div className="ph">
            <h3>Scraper health</h3>
            <span className="sub">14 days · per source</span>
            <a className="act" href="/admin/scrapers" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              run log <IconArrowRight size={11} />
            </a>
          </div>
          {sources.length === 0 ? (
            <div className="pb"><div className="ph-empty">No scraper has run yet. Trigger the CBK workflow or the aggregator; runs land here.</div></div>
          ) : (
            <>
              <div className="pb">
                <div className="heat">
                  {sources.map((src) => (
                    <div key={src} style={{ display: "contents" }}>
                      <div className="hl" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{src}</div>
                      {days.map((d) => (
                        <div key={dayKey(d)} className={`hcell ${grid[src][dayKey(d)]}`} title={`${src} · ${dayKey(d)}`} />
                      ))}
                    </div>
                  ))}
                </div>
                <div className="heatx">
                  <span />
                  {days.map((d) => <span key={dayKey(d)}>{d.getDate()}</span>)}
                </div>
              </div>
              <div className="term">
                {recent.map((r, i) => (
                  <div className="ln" key={i}>
                    <span className="ts">{clock(r.started_at)}</span>
                    <span className="src">{r.source}</span>
                    <span className={r.ok ? (r.rejected ? "warn" : "ok") : "bad"}>{r.ok ? "ok" : "fail"}</span>
                    <span className="msg">
                      {r.written} written{r.rejected ? `, ${r.rejected} rejected` : ""}
                      {r.errors?.length ? ` — ${r.errors[0]}` : ""}
                    </span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        {/* needs attention */}
        <div className="panelc">
          <div className="ph"><h3>Needs attention</h3><span className="sub">{attention.length || "0"}</span></div>
          {attention.length === 0 ? (
            <div className="pb"><div className="ph-empty">All clear — nothing stale, unmapped, or failing.</div></div>
          ) : (
            <div>
              {attention.map((a, i) => (
                <div className="att" key={i}>
                  <span className="dot" style={{ background: a.tone }} />
                  <div style={{ minWidth: 0 }}>
                    <div className="t">{a.t}</div>
                    <div className="d">{a.d}</div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* by category */}
      <div className="panelc" style={{ marginTop: 14 }}>
        <div className="ph"><h3>By category</h3><span className="sub">live rate average</span></div>
        {byCat.length === 0 ? (
          <div className="pb"><div className="ph-empty">No funds yet. Seed the funds table to populate the directory.</div></div>
        ) : (
          <table className="tbl">
            <thead><tr><th>Category</th><th className="r">Funds</th><th className="r">Avg rate</th></tr></thead>
            <tbody>
              {byCat.map((c) => (
                <tr key={c.key}>
                  <td>{c.label}</td>
                  <td className="r num">{c.count}</td>
                  <td className="r num" style={{ color: c.avg != null ? "var(--gold)" : "var(--faint)" }}>
                    {c.avg != null ? `${c.avg.toFixed(2)}%` : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* snapshot */}
      <div className="panelc" style={{ marginTop: 14 }}>
        <div className="ph">
          <h3>App snapshot</h3>
          <span className="sub">the static file the app reads · refreshed after every scrape</span>
          <a className="act" href={snapshotUrl} target="_blank" rel="noreferrer" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
            open snapshot <IconExternal size={11} />
          </a>
        </div>
      </div>
    </>
  );
}
