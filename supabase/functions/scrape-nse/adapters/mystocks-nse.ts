// supabase/functions/scrape-nse/adapters/mystocks-nse.ts
//
// The NSE board from live.mystocks.co.ke/m/pricelist.
//
// ── WHY THIS SOURCE ─────────────────────────────────────────────────────────
// afx is gone. It blocks datacenter IP ranges: four attempts, two networks
// (Supabase eu-central-1 and a GitHub runner), three clients (Deno fetch with a
// bot UA, Deno fetch with a Chrome UA, and real Chromium via Playwright). Always
// silence, never once a status code. A refusal has a status code; a hang is a
// firewall dropping packets.
//
// mystocks was chosen ON EVIDENCE, not by taste. The probe, run from the exact
// runner that will scrape it, found: HTTP 200 in 1.9s, no auth wall, 30 of 30
// known tickers, and SCOM at 35.05 which is the SAME price afx quoted. Two
// independent sources agreeing is worth more than one source asserting.
//
// Two candidates were rejected, and both would have passed a naive check:
//
//   /price_list/   returned HTTP 200 and BOUNCED TO A LOGIN. A parser aimed at
//                  it would have found 9 rows and reported an empty market.
//   /m/            returned 200, no auth wall, 30 tickers, and quoted SCOM at
//                  1.44. Structurally perfect, completely wrong. Only the VALUE
//                  gave it away.
//
// ── WHY THE COLUMNS ARE FOUND BY NAME ───────────────────────────────────────
// The previous NSE parser in this repo (nse-price-table.ts, now dead) read
// column 3 because column 3 looked like a price. That kind of parser does not
// break loudly the day a site inserts a "Change %" column. It breaks by reading
// the wrong number and storing it as a price, and nobody notices until a user
// does.
//
// So this reads the HEADER ROW and locates each column by what it is CALLED. If
// it cannot find a price column, it THROWS. An adapter that cannot identify its
// own columns must not fall back to a guess.

import { DOMParser, type Element } from "https://deno.land/x/deno_dom@v0.1.45/deno-dom-wasm.ts";
import type { StockPriceAdapter, StockPriceRow } from "../../_shared/types.ts";

export const MYSTOCKS_URL = "https://live.mystocks.co.ke/m/pricelist";

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

/** The date the BOARD says it is, not the date we happen to be running.
 *
 *  This matters more than it looks. The scraper fires at 19:00 EAT on weekdays,
 *  but the NSE does not trade on public holidays, and mystocks leaves the last
 *  session's board up when the market is shut. Stamping that board with today's
 *  date would invent a trading day that never happened, and then prev_close
 *  would compute a day-change across a seam where no trading occurred.
 *
 *  The page header reads "Market Pricelist - 10 Jul 2026". Read it. If it is not
 *  there, we do not know what day this board is, and a price without a date is
 *  not something we should be storing. */
export function parseBoardDate(html: string): string {
  const m = html.match(
    /Market\s+Pricelist[^0-9]{0,12}(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(20\d{2})/i,
  );
  if (!m) {
    throw new Error(
      "mystocks: no board date on the page. Refusing to guess which trading " +
        "day these prices belong to.",
    );
  }
  const day = Number(m[1]);
  const mon = MONTHS[m[2].toLowerCase()];
  const year = Number(m[3]);
  if (!mon) throw new Error(`mystocks: unrecognised month "${m[2]}"`);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${year}-${pad(mon)}-${pad(day)}`;
}

/** Numbers as the board writes them: "1,355.00", "(0.25)" for negative, "-" for
 *  nothing. A dash is ABSENT, not zero, and returning 0 for it would turn a
 *  counter that did not trade into one that fell to nothing. */
function num(raw: string): number | null {
  const s = raw.replace(/\u00a0/g, " ").trim();
  if (!s || s === "-" || s === "--" || /^n\/?a$/i.test(s)) return null;
  const neg = /^\(.*\)$/.test(s);
  const cleaned = s.replace(/[(),%\s]/g, "").replace(/,/g, "");
  const n = Number(cleaned);
  if (!Number.isFinite(n)) return null;
  return neg ? -n : n;
}

/** Find a column by what its header CALLS it. Returns -1 when absent, and the
 *  caller decides whether absence is survivable: a missing volume column is a
 *  shrug, a missing price column is fatal. */
function col(headers: string[], ...patterns: RegExp[]): number {
  for (const p of patterns) {
    const i = headers.findIndex((h) => p.test(h));
    if (i >= 0) return i;
  }
  return -1;
}

export function parseMystocksBoard(html: string): StockPriceRow[] {
  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) throw new Error("mystocks: could not parse the page");

  const asOf = parseBoardDate(html);

  // The board is the table whose rows link to individual stocks. The page also
  // carries navigation tables and index widgets, and picking "the first table"
  // or "the biggest table" is the same class of assumption that this whole
  // adapter exists to avoid.
  const tables = [...doc.querySelectorAll("table")] as Element[];
  let board: Element | null = null;
  let best = 0;
  for (const t of tables) {
    const links = t.querySelectorAll('a[href*="stock="]').length;
    if (links > best) {
      best = links;
      board = t;
    }
  }
  if (!board || best < 20) {
    throw new Error(
      `mystocks: no table with per-stock links found (best had ${best}). ` +
        "The page layout has changed, or this is not the board.",
    );
  }

  const rows = [...board.querySelectorAll("tr")] as Element[];

  // Headers. Take the first row that has any th, or failing that the first row.
  const headerRow = rows.find((r) => r.querySelectorAll("th").length > 0) ?? rows[0];
  const headers = [...headerRow.querySelectorAll("th,td")].map((c) =>
    (c.textContent ?? "").replace(/\s+/g, " ").trim().toLowerCase()
  );

  const iPrice = col(headers, /\bclose\b/, /\bprice\b/, /\blast\b/);
  const iChange = col(headers, /change/, /\bchg\b/, /^\+\/-$/);
  const iVolume = col(headers, /volume/, /\bvol\b/, /shares/);
  const iHigh = col(headers, /high/);
  const iLow = col(headers, /low/);

  if (iPrice < 0) {
    // The one failure we refuse to work around. Without a named price column we
    // would be back to counting columns and hoping.
    throw new Error(
      `mystocks: no price column. Headers were: ${JSON.stringify(headers)}. ` +
        "Refusing to guess which column is the price.",
    );
  }

  const out: StockPriceRow[] = [];

  for (const tr of rows) {
    // The ticker comes from the LINK, not the visible text. The visible cell may
    // hold a company name, and matching names to tickers is a fuzzy problem we
    // do not need to have: the href already says stock=SCOM.
    const a = tr.querySelector('a[href*="stock="]');
    if (!a) continue; // header row, section divider, or a nav row
    const href = a.getAttribute("href") ?? "";
    const t = href.match(/stock=([A-Za-z0-9._-]+)/);
    if (!t) continue;
    const ticker = t[1].trim().toUpperCase();

    const cells = [...tr.querySelectorAll("td,th")].map((c) =>
      (c.textContent ?? "").replace(/\s+/g, " ").trim()
    );
    if (cells.length <= iPrice) continue;

    const close = num(cells[iPrice]);
    // No price is NOT a zero price. A counter that did not trade is skipped, not
    // recorded as having crashed to nothing.
    if (close == null || close <= 0) continue;

    const change = iChange >= 0 && iChange < cells.length ? num(cells[iChange]) : null;

    out.push({
      ticker,
      close,
      // prev_close is DERIVED, and only when the board actually gave us a change.
      // Never invent it: a fabricated prev_close produces a fabricated day move.
      prevClose: change == null ? null : Number((close - change).toFixed(4)),
      high: iHigh >= 0 && iHigh < cells.length ? num(cells[iHigh]) : null,
      low: iLow >= 0 && iLow < cells.length ? num(cells[iLow]) : null,
      volume: iVolume >= 0 && iVolume < cells.length ? num(cells[iVolume]) : null,
      asOf,
    });
  }

  // The NSE has roughly 60 listed counters. A board with 12 of them is a
  // fragment, a widget, or a half-rendered page, and storing it would look like
  // a market where two thirds of the companies vanished overnight.
  if (out.length < 40) {
    throw new Error(
      `mystocks: only ${out.length} rows parsed, expected 60 or more. ` +
        "Refusing a partial board.",
    );
  }

  return out;
}

export function mystocksAdapter(url = MYSTOCKS_URL): StockPriceAdapter {
  return {
    id: "mystocks-nse",
    async fetchRows(): Promise<StockPriceRow[]> {
      // NOTE: this direct-fetch path is here for completeness and for local use.
      // In production the fetch happens in a real browser on a GitHub runner
      // (scrapers/fetch-nse-html.mjs) and the parsed board is POSTed to this
      // function. mystocks answered a plain request in the probe, but it answered
      // CHROMIUM. Do not assume a bare fetch gets the same treatment: that
      // assumption is exactly what cost us a day on afx.
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 20_000);
      try {
        const res = await fetch(url, {
          signal: ctl.signal,
          headers: {
            "User-Agent":
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
              "(KHTML, like Gecko) Chrome/126.0 Safari/537.36 " +
              "(+https://fructa.africa; end-of-day reader, 1 request per day)",
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-GB,en;q=0.9",
          },
        });
        if (!res.ok) throw new Error(`mystocks: HTTP ${res.status}`);
        return parseMystocksBoard(await res.text());
      } catch (e) {
        if (e instanceof Error && e.name === "AbortError") {
          throw new Error(
            `mystocks: no response from ${url} within 20s. Fetch it with ` +
              "Chromium on a runner instead.",
          );
        }
        throw e;
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
