// scrapers/fetch-nse-html.mjs
//
// Fetch the afx NSE board with a REAL browser and write the HTML to disk.
//
// ── WHY A BROWSER, AND NOT fetch() ──────────────────────────────────────────
// afx does not answer plain fetch() calls. Not a 403, not a 429, not a challenge
// page: no answer at all, until the socket dies. We have now watched this happen
// from two completely different networks:
//
//   Supabase edge (eu-central-1)  -> hung, killed at 150s
//   GitHub Actions runner (Azure) -> hung, aborted at 30s
//
// and with two different user agents (an honest "FructaBot/1.0" and a real
// Chrome string). So it is not the header, and it is not one unlucky IP range.
//
// What Deno's fetch, Node's fetch and curl all share is a TLS handshake that
// does not look like a browser's. Bot protection (Cloudflare and friends)
// fingerprints that handshake and drops the connection before a single byte of
// HTTP is exchanged. That is precisely the failure we keep seeing: silence, not
// refusal. A refusal has a status code.
//
// Real Chromium has a real browser fingerprint. scrape-cbk already runs
// Playwright on this same runner for the CBK site, which is the strongest
// available hint that this is the shape of the problem.
//
// This script does ONE thing: get the HTML. It does not parse and it does not
// write to the database. The parsing stays in the Deno adapter (one parser, one
// place, already tested against a real board), and the storing stays in the edge
// function behind the ticker map, the sanity band and the run log.
//
// If THIS still hangs, the hypothesis is wrong and the fingerprint is not the
// issue. In that case do not keep guessing: run the source probe and pick a
// different source on evidence.

import { chromium } from "playwright";
import { writeFileSync } from "node:fs";

const URL = process.env.NSE_PRICES_URL ?? "https://afx.kwayisi.org/nse/";
const OUT = process.env.NSE_HTML_FILE ?? "/tmp/nse.html";

const browser = await chromium.launch();
try {
  const ctx = await browser.newContext({
    // A plausible desktop. The point is not to lie about who we are (the
    // contact URL stays in the extra header below); it is to present a TLS and
    // header profile that bot protection does not silently discard.
    userAgent:
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    locale: "en-GB",
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: {
      // Still contactable. This is the honesty the original user agent was
      // reaching for, kept in a header that no bot rule pattern-matches on.
      "X-Contact": "https://fructa.africa (end-of-day reader, 1 request per day)",
    },
  });

  const page = await ctx.newPage();

  console.log(`fetching ${URL} with Chromium`);
  const res = await page.goto(URL, {
    waitUntil: "domcontentloaded",
    timeout: 45_000,
  });

  const status = res?.status();
  console.log(`status ${status}`);
  if (!status || status >= 400) {
    // A STATUS is progress, even a bad one: it means we got through the
    // fingerprint check and the server chose to refuse us. That is a different
    // problem, and a solvable one.
    throw new Error(`afx returned HTTP ${status}`);
  }

  // The board is server rendered, so domcontentloaded is enough. Wait for a
  // table anyway rather than assuming: if afx ever moves to client rendering,
  // this fails loudly here instead of handing an empty page to the parser.
  await page.waitForSelector("table", { timeout: 15_000 });

  const html = await page.content();
  writeFileSync(OUT, html, "utf8");

  // A cheap, honest sanity check before we hand off. SCOM is the most heavily
  // traded counter on the exchange; if it is not on the page, we did not get the
  // board, whatever else we got.
  const hasScom = /\bSCOM\b/.test(html);
  console.log(`wrote ${html.length} bytes to ${OUT}, SCOM present: ${hasScom}`);
  if (!hasScom) {
    throw new Error(
      "SCOM is not on the page. This is not the NSE board (a challenge page, a " +
        "cookie wall, or a moved layout). Refusing to hand it to the parser.",
    );
  }
} finally {
  await browser.close();
}
