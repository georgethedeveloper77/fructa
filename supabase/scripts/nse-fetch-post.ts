// supabase/scripts/nse-fetch-post.ts
//
// Fetch the NSE board from afx and POST it to the scrape-nse edge function.
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// afx blocks Supabase's egress. The edge functions run in eu-central-1, and afx
// drops those packets silently: no 403, no 429, just no answer until the socket
// dies at 150 seconds. We proved it was the ADDRESS and not the header by
// swapping the honest "FructaBot/1.0" user agent for a real Chrome string and
// getting the identical hang.
//
// So the fetch moves to a GitHub Actions runner, whose IP looks like an ordinary
// client. This is not a new idea in this codebase: ke-cbk-tbills already runs
// exactly this way for the same class of reason.
//
// ── WHAT THIS DOES AND DOES NOT DO ──────────────────────────────────────────
// It does ONE thing: fetch and parse. It then hands the board to the edge
// function, which owns everything that matters and is the only place any of it
// lives: ticker mapping, the sanity band, prev_close from our own stored series,
// source health, the run log, and the snapshot rebuild.
//
// Resist the temptation to "just write the rows from here". A runner with a
// service key that writes straight to stock_prices would bypass every check we
// built, and the checks are the product.
//
// Run:  deno run --allow-net --allow-env supabase/scripts/nse-fetch-post.ts

import { parseAfxTable } from "../functions/scrape-nse/adapters/afx-nse.ts";

const FEED = Deno.env.get("NSE_PRICES_URL") ?? "https://afx.kwayisi.org/nse/";

// When set, read the board from a FILE that a real browser already fetched
// (scrapers/fetch-nse-html.mjs), instead of fetching it here.
//
// afx does not answer plain fetch() calls. We watched it hang from Supabase's
// edge (150s) AND from a GitHub runner (30s), with an honest bot user agent AND
// with a real Chrome string. Silence, never a status code. What Deno fetch, Node
// fetch and curl all share is a TLS handshake that does not look like a
// browser's, and bot protection drops those before any HTTP is exchanged.
//
// So Chromium does the fetching and this script does the parsing and posting.
// The parser stays here, in one place, tested against a real board.
const HTML_FILE = Deno.env.get("NSE_HTML_FILE");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const CRON_SECRET = Deno.env.get("CRON_SECRET");

if (!SUPABASE_URL || !CRON_SECRET) {
  console.error("SUPABASE_URL and CRON_SECRET must be set.");
  Deno.exit(1);
}

// A real browser string, with the contact URL still in it. Same reasoning as the
// adapter: legitimate crawlers do this, and an agent with the word "bot" in it
// gets pattern-matched by rules that never read the rest of the line.
const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36 " +
    "(+https://fructa.africa; end-of-day reader, 1 request per day)",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "en-GB,en;q=0.9",
};

async function main() {
  let html: string;

  if (HTML_FILE) {
    html = await Deno.readTextFile(HTML_FILE);
    console.log(`read ${html.length} bytes from ${HTML_FILE}`);
  } else {
    // Direct fetch. Kept for local use and for any source that will actually
    // answer one. Against afx from a datacenter, this hangs: see above.
    console.log(`fetching ${FEED}`);
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 30_000);
    try {
      const res = await fetch(FEED, { headers: HEADERS, signal: ctl.signal });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      html = await res.text();
    } catch (e) {
      const aborted = e instanceof Error && e.name === "AbortError";
      throw new Error(
        aborted
          ? `no response from ${FEED} within 30s. The host is dropping this ` +
            "client. Fetch with scrapers/fetch-nse-html.mjs (Chromium) and set " +
            "NSE_HTML_FILE instead."
          : `fetch failed: ${e instanceof Error ? e.message : String(e)}`,
      );
    } finally {
      clearTimeout(timer);
    }
  }

  const rows = parseAfxTable(html);
  console.log(`parsed ${rows.length} rows`);

  // The same floor the adapter enforces. If the runner is ALSO blocked, or afx
  // has moved its layout, fail here and write nothing rather than posting a
  // partial board that would look like a market where half the counters
  // vanished overnight.
  if (rows.length < 40) {
    console.error(
      `only ${rows.length} rows parsed, expected 60 or more. ` +
        "Refusing to post a partial board.",
    );
    Deno.exit(1);
  }

  const res = await fetch(`${SUPABASE_URL}/functions/v1/scrape-nse`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-cron-secret": CRON_SECRET,
    },
    body: JSON.stringify({
      trigger: Deno.env.get("TRIGGER") ?? "cron",
      source: "afx-nse",
      rows,
    }),
  });

  const text = await res.text();
  console.log(`scrape-nse responded ${res.status}: ${text}`);

  // A non-2xx from the ingest endpoint must fail the workflow. A green tick on a
  // run that wrote nothing is worse than a red one, because nobody investigates
  // green.
  if (!res.ok) Deno.exit(1);

  try {
    const j = JSON.parse(text);
    if (typeof j.written === "number" && j.written === 0) {
      console.error("ingest wrote 0 rows. Failing the run so it is visible.");
      Deno.exit(1);
    }
  } catch {
    // Response was not JSON. The status was 2xx, so let it stand.
  }
}

await main();
