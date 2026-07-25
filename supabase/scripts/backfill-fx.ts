// backfill-fx.ts
// One-time (idempotent) loader: CBK daily indicative exchange rates -> fx_rates.
//
// This is the file that actually unblocks the currency comparison. Without it
// fx_rates only holds rows from the day the aggregator first ran, so every
// historical chart on the page renders empty. One pass here loads years.
//
// Note for whoever reads this next: backfill-cbk.ts is NOT this. That one is a
// T-bill auction loader that writes into rate_history. The names are close and
// the jobs are unrelated.
//
// Source: CBK "Foreign Exchange Rates", exported as CSV
//   https://www.centralbank.go.ke/rates/forex-exchange-rates/
//
// HOW TO GET THE FILE. The table on that page exports only what is on screen
// and caps at 6,000 rows. The whole multi-currency table burns that in under a
// year, so FILTER THE TABLE TO "US DOLLAR" FIRST, then set "Show 6,000
// entries", then export. One dollar-only export covers about twenty years.
// The per-year "CBK Indicative Exchange Rates <year>" links on the same page
// are the alternative; pass several of them at once, this script takes a list.
// If a download arrives as .xlsx, open it and save as CSV. No spreadsheet
// parsing here on purpose: a silent column shift in a binary format is a whole
// class of bug this pipeline does not need.
//
// WHAT CBK's BUY AND SELL ACTUALLY ARE. They are the INTERBANK indicative
// spread, roughly a quarter of a percent each way, and they are NOT what a
// bank quotes a retail customer over the counter. On 04/01/2024 CBK printed
// mean 157.3912, buy 157.0000, sell 157.7824. No walk-in customer converted at
// those rates. So the legs are stored because they are real and useful as a
// floor, and the app's RETAIL spread stays a separate, larger, admin-editable
// assumption in the `fx.spread_pct` config key. Wiring the app's retail spread
// to the number this script measures would understate the cost of converting
// by roughly three points on a one year comparison, which is most of the
// decision the currency page exists to price.
//
// Input is header driven, so column order does not matter. Recognised headers,
// matched case insensitively on a substring:
//   date            -> date | day | as_of
//   mean            -> mean | exchange rate | rate | close | value
//   bid             -> buy | bid
//   ask             -> sell | ask
//   currency filter -> currency | curr   (rows are kept only if they are USD)
//
// Both CBK shapes parse:
//   Date, Currency, Mean, Buy, Sell    cbk-indicative-rates
//   Date, Currency, EXCHANGE RATE      rates/forex-exchange-rates
// The legs are claimed before the mean, so "Buy Rate" is never read as the
// rate column. A UTF-8 BOM on the first cell is stripped.
//
// Only `date` is required. If `mean` is absent it is derived from bid and ask.
// If bid and ask are absent the row still loads with mean alone, which is
// enough for the charts and leaves the engine falling back to a modelled
// spread.
//
// Dates are accepted as YYYY-MM-DD, DD/MM/YYYY or DD-MMM-YYYY, because CBK has
// used all three across different export vintages.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//     deno run --allow-env --allow-read --allow-net backfill-fx.ts rates.csv
//
//   Several files at once, deduplicated across all of them:
//     deno run ... backfill-fx.ts 2021.csv 2022.csv 2023.csv
//
//   Add --dry to parse and report without writing anything.

import { createClient } from "jsr:@supabase/supabase-js@2";

const PAIR = "USD/KES";
const SOURCE = "cbk-backfill";
const CHUNK = 500;

// Same plausibility band as _shared/cbk-fx.ts. A USD/KES quote outside this is
// a parse error every time.
const LO = 90;
const HI = 250;

interface Row {
  pair: string;
  rate: number;
  bid: number | null;
  ask: number | null;
  as_of: string;
  source: string;
}

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** Accepts the three date shapes CBK has shipped. Returns YYYY-MM-DD or null. */
function parseDate(raw: string): string | null {
  const s = raw.trim().replace(/^"|"$/g, "");
  if (!s) return null;

  const iso = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (iso) {
    return `${iso[1]}-${pad(Number(iso[2]))}-${pad(Number(iso[3]))}`;
  }

  // 31/03/2026 and 31-03-2026. Day first, which is the Kenyan convention and
  // what every CBK export uses.
  const dmy = s.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$/);
  if (dmy) {
    const d = Number(dmy[1]);
    const m = Number(dmy[2]);
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return `${dmy[3]}-${pad(m)}-${pad(d)}`;
  }

  // 31-Mar-2026 and 31 Mar 2026.
  const dMy = s.match(/^(\d{1,2})[\s\-]([A-Za-z]{3,})[\s\-](\d{4})$/);
  if (dMy) {
    const m = MONTHS[dMy[2].slice(0, 3).toLowerCase()];
    if (!m) return null;
    return `${dMy[3]}-${pad(m)}-${pad(Number(dMy[1]))}`;
  }

  return null;
}

function toNum(raw: string | undefined): number | null {
  if (raw == null) return null;
  // CBK exports carry thousands separators on some sheets and stray spaces on
  // most of them.
  const n = Number(raw.replace(/[",\s]/g, ""));
  return Number.isFinite(n) && n >= LO && n <= HI ? Number(n.toFixed(4)) : null;
}

/**
 * Which delimiter this file uses. CBK exports have arrived comma separated,
 * semicolon separated (a European locale export) and tab separated depending on
 * the browser and year, and a wrong guess produces one giant column and the
 * useless error "no date column found".
 */
function sniff(lines: string[]): string {
  const candidates = [",", ";", "\t"];
  let best = ",";
  let bestScore = -1;
  for (const d of candidates) {
    // Score on the first few lines so one ragged row cannot decide it.
    const score = lines
      .slice(0, 5)
      .reduce((acc, l) => acc + l.split(d).length - 1, 0);
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

/** Minimal CSV split that survives quoted fields containing the delimiter. */
function splitLine(line: string, delim = ","): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      quoted = !quoted;
      continue;
    }
    if (ch === delim && !quoted) {
      out.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  out.push(cur);
  return out.map((c) => c.trim());
}

/**
 * Is this row the US dollar?
 *
 * This used to be `cur.includes("us")`, which is true of "AUSTRALIAN $".
 * Every Australian dollar row in the file loaded as USD/KES, at roughly two
 * thirds of the real rate, interleaved with the correct rows and sorted by
 * date so it looked like a plausible series. Substring matching on currency
 * names is not a shortcut, it is a trap.
 */
function isUsd(raw: string): boolean {
  const c = raw.trim().toLowerCase().replace(/[.\s]+/g, " ").trim();
  return c === "usd" ||
    c === "us dollar" ||
    c === "u s dollar" ||
    c === "united states dollar" ||
    c === "us dollars";
}

interface Cols {
  date: number;
  mean: number;
  bid: number;
  ask: number;
  currency: number;
}

function findCols(header: string[]): Cols | null {
  // Strip a UTF-8 BOM off the first cell. CBK's export carries one, which
  // turns "Date" into "\uFEFFDate" and quietly breaks any exact match.
  const norm = header.map((h) =>
    h.replace(/^\uFEFF/, "").trim().toLowerCase()
  );
  const claimed = new Set<number>();

  // Each needle scans only columns nothing else has taken, so the ORDER of the
  // calls below is load bearing: the legs are claimed before the mean, which
  // is what stops a header like "Buy Rate" being read as the rate column.
  const take = (...needles: string[]): number => {
    for (const n of needles) {
      const i = norm.findIndex((h, k) => !claimed.has(k) && h.includes(n));
      if (i >= 0) {
        claimed.add(i);
        return i;
      }
    }
    return -1;
  };

  const date = take("date", "day", "as_of");
  if (date < 0) return null;

  const currency = take("currency", "curr");
  const bid = take("buy", "bid");
  const ask = take("sell", "ask");
  // "exchange rate" before the bare "rate" so the full label wins when both
  // could match. CBK ships at least two shapes:
  //   Date, Currency, Mean, Buy, Sell       (cbk-indicative-rates)
  //   Date, Currency, EXCHANGE RATE         (rates/forex-exchange-rates)
  // The second is the one with twenty years of history behind it, and it
  // carries no legs at all, which is fine: CBK's legs are interbank and the
  // app's retail spread is a separate assumption regardless.
  const mean = take("mean", "exchange rate", "rate", "close", "value");

  return { date, mean, bid, ask, currency };
}

function parseCsv(
  text: string,
  seen: Set<string>,
): { rows: Row[]; skipped: number } {
  const lines = text.replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (lines.length === 0) return { rows: [], skipped: 0 };

  const delim = sniff(lines);

  // The header is not always line 0. CBK exports have shipped with a title
  // row, a blank-ish banner and a source note above it, so scan the first few
  // lines for the first one that actually carries a date column.
  let cols: Cols | null = null;
  let headerAt = -1;
  const HEADER_SCAN = 12;
  for (let i = 0; i < Math.min(HEADER_SCAN, lines.length); i++) {
    const found = findCols(splitLine(lines[i], delim));
    if (found) {
      cols = found;
      headerAt = i;
      break;
    }
  }
  if (!cols) {
    throw new Error(
      `no date column in the first ${HEADER_SCAN} lines. Saw: ` +
        lines.slice(0, 3).map((l) => `"${l.slice(0, 90)}"`).join(" / "),
    );
  }
  if (cols.mean < 0 && (cols.bid < 0 || cols.ask < 0)) {
    throw new Error(
      "need either a mean column, or both a buy and a sell column",
    );
  }

  if (cols.currency < 0) {
    console.warn(
      "  note: no currency column, so every row is taken as USD/KES.",
    );
    console.warn(
      "        Make sure the export was filtered to US DOLLAR first.",
    );
  }

  const rows: Row[] = [];
  let skipped = 0;

  for (const line of lines.slice(headerAt + 1)) {
    const c = splitLine(line, delim);
    const as_of = parseDate(c[cols.date] ?? "");
    if (!as_of) {
      skipped++;
      continue;
    }

    // Multi currency exports carry every pair. Keep the dollar rows only.
    if (cols.currency >= 0 && !isUsd(c[cols.currency] ?? "")) {
      skipped++;
      continue;
    }

    const bid = cols.bid >= 0 ? toNum(c[cols.bid]) : null;
    const ask = cols.ask >= 0 ? toNum(c[cols.ask]) : null;
    let rate = cols.mean >= 0 ? toNum(c[cols.mean]) : null;
    if (rate == null && bid != null && ask != null) {
      rate = Number(((bid + ask) / 2).toFixed(4));
    }
    if (rate == null) {
      skipped++;
      continue;
    }

    // A crossed quote is a column mix up, not a market. Drop the legs and keep
    // the mean rather than writing something the check constraint will reject.
    const ordered = bid != null && ask != null && bid > ask;

    // CBK publishes one row per business day. A duplicate date means the export
    // overlaps another file, and last write would win silently, so take the
    // first and count the rest.
    if (seen.has(as_of)) {
      skipped++;
      continue;
    }
    seen.add(as_of);

    rows.push({
      pair: PAIR,
      rate,
      bid: ordered ? null : bid,
      ask: ordered ? null : ask,
      as_of,
      source: SOURCE,
    });
  }

  rows.sort((a, b) => (a.as_of < b.as_of ? -1 : 1));
  return { rows, skipped };
}

async function main() {
  const dry = Deno.args.includes("--dry");
  const paths = Deno.args.filter((a) => !a.startsWith("--"));

  if (paths.length === 0) {
    console.error(
      "usage: deno run --allow-env --allow-read --allow-net backfill-fx.ts <rates.csv> [more.csv ...] [--dry]",
    );
    console.error("");
    console.error("Get the CSV from:");
    console.error("  https://www.centralbank.go.ke/rates/forex-exchange-rates/");
    console.error("  Filter the table to US DOLLAR, set Show 6,000 entries, export.");
    Deno.exit(1);
  }

  // Shared across every file so a date appearing in two overlapping yearly
  // exports is taken once, from whichever file was listed first.
  const seen = new Set<string>();
  const rows: Row[] = [];
  let skipped = 0;

  for (const path of paths) {
    let text: string;
    try {
      text = await Deno.readTextFile(path);
    } catch {
      console.error(`cannot read ${path}. Check the path, and note that an`);
      console.error("xlsx download has to be saved as CSV first.");
      Deno.exit(1);
    }
    const r = parseCsv(text, seen);
    rows.push(...r.rows);
    skipped += r.skipped;
    console.log(`${path}: ${r.rows.length} rows, ${r.skipped} skipped`);
  }

  if (rows.length === 0) {
    console.error("no valid rows parsed. Check the header and the date format.");
    Deno.exit(1);
  }

  rows.sort((a, b) => (a.as_of < b.as_of ? -1 : 1));

  const withLegs = rows.filter((r) => r.bid != null && r.ask != null);
  const oneWay = withLegs
    .filter((r) => r.rate > 0)
    .map((r) => ((r.ask! - r.bid!) / 2 / r.rate) * 100);
  const meanSpread = oneWay.length
    ? oneWay.reduce((a, b) => a + b, 0) / oneWay.length
    : null;

  // Sanity band. USD/KES has run roughly 100 to 165 over the last decade, so
  // anything far outside that in a parsed file is a column shift, not a market.
  const lo = Math.min(...rows.map((r) => r.rate));
  const hi = Math.max(...rows.map((r) => r.rate));

  console.log("");
  console.log(`parsed   ${rows.length} rows, skipped ${skipped}`);
  console.log(`range    ${rows[0].as_of} to ${rows[rows.length - 1].as_of}`);
  console.log(`rate     ${lo.toFixed(4)} low, ${hi.toFixed(4)} high`);
  console.log(`quotes   ${withLegs.length} rows carry both legs`);
  if (meanSpread != null) {
    console.log(`spread   ${meanSpread.toFixed(3)}% one way, INTERBANK`);
    console.log("");
    console.log("         Do NOT set fx.spread_pct to that number. CBK's buy");
    console.log("         and sell are the interbank indicative, not a retail");
    console.log("         counter quote. fx.spread_pct is the RETAIL");
    console.log("         assumption and belongs somewhere near 1.5.");
  }
  if (hi > 200 || lo < 60) {
    console.log("");
    console.log("WARNING  a rate outside the plausible USD/KES band was parsed.");
    console.log("         Check that the Mean column was not read off a");
    console.log("         neighbouring currency before writing this.");
  }

  if (dry) {
    console.log("");
    console.log("dry run, nothing written");
    return;
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
    Deno.exit(1);
  }
  const db = createClient(url, key);

  let written = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const batch = rows.slice(i, i + CHUNK);
    // Primary key is (pair, as_of), so re-running is safe and a later, richer
    // export overwrites an earlier mean-only one.
    const { error } = await db
      .from("fx_rates")
      .upsert(batch, { onConflict: "pair,as_of" });
    if (error) throw new Error(`upsert failed: ${error.message}`);
    written += batch.length;
    console.log(`  wrote ${written}/${rows.length}`);
  }

  console.log(`done: ${written} fx_rates rows for ${PAIR}`);
  console.log("next: deploy the functions, then Rebuild snapshot in admin");
}

if (import.meta.main) await main();
