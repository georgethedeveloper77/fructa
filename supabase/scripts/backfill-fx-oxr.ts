// backfill-fx-oxr.ts
// One-time (resumable) loader: Open Exchange Rates historical -> fx_rates.
//
// THE POINT OF THIS FILE IS THE MONTH-END SAMPLING, so read this before
// changing it.
//
// OXR's free plan allows 1,000 requests a month, and every call to
// historical/YYYY-MM-DD.json costs one, regardless of how many currencies come
// back. Five years of DAILY history is about 1,825 calls. That does not fit,
// and it never will on the free plan.
//
// But the app does not need daily history. The snapshot builder samples
// fx_rates to MONTH END when it builds fx_series, because the currency charts
// compare an entry point against an exit point and an average of daily means is
// a rate nobody ever traded at. Five years of month end is 60 calls. That fits
// with 940 to spare, and leaves the daily lane (about 22 calls a month) with
// room it will never use.
//
// So: one request per calendar month, on the last day of that month.
//
// The time-series.json endpoint would do this in one call, but it is not on the
// free plan and it bills one request per day of data returned anyway, so it
// would cost the same 1,825 requests it is supposed to save.
//
// THIS IS A MID-MARKET RATE, NOT CBK. OXR is a global aggregate. CBK's
// indicative mean is the number a Kenyan checks and the one worth citing, and
// backfill-fx.ts loads it from the published CSV with exact columns and daily
// granularity. The two coexist: fx_rates.source records which produced each
// row, so a mixed series is auditable rather than mysterious. If you have the
// CBK CSV, prefer it and use this only for the live daily lane.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... OXR_APP_ID=... \
//     deno run --allow-env --allow-net backfill-fx-oxr.ts [--from=2021-07] [--dry]
//
//   --from   first month to load, YYYY-MM. Default: 60 months back.
//   --dry    report the plan and the quota cost, write nothing.
//   --force  re-fetch months already present in fx_rates.

import { createClient } from "jsr:@supabase/supabase-js@2";

const PAIR = "USD/KES";
const SOURCE = "openexchangerates-backfill";
const OXR_BASE = "https://openexchangerates.org/api";

/// Be a good citizen. The quota is monthly, not per second, but hammering an
/// endpoint 60 times in 60 milliseconds is how an app id gets rate limited.
const THROTTLE_MS = 250;

const DEFAULT_MONTHS_BACK = 60;

interface Row {
  pair: string;
  rate: number;
  as_of: string;
  source: string;
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// Last calendar day of a month, as YYYY-MM-DD. Day 0 of the NEXT month is the
/// last day of this one, and Date.UTC handles February and leap years for us.
function monthEnd(year: number, month1: number): string {
  const d = new Date(Date.UTC(year, month1, 0));
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/// Every month-end date from `from` up to and including the last COMPLETE
/// month. The current month is skipped: its month end has not happened yet, and
/// the live daily lane is already covering today.
function monthEnds(fromYear: number, fromMonth1: number): string[] {
  const now = new Date();
  const out: string[] = [];
  let y = fromYear;
  let m = fromMonth1;
  for (let i = 0; i < 600; i++) {
    // Stop before the current month.
    if (y > now.getUTCFullYear() ||
      (y === now.getUTCFullYear() && m >= now.getUTCMonth() + 1)) {
      break;
    }
    out.push(monthEnd(y, m));
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}

function plausible(n: unknown): number | null {
  return typeof n === "number" && Number.isFinite(n) && n >= 90 && n <= 250
    ? Number(n.toFixed(4))
    : null;
}

interface Usage {
  used: number;
  quota: number;
  remaining: number;
  unlimited: boolean;
}

/// Free, and does not count against the quota.
async function fetchUsage(appId: string): Promise<Usage | null> {
  try {
    const res = await fetch(`${OXR_BASE}/usage.json?app_id=${appId}`);
    if (!res.ok) return null;
    const j = await res.json();
    const u = j?.data?.usage;
    const used = Number(u?.requests);
    const quota = Number(u?.requests_quota);
    const remaining = Number(u?.requests_remaining);
    if (!Number.isFinite(used)) return null;
    return {
      used,
      quota,
      remaining,
      unlimited: quota < 0,
    };
  } catch {
    return null;
  }
}

async function fetchHistorical(
  appId: string,
  date: string,
): Promise<number | null> {
  const res = await fetch(`${OXR_BASE}/historical/${date}.json?app_id=${appId}`);
  if (!res.ok) {
    if (res.status === 429) {
      throw new Error(
        "HTTP 429: monthly request quota exhausted. Re-run next month, or upgrade the plan. Everything written so far is saved and this script resumes.",
      );
    }
    if (res.status === 401) {
      throw new Error("HTTP 401: OXR_APP_ID is wrong or revoked.");
    }
    if (res.status === 403) {
      throw new Error(
        "HTTP 403: this app id cannot reach the historical endpoint. Check the plan.",
      );
    }
    return null;
  }
  const j = await res.json();
  return plausible(j?.rates?.KES);
}

function arg(name: string): string | null {
  const hit = Deno.args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

async function main() {
  const dry = Deno.args.includes("--dry");
  const force = Deno.args.includes("--force");

  const appId = Deno.env.get("OXR_APP_ID");
  if (!appId) {
    console.error("OXR_APP_ID is required. Get one at openexchangerates.org.");
    Deno.exit(1);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
    Deno.exit(1);
  }
  const db = createClient(url, key, { auth: { persistSession: false } });

  // Start month.
  let y: number;
  let m: number;
  const from = arg("from");
  if (from) {
    const mm = from.match(/^(\d{4})-(\d{1,2})$/);
    if (!mm) {
      console.error(`--from must be YYYY-MM, got "${from}"`);
      Deno.exit(1);
    }
    y = Number(mm[1]);
    m = Number(mm[2]);
    if (m < 1 || m > 12) {
      console.error(`--from month out of range: ${from}`);
      Deno.exit(1);
    }
  } else {
    const back = new Date();
    back.setUTCMonth(back.getUTCMonth() - DEFAULT_MONTHS_BACK);
    y = back.getUTCFullYear();
    m = back.getUTCMonth() + 1;
  }

  const all = monthEnds(y, m);
  if (all.length === 0) {
    console.error("nothing to do: the start month is not in the past");
    Deno.exit(1);
  }

  // Resume: which months does fx_rates already cover? Skipping them is what
  // makes a 429 partway through harmless.
  const covered = new Set<string>();
  if (!force) {
    const { data, error } = await db
      .from("fx_rates")
      .select("as_of")
      .eq("pair", PAIR);
    if (error) {
      console.error(`could not read fx_rates: ${error.message}`);
      Deno.exit(1);
    }
    for (const r of data ?? []) covered.add(String(r.as_of).slice(0, 7));
  }

  const todo = all.filter((d) => !covered.has(d.slice(0, 7)));

  console.log(`months in range   ${all.length}  (${all[0]} to ${all[all.length - 1]})`);
  console.log(`already covered   ${all.length - todo.length}`);
  console.log(`to fetch          ${todo.length}  = ${todo.length} requests`);

  const usage = await fetchUsage(appId);
  if (usage) {
    if (usage.unlimited) {
      console.log(`quota             ${usage.used} used, unlimited plan`);
    } else {
      console.log(
        `quota             ${usage.used} / ${usage.quota} used, ${usage.remaining} remaining`,
      );
      if (!dry && todo.length > usage.remaining) {
        console.error("");
        console.error(
          `refusing to start: this run needs ${todo.length} requests and only ${usage.remaining} remain.`,
        );
        console.error(
          "Narrow the range with --from, or wait for the quota to reset. Partial runs resume cleanly.",
        );
        Deno.exit(1);
      }
    }
  } else {
    console.log("quota             could not be read, continuing anyway");
  }

  if (todo.length === 0) {
    console.log("");
    console.log("nothing to fetch. Use --force to re-fetch covered months.");
    return;
  }

  if (dry) {
    console.log("");
    console.log("dry run, nothing written");
    return;
  }

  const rows: Row[] = [];
  let missing = 0;

  for (const date of todo) {
    const rate = await fetchHistorical(appId, date);
    if (rate == null) {
      missing++;
      console.log(`  ${date}  no plausible rate`);
    } else {
      rows.push({ pair: PAIR, rate, as_of: date, source: SOURCE });
      console.log(`  ${date}  ${rate}`);
    }
    await new Promise((r) => setTimeout(r, THROTTLE_MS));
  }

  if (rows.length === 0) {
    console.error("no rows fetched");
    Deno.exit(1);
  }

  // Primary key is (pair, as_of), so re-running is safe. Chunked because a
  // --from far enough back can exceed a comfortable single statement.
  const CHUNK = 200;
  let written = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const batch = rows.slice(i, i + CHUNK);
    const { error } = await db
      .from("fx_rates")
      .upsert(batch, { onConflict: "pair,as_of" });
    if (error) throw new Error(`upsert failed: ${error.message}`);
    written += batch.length;
  }

  console.log("");
  console.log(`done: ${written} month-end rows for ${PAIR}, ${missing} missing`);
  console.log("next: Rebuild snapshot in admin so fx_series picks them up");
}

if (import.meta.main) await main();
