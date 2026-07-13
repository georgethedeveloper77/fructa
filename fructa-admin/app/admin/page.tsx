import { supabaseAdmin } from "@/lib/supabase/server";
import { IconExternal, IconArrowRight } from "./_icons";

export const dynamic = "force-dynamic"; // admin data is always live, never cached

type Fund = { id: string; name: string; category: string; currency: string; current_rate: number | null; status: string };
type Run = { source: string; started_at: string; finished_at: string | null; written: number; rejected: number; ok: boolean; unmapped: string[]; errors: string[] };
type Sacco = { id: string; display_name: string | null; name: string; common_bond: string; active: boolean };
type SaccoRate = { sacco_id: string; financial_year: number; interest_on_deposits: number | null };

// Fund categories ONLY. `sacco` and `stock` used to be listed here and were
// dead the whole time: SACCOs live in `saccos` and stocks in `stocks`, so no row
// in `funds` has ever carried either value. The byCat filter drops empty rows,
// so the two entries rendered as nothing and looked wired. They are counted from
// their own tables below instead, where the numbers are real.
const CAT: Record<string, string> = {
  mmf_kes: "MMF · KES", mmf_usd: "MMF · USD", tbill: "T-Bills",
  bond: "Bonds",
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
  let saccos: Sacco[] = [];
  let saccoRates: SaccoRate[] = [];
  let error: string | null = null;

  try {
    const [f, r, s, sr] = await Promise.all([
      db.from("funds").select("id,name,category,currency,current_rate,status"),
      db.from("scraper_runs")
        .select("source,started_at,finished_at,written,rejected,ok,unmapped,errors")
        .order("started_at", { ascending: false }).limit(200),
      // Deposit-taking only. Credit-only societies are seeded so the register is
      // complete and are barred from taking new deposits, so they have no place
      // in a savings-rate count.
      db.from("saccos").select("id,display_name,name,common_bond,active").eq("licence_class", "dt"),
      db.from("sacco_rates").select("sacco_id,financial_year,interest_on_deposits"),
    ]);
    if (f.error) throw f.error;
    if (r.error) throw r.error;
    funds = (f.data ?? []) as Fund[];
    runs = (r.data ?? []) as Run[];
    saccos = (s.data ?? []) as Sacco[];
    saccoRates = (sr.data ?? []) as SaccoRate[];
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

  // ── SACCOs ────────────────────────────────────────────────────────────
  // Latest declared deposit rate per society. The DEPOSIT rate, never the
  // dividend: the dividend is paid on a capped pot of share capital and is
  // nearly always the bigger percentage and the smaller cheque. Averaging it
  // here would put a number on the dashboard that answers no question anyone has.
  const latestDeposit = new Map<string, number>();
  const latestYear = new Map<string, number>();
  for (const r of saccoRates) {
    const seen = latestYear.get(r.sacco_id);
    if (seen != null && seen >= r.financial_year) continue;
    latestYear.set(r.sacco_id, r.financial_year);
    if (r.interest_on_deposits != null) {
      latestDeposit.set(r.sacco_id, Number(r.interest_on_deposits));
    } else {
      latestDeposit.delete(r.sacco_id);
    }
  }
  const saccoLive = saccos.filter((x) => x.active);
  const saccoRated = saccoLive.filter((x) => latestDeposit.has(x.id));
  const saccoAvg = saccoRated.length
    ? saccoRated.reduce((a, x) => a + (latestDeposit.get(x.id) ?? 0), 0) / saccoRated.length
    : null;
  // The only SACCOs a user can actually see: a rate to rank on AND a bond they
  // can join. Everything else is a directory entry.
  const saccoJoinable = saccoRated.filter((x) => x.common_bond === "open");
  const saccoUnknownBond = saccoRated.filter((x) => x.common_bond === "unknown");

  // attention items
  type Att = { tone: string; t: string; d: string };
  const attention: Att[] = [];

  // The failure that looks exactly like a working feature: rates imported, bond
  // never confirmed. The open-bond filter is on by default and treats unknown as
  // not joinable, so these societies carry a live rate and render to NOBODY. The
  // tab looks broken and the data looks fine.
  if (saccoUnknownBond.length) {
    attention.push({
      tone: "var(--warn)",
      t: `${saccoUnknownBond.length} rated ${saccoUnknownBond.length === 1 ? "SACCO is" : "SACCOs are"} hidden, bond not confirmed`,
      d: saccoUnknownBond.slice(0, 4).map((x) => x.display_name ?? x.name).join(" · ") + (saccoUnknownBond.length > 4 ? " …" : ""),
    });
  }
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

      {/* SACCOs. Their own panel rather than a row in "By category", because the
          number that matters here is not a rate average, it is how many societies
          are actually reachable by a user. */}
      {saccos.length > 0 && (
        <div className="panelc" style={{ marginTop: 14 }}>
          <div className="ph">
            <h3>SACCOs</h3>
            <span className="sub">AGM-declared rates · deposit interest, not the dividend</span>
            <a className="act" href="/admin/saccos" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              manage <IconArrowRight size={11} />
            </a>
          </div>
          <table className="tbl">
            <thead><tr><th>Societies</th><th className="r">Count</th><th className="r">Avg on deposits</th></tr></thead>
            <tbody>
              <tr>
                <td>Licensed, deposit taking</td>
                <td className="r num">{saccos.length}</td>
                <td className="r num" style={{ color: "var(--faint)" }}>{"\u2014"}</td>
              </tr>
              <tr>
                <td>With a declared rate</td>
                <td className="r num">{saccoRated.length}</td>
                <td className="r num" style={{ color: saccoAvg != null ? "var(--gold)" : "var(--faint)" }}>
                  {saccoAvg != null ? `${saccoAvg.toFixed(2)}%` : "\u2014"}
                </td>
              </tr>
              <tr>
                <td>Rated and joinable<small style={{ color: "var(--faint)", marginLeft: 6 }}>what a user actually sees</small></td>
                <td className="r num" style={{ color: saccoJoinable.length ? "var(--ok, var(--gold))" : "var(--warn)" }}>
                  {saccoJoinable.length}
                </td>
                <td className="r num" style={{ color: "var(--faint)" }}>{"\u2014"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      )}

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
