import { supabaseAdmin } from "@/lib/supabase/server";
import { runAggregator, runNseScraper, rebuildSnapshot } from "./actions";
import { RunButton } from "./RunButton";
import { FxHealth } from "./FxHealth";
import { IconExternal, IconChevronRight, IconClock } from "../_icons";

export const dynamic = "force-dynamic";

type Run = {
  id: number; source: string; trigger: string; started_at: string; finished_at: string | null;
  written: number; rejected: number; unmapped: string[]; errors: string[]; ok: boolean;
};

const REPO = process.env.GITHUB_REPO ?? "georgethedeveloper77/fructa";

// ── Schedule (mirror migrations/0022_reschedule_cron.sql) ───────────────────
// EAT = UTC+3. Aggregator fires 09:00 UTC = 12:00 EAT, weekdays.
const SCHEDULE_UTC_HOURS = [9];
const SCHEDULE_HUMAN = "Weekdays · 12:00 EAT";

// ── The fleet ───────────────────────────────────────────────────────────────
// This page used to be hard-wired to ke-aggregator. The schedule card, every
// KPI, the chart and the health check all read that one source, and the
// SCRAPERS list was decoration. So when the NSE price scraper was added, it got
// no trigger, no schedule, no health, and no way to see it fail. The Stocks page
// said "run it from Scrapers" and there was nothing here to run.
//
// Every scraper now declares its own schedule and its own runner, and the page
// computes health per source. Adding the next one is a row in this array.
//
// `sources` is a LIST because a scraper writes whatever source string it likes
// into scraper_runs, and the function name and the log name do not have to
// match. Matching on several means a renamed log line shows up as a run rather
// than silently reading "Never run", which is the exact failure this page is
// supposed to catch.
type Fleet = {
  id: string;
  sources: string[];
  label: string;
  note: string;
  // UTC hours it fires at. EAT is UTC+3.
  hoursUtc: number[];
  weekdaysOnly: boolean;
  human: string;
  kind: "edge" | "github";
  writes: string;
  // The workflow file, for github-kind scrapers. This was hardcoded to
  // scrape-cbk.yml for every one of them, which was fine while there was
  // exactly one and wrong the moment there were two.
  workflow?: string;
};

const SCRAPERS: Fleet[] = [
  {
    id: "ke-aggregator",
    sources: ["ke-aggregator"],
    label: "MMF aggregator",
    note: "Deno edge",
    hoursUtc: [9],
    weekdaysOnly: true,
    human: SCHEDULE_HUMAN,
    kind: "edge",
    writes: "rate_history",
  },
  {
    id: "ke-nse",
    sources: ["ke-nse", "scrape-nse", "nse"],
    label: "NSE end-of-day prices",
    // GitHub, not edge. afx blocks Supabase's eu-central-1 egress: it drops the
    // packets silently until the socket dies at 150s. A real browser user agent
    // changed nothing, so it is the ADDRESS, not the header. The runner fetches
    // and parses; the edge function still validates, stores and publishes.
    note: "GitHub Actions",
    hoursUtc: [16], // 16:00 UTC = 19:00 EAT, after the 15:00 EAT close
    weekdaysOnly: true,
    human: "Weekdays · 19:00 EAT",
    kind: "github",
    writes: "stock_prices",
    workflow: "scrape-nse.yml",
  },
  {
    id: "ke-cbk-tbills",
    sources: ["ke-cbk-tbills"],
    label: "CBK T-bills",
    note: "Playwright",
    hoursUtc: [],
    weekdaysOnly: false,
    human: "Weekly · Thursday",
    kind: "github",
    writes: "rate_history",
    workflow: "scrape-cbk.yml",
  },
];

// Only edge-kind scrapers have an in-admin runner. runNseScraper is kept and
// still works: it hits the edge function directly, which will now fail at the
// fetch because Supabase cannot reach afx. That is exactly what we want the
// button NOT to do, so ke-nse routes to GitHub instead.
const RUNNER: Record<string, (() => Promise<import("./actions").RunResult>) | null> = {
  "ke-aggregator": runAggregator,
  "ke-nse": null, // GitHub Actions: Supabase egress is blocked by the source
  "ke-cbk-tbills": null,
};

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
// Schedule maths, per scraper. These used to close over one global hours array,
// which is why the whole page could only ever describe the aggregator.
function nextRun(now: Date, hours: number[], weekdaysOnly: boolean): Date | null {
  if (hours.length === 0) return null; // GitHub-scheduled: we do not own the clock
  for (let d = 0; d < 8; d++) {
    const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + d));
    if (weekdaysOnly && !isWeekday(base)) continue;
    for (const h of [...hours].sort((a, b) => a - b)) {
      const t = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate(), h));
      if (t.getTime() > now.getTime()) return t;
    }
  }
  return null;
}
function prevRun(now: Date, hours: number[], weekdaysOnly: boolean): Date | null {
  if (hours.length === 0) return null;
  for (let d = 0; d < 8; d++) {
    const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - d));
    if (weekdaysOnly && !isWeekday(base)) continue;
    for (const h of [...hours].sort((a, b) => b - a)) {
      const t = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate(), h));
      if (t.getTime() <= now.getTime()) return t;
    }
  }
  return null;
}

/** Health of one scraper, from its own runs and its own schedule. */
type Health = {
  fleet: Fleet;
  runs: Run[];
  last: Run | null;
  lastAuto: Run | null;
  next: Date | null;
  prev: Date | null;
  missed: boolean;
  successRate: number;
};

function healthOf(f: Fleet, all: Run[], now: Date): Health {
  const runs = all.filter((r) => f.sources.includes(r.source));
  const last = runs[0] ?? null;
  const lastAuto = runs.find((r) => r.trigger !== "manual") ?? null;
  const recent = runs.slice(0, 20);
  const successRate = recent.length
    ? Math.round((recent.filter((r) => r.ok).length / recent.length) * 100)
    : 0;

  const next = nextRun(now, f.hoursUtc, f.weekdaysOnly);
  const prev = prevRun(now, f.hoursUtc, f.weekdaysOnly);
  const lastAutoAt = lastAuto ? new Date(lastAuto.started_at) : null;

  // A manual re-run does NOT satisfy the schedule. Only a scheduled run proves
  // pg_cron is alive, and conflating the two is exactly how a dead cron hides
  // behind someone pressing the button.
  const missed =
    prev != null &&
    now.getTime() - prev.getTime() > 75 * 60_000 &&
    (lastAutoAt == null || lastAutoAt.getTime() < prev.getTime());

  return { fleet: f, runs, last, lastAuto, next, prev, missed, successRate };
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
    return <p className="px-4 py-3 text-xs text-faint">Clean run. every row mapped, no errors.</p>;
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
            Unmapped · {r.unmapped.length} · source labels with no fund in the name map
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

  const now = new Date();
  const fleet = SCRAPERS.map((f) => healthOf(f, runs, now));

  // The aggregator keeps its chart: it is the only lane that runs often enough
  // for a 16-bar history to mean anything.
  const agg = fleet.find((h) => h.fleet.id === "ke-aggregator")!;
  const chart = agg.runs.slice(0, 16).reverse();
  const maxW = Math.max(1, ...chart.map((r) => r.written));

  // Fleet-wide, because the question this page must answer at a glance is "is
  // anything broken", not "is the aggregator fine".
  const broken = fleet.filter((h) => h.missed || (h.last != null && !h.last.ok));
  const neverRun = fleet.filter((h) => h.last == null && h.fleet.kind === "edge");

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-5 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Scrapers</h1>
          <p className="mt-1 text-sm text-mute">Automatic rate collection, with the exact rows that didn&apos;t map and why.</p>
        </div>
        {/* Rebuild used to be a form post into silence: no pending state, no
            confirmation, and the action swallowed every error. Deploying a
            function does NOT rebuild the snapshot, so this button is the last
            step of nearly every change, and it needs to say whether it worked. */}
        <RunButton action={rebuildSnapshot} label="Rebuild snapshot" variant="gold" />
      </header>

      {/* Anything broken, said once, at the top. Previously the only alarm on
          this page was "the aggregator missed its slot": a scraper that had
          never run in its life produced no warning at all, because the page did
          not know it existed. */}
      {(broken.length > 0 || neverRun.length > 0) && (
        <div className="mb-4 rounded-xl border border-bad/40 bg-bad/10 px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-bad">
            {broken.length + neverRun.length} {broken.length + neverRun.length === 1 ? "scraper needs" : "scrapers need"} attention
          </div>
          <ul className="mt-1.5 space-y-1 text-sm text-mute">
            {neverRun.map((h) => (
              <li key={h.fleet.id}>
                <code className="text-faint">{h.fleet.id}</code> has never run. Nothing has ever been written to{" "}
                <code className="text-faint">{h.fleet.writes}</code>.
              </li>
            ))}
            {broken.map((h) => (
              <li key={h.fleet.id}>
                <code className="text-faint">{h.fleet.id}</code>{" "}
                {h.missed
                  ? `has not run on schedule since the ${eatTime(h.prev!)} slot.`
                  : `failed ${ago(h.last!.started_at)}.`}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* The FX lane, above the fleet because it is the one thing on this page
          that fails SILENTLY. A scraper that stops writes nothing and the rows
          below go red. Open Exchange Rates stops at 1,000 requests a month by
          answering nothing at all: the last rate stays in fx_rates, the app
          keeps rendering it, and a stale number is pixel identical to a fresh
          one. This readout is the only warning that arrives before that. */}
      <FxHealth />

      {/* The fleet. One row per scraper: what it writes, when it fires, whether
          it fired, what it produced, and a button to fire it now. */}
      <div className="mb-6 overflow-hidden rounded-xl border border-line bg-panel">
        <div className="border-b border-line px-4 py-2.5 text-[11px] uppercase tracking-wider text-faint">
          Fleet
        </div>
        <div className="divide-y divide-line/60">
          {fleet.map((h) => {
            const lr = h.last;
            const st = lr ? stateOf(lr) : null;
            const runner = RUNNER[h.fleet.id];
            return (
              <div key={h.fleet.id} className="flex flex-wrap items-start gap-x-6 gap-y-3 px-4 py-4">
                <div className="min-w-[13rem] flex-1">
                  <div className="flex items-center gap-2">
                    <span className="h-2 w-2 shrink-0 rounded-full"
                      style={{ background: lr && st ? DOT[st] : "var(--faint)" }} />
                    <span className="font-mono text-sm text-ink">{h.fleet.id}</span>
                    {h.missed && (
                      <span className="rounded border border-warn/40 px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-warn">
                        off schedule
                      </span>
                    )}
                  </div>
                  <p className="mt-1 text-xs text-faint">
                    {h.fleet.note} {"\u00B7"} {h.fleet.human} {"\u00B7"} writes{" "}
                    <code className="text-mute">{h.fleet.writes}</code>
                  </p>
                </div>

                <div className="min-w-[8rem]">
                  <div className="text-[10px] uppercase tracking-wider text-faint">Last run</div>
                  {lr && st ? (
                    <div className="mt-0.5 text-sm">
                      <span className={TEXT[st]}>{st}</span>
                      <span className="ml-1.5 text-xs text-mute">{ago(lr.started_at)}</span>
                    </div>
                  ) : (
                    <div className="mt-0.5 text-sm text-bad">never</div>
                  )}
                </div>

                <div className="min-w-[7rem]">
                  <div className="text-[10px] uppercase tracking-wider text-faint">Next</div>
                  <div className="mt-0.5 text-sm text-mute">
                    {h.next ? `${eatDay(h.next, now)} ${eatTime(h.next)}` : "not scheduled here"}
                  </div>
                </div>

                <div className="min-w-[7rem]">
                  <div className="text-[10px] uppercase tracking-wider text-faint">Written</div>
                  <div className="tnum mt-0.5 text-sm">
                    {lr ? (
                      <>
                        <span className={lr.written > 0 ? "text-live" : "text-warn"}>{lr.written}</span>
                        {(lr.unmapped?.length ?? 0) > 0 && (
                          <span className="ml-2 text-xs text-warn">{lr.unmapped.length} unmapped</span>
                        )}
                        {(lr.errors?.length ?? 0) > 0 && (
                          <span className="ml-2 text-xs text-bad">{lr.errors.length} err</span>
                        )}
                      </>
                    ) : (
                      <span className="text-faint">nothing</span>
                    )}
                  </div>
                </div>

                <div className="ml-auto">
                  {runner ? (
                    <RunButton action={runner} />
                  ) : (
                    <a href={`https://github.com/${REPO}/actions/workflows/${h.fleet.workflow ?? "scrape-cbk.yml"}`}
                      target="_blank" rel="noreferrer"
                      className="inline-flex items-center gap-1 rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:border-gold/60 hover:text-gold">
                      Run on GitHub <IconExternal size={12} />
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Aggregator schedule detail. Kept, because it is the lane that fires
          daily and whose cron health is worth watching closely. */}
      <div className="mb-4 rounded-xl border border-line bg-panel p-4">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          <div className="flex items-center gap-2.5">
            <span className="text-gold"><IconClock size={15} /></span>
            <div>
              <div className="text-[10px] uppercase tracking-wider text-faint">Aggregator schedule</div>
              <div className="text-sm font-medium text-ink">{SCHEDULE_HUMAN}</div>
            </div>
          </div>
          <div className="ml-auto">
            {agg.missed ? (
              <span className="inline-flex items-center gap-2 rounded-md border border-warn/40 bg-warn/5 px-3 py-1.5 text-xs text-warn">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--warn)" }} />
                No automatic run since the {eatTime(agg.prev!)} slot
              </span>
            ) : (
              <span className="inline-flex items-center gap-2 rounded-md border border-live/30 bg-live/5 px-3 py-1.5 text-xs text-live">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--live)" }} />
                On schedule{agg.lastAuto ? ` \u00B7 last auto ${ago(agg.lastAuto.started_at)}` : ""}
              </span>
            )}
          </div>
        </div>
        {agg.missed && (
          <p className="mt-3 border-t border-line pt-3 text-xs text-faint">
            The {eatTime(agg.prev!)} slot passed with no scheduled run. Check{" "}
            <code className="text-mute">select jobname, schedule, active from cron.job</code> and the Vault{" "}
            <code className="text-mute">cron_secret</code>. Re-run above triggers it now (logged as manual).
          </p>
        )}
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

      {/* run log, expandable */}
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
                  <TriggerTag t={r.trigger} />
                </span>
                <span className="w-20 text-xs text-mute">{ago(r.started_at)}</span>
                <span className="w-24">
                  <span className={"inline-flex items-center gap-1.5 text-xs " + TEXT[st]}>
                    <span className="h-1.5 w-1.5 rounded-full" style={{ background: DOT[st] }} />{st}
                  </span>
                </span>
                <span className="w-20 text-right tnum text-xs text-faint">{r.written}w · {r.rejected}r</span>
                <span className="w-28 text-right text-xs">
                  {notes === 0 ? <span className="text-faint">none</span> : (
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
