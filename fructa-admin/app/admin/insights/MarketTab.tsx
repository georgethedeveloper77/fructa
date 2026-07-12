"use client";

export type MarketData = {
  snapshotFunds: number;
  mmfCount: number;
  top: { name: string; rate: number } | null;
  avg: number | null;
  netTop: number | null;
  spread: number | null;
  topDelta: number | null;
  avgDelta: number | null;
  distribution: { label: string; count: number }[];
  leaders: { name: string; rate: number }[];
  byClass: { label: string; avg: number; count: number }[];
  trend: { date: string; avg: number; top: number }[];
  benchmarks:
    | null
    | { inflation: number | null; cbr: number | null; tbill91: number | null; tbill182: number | null; tbill364: number | null; wht: number | null };
};

const f2 = (n: number) => n.toFixed(2);

function Delta({ v }: { v: number | null }) {
  if (v == null || Math.abs(v) < 0.005) return null;
  const up = v > 0;
  return (
    <span className={"inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 font-mono text-[11px] font-semibold " +
      (up ? "bg-live/10 text-live" : "bg-bad/10 text-bad")}>
      <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
        {up ? <path d="m6 15 6-6 6 6" /> : <path d="m6 9 6 6 6-6" />}
      </svg>
      {Math.abs(v).toFixed(2)}
    </span>
  );
}

function Kpi({ label, value, unit, children }: { label: string; value: string; unit?: string; children?: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-line bg-panel px-4 py-4">
      <div className="text-[12px] text-mute">{label}</div>
      <div className="mt-2 flex items-baseline gap-1 font-mono text-[27px] font-semibold tracking-tight text-ink">
        {value}{unit && <span className="text-[13px] font-medium text-faint">{unit}</span>}
      </div>
      <div className="mt-2 flex items-center gap-2 text-[11.5px] text-faint">{children}</div>
    </div>
  );
}

function Panel({ title, sub, legend, children }: { title: string; sub?: string; legend?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="overflow-hidden rounded-xl border border-line bg-panel">
      <div className="flex items-center gap-2 border-b border-line px-4 py-3">
        <h3 className="text-sm font-semibold">{title}</h3>
        {sub && <span className="font-mono text-[11px] text-faint">{sub}</span>}
        {legend && <div className="ml-auto flex gap-3 font-mono text-[11px] text-muted">{legend}</div>}
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

// ── trend line chart ─────────────────────────────────────────────────────────
function TrendChart({ trend }: { trend: MarketData["trend"] }) {
  if (trend.length < 2) {
    return <div className="flex h-[190px] items-center justify-center text-xs text-faint">Not enough rate history yet to plot a trend.</div>;
  }
  const W = 560, H = 170, PAD_T = 12, PAD_B = 24;
  const ys = trend.flatMap((p) => [p.avg, p.top]);
  let lo = Math.min(...ys), hi = Math.max(...ys);
  const pad = Math.max(0.4, (hi - lo) * 0.15);
  lo -= pad; hi += pad;
  const x = (i: number) => (i / (trend.length - 1)) * W;
  const y = (v: number) => PAD_T + (1 - (v - lo) / (hi - lo)) * (H - PAD_T - PAD_B);
  const line = (key: "avg" | "top") => trend.map((p, i) => `${x(i).toFixed(1)},${y(p[key]).toFixed(1)}`).join(" ");
  const first = trend[0].date, last = trend[trend.length - 1].date;
  const mid = trend[Math.floor(trend.length / 2)].date;
  const short = (d: string) => new Date(d + "T00:00:00Z").toLocaleDateString("en-GB", { month: "short" });

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-[190px] w-full" preserveAspectRatio="none">
      {[0, 0.5, 1].map((t) => {
        const gy = PAD_T + t * (H - PAD_T - PAD_B);
        return <line key={t} x1="0" y1={gy} x2={W} y2={gy} stroke="var(--line)" strokeWidth="1" />;
      })}
      <text x="2" y={PAD_T + 8} fill="var(--faint)" fontFamily="var(--mono)" fontSize="9">{f2(hi)}%</text>
      <text x="2" y={H - PAD_B} fill="var(--faint)" fontFamily="var(--mono)" fontSize="9">{f2(lo)}%</text>
      <polyline fill="none" stroke="var(--gold)" strokeWidth="2.5" points={line("top")} />
      <polyline fill="none" stroke="var(--blue)" strokeWidth="2.5" points={line("avg")} />
      <text x="0" y={H - 6} fill="var(--faint)" fontFamily="var(--mono)" fontSize="9">{short(first)}</text>
      <text x={W / 2 - 10} y={H - 6} fill="var(--faint)" fontFamily="var(--mono)" fontSize="9">{short(mid)}</text>
      <text x={W - 26} y={H - 6} fill="var(--faint)" fontFamily="var(--mono)" fontSize="9">{short(last)}</text>
    </svg>
  );
}

// ── vertical distribution bars ───────────────────────────────────────────────
function Distribution({ data }: { data: MarketData["distribution"] }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  return (
    <div className="flex h-[170px] items-end gap-3 px-1 pt-2">
      {data.map((d) => (
        <div key={d.label} className="flex h-full flex-1 flex-col items-center justify-end gap-2">
          <span className="font-mono text-[13px] font-semibold text-ink">{d.count}</span>
          <div className="w-full rounded-t-md bg-gold" style={{ height: `${Math.max(2, (d.count / max) * 100)}%` }} />
          <span className="font-mono text-[10.5px] text-faint">{d.label}</span>
        </div>
      ))}
    </div>
  );
}

// ── horizontal bars ──────────────────────────────────────────────────────────
function HBars({ rows, accent }: { rows: { name: string; value: number }[]; accent: "gold" | "blue" }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  const bar = accent === "blue" ? "bg-blue" : "bg-gold";
  const val = accent === "blue" ? "text-blue" : "text-gold";
  return (
    <div className="flex flex-col gap-2.5">
      {rows.map((r) => (
        <div key={r.name} className="flex items-center gap-3">
          <span className="w-[128px] shrink-0 text-[12.5px] text-ink">{r.name}</span>
          <div className="h-4 flex-1 overflow-hidden rounded bg-raise2">
            <div className={"h-full rounded " + bar} style={{ width: `${Math.max(3, (r.value / max) * 100)}%` }} />
          </div>
          <span className={"w-[52px] shrink-0 text-right font-mono text-[12.5px] font-semibold " + val}>{f2(r.value)}</span>
        </div>
      ))}
    </div>
  );
}

// ── benchmark strip ──────────────────────────────────────────────────────────
function Benchmarks({ b }: { b: MarketData["benchmarks"] }) {
  if (!b) {
    return (
      <div className="rounded-xl border border-dashed border-line2 bg-panel px-4 py-4 text-center text-xs text-faint">
        Benchmarks strip (inflation, CBR, T-bill tenors, WHT) lights up once the benchmarks table is wired.
      </div>
    );
  }
  const cells: [string, number | null, string][] = [
    ["Inflation", b.inflation, "%"],
    ["CBR", b.cbr, "%"],
    ["T-bill 91d", b.tbill91, "%"],
    ["T-bill 182d", b.tbill182, "%"],
    ["T-bill 364d", b.tbill364, "%"],
    ["WHT", b.wht, "%"],
  ];
  return (
    <div className="grid grid-cols-3 overflow-hidden rounded-xl border border-line bg-panel sm:grid-cols-6">
      {cells.map(([k, v, u], i) => (
        <div key={k} className={"px-4 py-3.5 " + (i < cells.length - 1 ? "border-r border-line" : "")}>
          <div className="text-[10.5px] uppercase tracking-wider text-faint">{k}</div>
          <div className="mt-1 font-mono text-[19px] font-semibold text-ink">{v != null ? `${v}${u}` : "-"}</div>
        </div>
      ))}
    </div>
  );
}

export function MarketTab({ data }: { data: MarketData }) {
  const { top, avg, netTop, spread } = data;

  return (
    <div className="space-y-3.5">
      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Top MMF · KES" value={top ? f2(top.rate) : "-"} unit="%">
          <Delta v={data.topDelta} /> <span>{top ? top.name : "no data"}</span>
        </Kpi>
        <Kpi label="Average MMF · KES" value={avg != null ? f2(avg) : "-"} unit="%">
          <Delta v={data.avgDelta} /> <span>across {data.mmfCount} funds</span>
        </Kpi>
        <Kpi label="Top net of 15% WHT" value={netTop != null ? f2(netTop) : "-"} unit="%">
          <span className="rounded bg-gold/10 px-1.5 py-0.5 font-mono text-[11px] font-semibold text-gold">net</span>
          <span>{top ? `from ${f2(top.rate)} gross` : ""}</span>
        </Kpi>
        <Kpi label="MMF rate spread" value={spread != null ? f2(spread) : "-"} unit="pp">
          <span>top minus lowest live</span>
        </Kpi>
      </div>

      {/* trend + distribution */}
      <div className="grid gap-3.5 lg:grid-cols-[1.55fr_1fr]">
        <Panel
          title="MMF rate trend"
          sub="180 days"
          legend={<>
            <span><i className="mr-1.5 inline-block h-[3px] w-2.5 rounded bg-gold align-middle" />top fund</span>
            <span><i className="mr-1.5 inline-block h-[3px] w-2.5 rounded bg-blue align-middle" />market avg</span>
          </>}
        >
          <TrendChart trend={data.trend} />
        </Panel>
        <Panel title="Rate distribution" sub="funds per band">
          <Distribution data={data.distribution} />
        </Panel>
      </div>

      {/* leaders + by class */}
      <div className="grid gap-3.5 lg:grid-cols-2">
        <Panel title="Top MMF funds" sub="current rate · KES">
          {data.leaders.length ? (
            <HBars rows={data.leaders.map((l) => ({ name: l.name, value: l.rate }))} accent="gold" />
          ) : (
            <p className="py-6 text-center text-xs text-faint">No live MMF rates yet.</p>
          )}
        </Panel>
        <Panel title="Yield by asset class" sub="average · annualised">
          {data.byClass.length ? (
            <HBars rows={data.byClass.map((c) => ({ name: `${c.label} (${c.count})`, value: c.avg }))} accent="blue" />
          ) : (
            <p className="py-6 text-center text-xs text-faint">No rated funds yet.</p>
          )}
        </Panel>
      </div>

      {/* benchmarks */}
      <Benchmarks b={data.benchmarks} />
    </div>
  );
}
