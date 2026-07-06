import { supabaseAdmin } from "@/lib/supabase/server";
import { runAggregator, rebuildSnapshot } from "./actions";
import { IconExternal, IconChevronRight, IconClock } from "../_icons";

export const dynamic = "force-dynamic";

type Run = {
  id: number; source: string; trigger: string; started_at: string; finished_at: string | null;
  written: number; rejected: number; unmapped: string[]; errors: string[]; ok: boolean;
};

const REPO = process.env.GITHUB_REPO ?? "georgethedeveloper77/akiba";

// ── Schedule (mirror migrations/0022_reschedule_cron.sql) ───────────────────
// EAT = UTC+3. Aggregator fires 09:00 UTC = 12:00 EAT, weekdays.
const SCHEDULE_UTC_HOURS = [9];
const SCHEDULE_HUMAN = "Weekdays · 12:00 EAT";

const SCRAPERS = [
  { id: "ke-aggregator", label: "MMF aggregator", note: "Deno edge · " + SCHEDULE_HUMAN, kind: "edge" as const },
  { id: "ke-cbk-tbills", label: "CBK T-bills", note: "Playwright · weekly, Thursday", kind: "github" as const },
];

function ago(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

const EAT_MS = 3 * 3_600_000;
const isWeekday = (d: Date) => d.getUTCDay() >= 1 && d.getUTCDay() <= 5;

function eatTime(d: Date): string {
  const e = new Date(d.getTime() + EAT_MS);
  return `${String(e.getUTCHours()).padStart(2, "0")}:${String(e.getUTCMinutes()).padStart(2, "0")} EAT`;
}
function eatDay(d: Date, now: Date): string {
  const e = new Date(d.getTime() + EAT_MS);
  const n = new Date(now.getTime() + EAT_MS);
  const days = Math.round(
    (Date.UTC(e.getUTCFullYear(), e.getUTCMonth(), e.getUTCDate()) -
      Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate())) / 86_400_000,
  );
  if (days === 0) return "today";
  if (days === 1) return "tomorrow";
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][e.getUTCDay()];
}
function inWords(ms: number): string {
  const s = Math.max(0, ms / 1000);
  if (s < 3600) return `in ${Math.max(1, Math.round(s / 60))}m`;
  if (s < 86400) return `in ${Math.round(s / 3600)}h`;
  return `in ${Math.round(s / 86400)}d`;
}
function nextRun(now: Date): Date {
  for (let d = 0; d < 8; d++) {
    const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + d));
    if (!isWeekday(base)) continue;
    for (const h of SCHEDULE_UTC_HOURS) {
      const t = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate(), h));
      if (t.getTime() > now.getTime()) return t;
    }
  }
  return now;
}
function prevRun(now: Date): Date | null {
  for (let d = 0; d < 8; d++) {
    const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - d));
    if (!isWeekday(base)) continue;
    for (const h of [...SCHEDULE_UTC_HOURS].reverse()) {
      const t = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate(), h));
      if (t.getTime() <= now.getTime()) return t;
    }
  }
  return null;
}

type State = "ok" | "partial" | "failed";
function stateOf(r: Run): State {
  if (r.ok) return "ok";
  return r.written > 0 ? "partial" : "failed";
}
const DOT: Record<State, string> = { ok: "var(--live)", partial: "var(--warn)", failed: "var(--bad)" };
const TEXT: Record<State, string> = { ok: "text-live", partial: "text-warn", failed: "text-bad" };

function TriggerTag({ t }: { t: string }) {
  const manual = t === "manual";
  return (
    <span
      className={
        "rounded px-1.5 py-0.5 text-[10px] uppercase tracking-wide " +
        (manual ? "bg-panel2 text-mute" : "bg-live/10 text-live")
      }
    >
      {manual ? "manual" : "auto"}
    </span>
  );
}

function groupUnmapped(list: string[]): Record<string, string[]> {
  const g: Record<string, string[]> = {};
  for (const s of list ?? []) {
    const i = s.indexOf(":");
    const a = i > 0 ? s.slice(0, i) : "unknown";
    const l = i > 0 ? s.slice(i + 1) : s;
    (g[a] ??= []).push(l);
  }
  return g;
}

function RunDetail({ r }: { r: Run }) {
  const groups = groupUnmapped(r.unmapped);
  const hasUnmapped = (r.unmapped?.length ?? 0) > 0;
  const hasErrors = (r.errors?.length ?? 0) > 0;
  if (!hasUnmapped && !hasErrors) {
    return <p className="px-4 py-3 text-xs text-faint">Clean run — every row mapped, no errors.</p>;
  }
  return (
    <div className="space-y-3 px-4 py-3">
      {hasErrors && (
        <div>
          <div className="mb-1.5 text-[10px] uppercase tracking-wider text-faint">Errors</div>
          <ul className="space-y-1">
            {r.errors.map((e, i) => (
              <li key={i} className="rounded-md border border-bad/30 bg-bad/5 px-2.5 py-1.5 font-mono text-xs text-bad">{e}</li>
            ))}
          </ul>
        </div>
      )}
      {hasUnmapped && (
        <div>
          <div className="mb-1.5 text-[10px] uppercase tracking-wider text-faint">
            Unmapped · {r.unmapped.length} — source labels with no fund in the name map
          </div>
          <div className="space-y-1.5">
            {Object.entries(groups).map(([adapter, labels]) => (
              <div key={adapter} className="flex flex-wrap items-center gap-1.5">
                <span className="font-mono text-[11px] text-mute">{adapter}</span>
                {labels.map((l, i) => (
                  <span key={i} className="rounded-md border border-line bg-panel2 px-2 py-0.5 text-[11px] text-mute">{l}</span>
                ))}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default async function ScrapersPage() {
  const db = supabaseAdmin();
  const { data } = await db
    .from("scraper_runs")
    .select("id,source,trigger,started_at,finished_at,written,rejected,unmapped,errors,ok")
    .order("started_at", { ascending: false })
    .limit(50);
  const runs = (data ?? []) as Run[];

  const lastBySource = new Map<string, Run>();
  for (const r of runs) if (!lastBySource.has(r.source)) lastBySource.set(r.source, r);

  const agg = runs.filter((r) => r.source === "ke-aggregator");
  const last = agg[0];
  const lastAuto = agg.find((r) => r.trigger !== "manual"); // scheduled run
  const recent = agg.slice(0, 20);
  const successRate = recent.length ? Math.round((recent.filter((r) => r.ok).length / recent.length) * 100) : 0;
  const lastGood = agg.find((r) => r.written > 0);
  const chart = agg.slice(0, 16).reverse();
  const maxW = Math.max(1, ...chart.map((r) => r.written));

  // Schedule + health: did the last *scheduled* run actually land? A manual
  // re-run doesn't satisfy the schedule, so we check the last auto run only.
  const now = new Date();
  const next = nextRun(now);
  const prev = prevRun(now);
  const lastAutoAt = lastAuto ? new Date(lastAuto.started_at) : null;
  const missed =
    prev != null &&
    now.getTime() - prev.getTime() > 75 * 60_000 &&
    (lastAutoAt == null || lastAutoAt.getTime() < prev.getTime());

  const kpis: { label: string; value: string; sub?: string; tone?: State }[] = [
    { label: "Last run", value: last ? stateOf(last) : "—", sub: last ? ago(last.started_at) : undefined, tone: last ? stateOf(last) : undefined },
    { label: "Written", value: last ? String(last.written) : "—", sub: lastGood ? `good ${ago(lastGood.started_at)}` : undefined, tone: "ok" },
    { label: "Unmapped", value: last ? String(last.unmapped?.length ?? 0) : "—", tone: (last?.unmapped?.length ?? 0) > 0 ? "partial" : "ok" },
    { label: "Errors", value: last ? String(last.errors?.length ?? 0) : "—", tone: (last?.errors?.length ?? 0) > 0 ? "failed" : "ok" },
    { label: "Success rate", value: `${successRate}%`, sub: `last ${recent.length}`, tone: successRate >= 80 ? "ok" : successRate >= 40 ? "partial" : "failed" },
  ];

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-5 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Scrapers</h1>
          <p className="mt-1 text-sm text-mute">Automatic rate collection, with the exact rows that didn&apos;t map and why.</p>
        </div>
        <form action={rebuildSnapshot}>
          <button className="rounded-lg border border-line px-3 py-2 text-xs text-mute hover:border-gold/60 hover:text-gold">Rebuild snapshot</button>
        </form>
      </header>

      {/* Schedule + next run + health */}
      <div className="mb-4 rounded-xl border border-line bg-panel p-4">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          <div className="flex items-center gap-2.5">
            <span className="text-gold"><IconClock size={15} /></span>
            <div>
              <div className="text-[10px] uppercase tracking-wider text-faint">Schedule</div>
              <div className="text-sm font-medium text-ink">{SCHEDULE_HUMAN}</div>
            </div>
          </div>
          <div>
            <div className="text-[10px] uppercase tracking-wider text-faint">Next automatic run</div>
            <div className="text-sm font-medium text-ink">
              {eatDay(next, now)} {eatTime(next)}
              <span className="ml-2 text-xs font-normal text-mute">{inWords(next.getTime() - now.getTime())}</span>
            </div>
          </div>
          <div className="ml-auto">
            {missed ? (
              <span className="inline-flex items-center gap-2 rounded-md border border-warn/40 bg-warn/5 px-3 py-1.5 text-xs text-warn">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--warn)" }} />
                No automatic run since the {eatTime(prev!)} slot
              </span>
            ) : (
              <span className="inline-flex items-center gap-2 rounded-md border border-live/30 bg-live/5 px-3 py-1.5 text-xs text-live">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--live)" }} />
                On schedule{lastAuto ? ` · last auto ${ago(lastAuto.started_at)}` : ""}
              </span>
            )}
          </div>
        </div>
        {missed && (
          <p className="mt-3 border-t border-line pt-3 text-xs text-faint">
            The {eatTime(prev!)} slot passed with no scheduled run. Check{" "}
            <code className="text-mute">select jobname, schedule, active from cron.job</code> and the Vault{" "}
            <code className="text-mute">cron_secret</code>. Re-run below triggers it now (logged as manual).
          </p>
        )}
      </div>

      {/* KPIs */}
      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
        {kpis.map((k) => (
          <div key={k.label} className="rounded-xl border border-line bg-panel px-4 py-3">
            <div className="text-[10px] uppercase tracking-wider text-faint">{k.label}</div>
            <div className={"mt-0.5 text-2xl font-semibold tnum " + (k.tone ? TEXT[k.tone] : "text-ink")}>{k.value}</div>
            {k.sub && <div className="text-[11px] text-faint">{k.sub}</div>}
          </div>
        ))}
      </div>

      {/* written over recent runs */}
      {chart.length > 1 && (
        <div className="mb-6 rounded-xl border border-line bg-panel px-4 py-3">
          <div className="mb-2 flex items-center justify-between text-[10px] uppercase tracking-wider text-faint">
            <span>Written · last {chart.length} runs</span><span>peak {maxW}</span>
          </div>
          <div className="flex h-16 items-end gap-1">
            {chart.map((r) => (
              <div key={r.id} title={`${ago(r.started_at)} · ${r.written} written · ${stateOf(r)} · ${r.trigger}`}
                className="flex-1 rounded-t"
                style={{ height: `${Math.max(4, (r.written / maxW) * 100)}%`, background: DOT[stateOf(r)], opacity: 0.85 }} />
            ))}
          </div>
        </div>
      )}

      {/* per-source cards */}
      <div className="mb-8 grid gap-4 sm:grid-cols-2">
        {SCRAPERS.map((s) => {
          const lr = lastBySource.get(s.id);
          const st = lr ? stateOf(lr) : null;
          return (
            <div key={s.id} className="rounded-xl border border-line bg-panel p-5">
              <div className="flex items-start justify-between">
                <div>
                  <p className="font-mono text-sm text-ink">{s.id}</p>
                  <p className="mt-0.5 text-xs text-faint">{s.note}</p>
                </div>
                {s.kind === "edge" ? (
                  <form action={runAggregator}>
                    <button className="rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:border-gold/60 hover:text-gold">Re-run</button>
                  </form>
                ) : (
                  <a href={`https://github.com/${REPO}/actions/workflows/scrape-cbk.yml`} target="_blank" rel="noreferrer"
                     className="inline-flex items-center gap-1 rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:border-gold/60 hover:text-gold">
                    Run on GitHub <IconExternal size={12} />
                  </a>
                )}
              </div>
              <div className="mt-4 border-t border-line pt-3 text-xs">
                {lr && st ? (
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="h-2 w-2 rounded-full" style={{ background: DOT[st] }} />
                      <span className={TEXT[st]}>{st}</span>
                      {lr.source === "ke-aggregator" && <TriggerTag t={lr.trigger} />}
                      <span className="text-mute">{ago(lr.started_at)}</span>
                      <span className="tnum ml-auto text-faint"><span className="text-live">{lr.written}</span> written</span>
                    </div>
                    {(lr.errors?.length ?? 0) > 0 && (
                      <p className="truncate font-mono text-[11px] text-bad" title={lr.errors.join("\n")}>{lr.errors[0]}</p>
                    )}
                  </div>
                ) : (
                  <span className="text-faint">Never run.</span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* run log — expandable */}
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-mute">Run log</h2>
      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <div className="flex items-center gap-3 border-b border-line px-4 py-2.5 text-[11px] uppercase tracking-wider text-faint">
          <span className="w-6" /><span className="flex-1">Source</span>
          <span className="w-20">When</span><span className="w-24">Result</span>
          <span className="w-20 text-right tnum">w · r</span><span className="w-28 text-right">Notes</span>
        </div>
        {runs.map((r) => {
          const st = stateOf(r);
          const notes = (r.unmapped?.length ?? 0) + (r.errors?.length ?? 0);
          return (
            <details key={r.id} className="border-b border-line/60 last:border-0">
              <summary className="flex cursor-pointer list-none items-center gap-3 px-4 py-3 text-sm hover:bg-panel2/30 [&::-webkit-details-marker]:hidden">
                <span className="shrink-0 text-faint transition-transform [details[open]_&]:rotate-90">
                  <IconChevronRight size={14} />
                </span>
                <span className="flex flex-1 items-center gap-2">
                  <span className="font-mono text-xs text-ink">{r.source}</span>
                  {r.source === "ke-aggregator" && <TriggerTag t={r.trigger} />}
                </span>
                <span className="w-20 text-xs text-mute">{ago(r.started_at)}</span>
                <span className="w-24">
                  <span className={"inline-flex items-center gap-1.5 text-xs " + TEXT[st]}>
                    <span className="h-1.5 w-1.5 rounded-full" style={{ background: DOT[st] }} />{st}
                  </span>
                </span>
                <span className="w-20 text-right tnum text-xs text-faint">{r.written}w · {r.rejected}r</span>
                <span className="w-28 text-right text-xs">
                  {notes === 0 ? <span className="text-faint">—</span> : (
                    <>
                      {(r.unmapped?.length ?? 0) > 0 && <span className="text-warn">{r.unmapped.length} unmapped</span>}
                      {(r.errors?.length ?? 0) > 0 && <span className="text-bad">{(r.unmapped?.length ?? 0) > 0 ? " · " : ""}{r.errors.length} err</span>}
                    </>
                  )}
                </span>
              </summary>
              <div className="border-t border-line/60 bg-panel2/20">
                <RunDetail r={r} />
              </div>
            </details>
          );
        })}
        {runs.length === 0 && (
          <div className="px-4 py-10 text-center text-sm text-mute">No runs yet. Hit Re-run above, or trigger the CBK workflow.</div>
        )}
      </div>
    </div>
  );
}
