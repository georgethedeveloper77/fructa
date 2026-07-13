// scrapers/probe-board.mjs
//
// Which mystocks URL serves the FULL board, without a login?
//
// The first probe proved mystocks is reachable from this runner and quotes SCOM
// at 35.05 (the same price afx quoted, which is a real cross-check: two
// independent sources agreeing beats one source asserting). But it hit a
// SINGLE-STOCK page. Sixty-odd separate page loads every evening is not a
// scraper, it is a nuisance to a host that has been good to us.
//
// So: find the board. Two candidates, and one known trap.
//
// The trap matters. https://live.mystocks.co.ke/price_list/ REDIRECTS TO LOGIN.
// A naive fetch of it returns HTTP 200 and a pile of HTML, and a parser pointed
// at it would find zero rows and report an empty market, or worse, find the
// login page's own stray numbers. So this probe checks the URL we LANDED on, not
// the one we asked for. A 200 is not the same as an answer.
//
// Run: node scrapers/probe-board.mjs

import { chromium } from "playwright";

const CANDIDATES = [
  // Mobile pricelist. Search suggests it is public and carries every counter,
  // including the KPLC preferentials, which is a good sign: a partial board
  // usually drops the odd instruments first.
  { id: "m-pricelist", url: "https://live.mystocks.co.ke/m/pricelist" },

  // The desktop price list. Expected to bounce to /login. Included as the
  // CONTROL: if the redirect detection below does not catch this one, the
  // detection is broken and I do not trust it on the others either.
  { id: "price_list", url: "https://live.mystocks.co.ke/price_list/" },

  // Mobile home, in case the board lives at the root of the mobile edition.
  { id: "m-home", url: "https://live.mystocks.co.ke/m/" },
];

// Tickers we know are on the NSE. Counting how many appear tells us whether we
// have the whole market or a fragment. Deliberately a spread across sectors and
// liquidity, not just the blue chips: a page that shows SCOM and EQTY but not
// EVRD or KURV is a "top movers" widget, not a board.
const KNOWN = [
  "SCOM", "EQTY", "KCB", "EABL", "COOP", "ABSA", "SBIC", "SCBK", "NCBA", "DTK",
  "BAT", "KEGN", "KPLC", "KNRE", "JUB", "CIC", "BRIT", "CTUM", "TOTL", "NMG",
  "KUKZ", "SASN", "WTK", "KAPC", "EVRD", "KURV", "UNGA", "CARB", "BOC", "CGEN",
];

const browser = await chromium.launch();
const ctx = await browser.newContext({
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  locale: "en-GB",
  viewport: { width: 1280, height: 900 },
});

const out = [];

for (const c of CANDIDATES) {
  const page = await ctx.newPage();
  const r = { id: c.id, url: c.url };
  const t0 = Date.now();
  try {
    const res = await page.goto(c.url, {
      waitUntil: "domcontentloaded",
      timeout: 30_000,
    });
    r.status = res?.status() ?? 0;
    r.ms = Date.now() - t0;

    // WHERE DID WE ACTUALLY LAND. Not where we asked to go.
    r.landed = page.url();
    r.bounced = /login|signin|register/i.test(r.landed);

    const html = await page.content();
    r.bytes = html.length;

    // How much of the market is on this page?
    r.tickersFound = KNOWN.filter((t) => new RegExp(`\\b${t}\\b`).test(html));
    r.tickerCount = r.tickersFound.length;

    // The rows, roughly. A real board has one row per counter.
    r.trCount = (html.match(/<tr[\s>]/gi) ?? []).length;

    // SCOM's price, to check against the 35.05 that both afx and the mystocks
    // single-stock page gave us. If this board disagrees, do not paper over it:
    // that is a finding, and it means one of them is not an end-of-day close.
    const m = html.match(/\bSCOM\b[\s\S]{0,300}?(\d{1,3}\.\d{2})/i);
    r.scomPrice = m ? m[1] : null;

    // The date the board claims to be. A board with no date is a board we cannot
    // check for staleness, and staleness is the failure mode that does not
    // announce itself.
    const d = html.match(
      /\b(\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+20\d{2})\b/i,
    );
    r.dateOnPage = d ? d[1] : null;
  } catch (e) {
    r.status = 0;
    r.ms = Date.now() - t0;
    r.error = e instanceof Error ? e.message.split("\n")[0].slice(0, 90) : String(e);
  } finally {
    await page.close();
  }
  out.push(r);
}

await browser.close();

console.log("");
console.log("BOARD PROBE");
console.log("===========");
for (const r of out) {
  console.log("");
  console.log(`${r.id}  ${r.url}`);
  const ok = r.status >= 200 && r.status < 400;
  console.log(`   reachable   : ${ok ? `yes (HTTP ${r.status}, ${r.ms}ms)` : `NO  ${r.error ?? r.status}`}`);
  if (!ok) continue;
  console.log(`   landed on   : ${r.landed}`);
  console.log(`   auth wall   : ${r.bounced ? "YES, bounced to a login. Unusable." : "no"}`);
  console.log(`   bytes       : ${r.bytes}`);
  console.log(`   table rows  : ${r.trCount}`);
  console.log(`   tickers     : ${r.tickerCount} of ${KNOWN.length} known`);
  console.log(`   SCOM price  : ${r.scomPrice ?? "none found"}`);
  console.log(`   date on page: ${r.dateOnPage ?? "NONE, cannot check staleness"}`);
  if (r.tickerCount > 0 && r.tickerCount < 20) {
    console.log(`   missing     : ${KNOWN.filter((t) => !r.tickersFound.includes(t)).join(" ")}`);
  }
}

console.log("");
console.log("WHAT WE WANT: no auth wall, 20+ known tickers, a SCOM price near");
console.log("35.05, and a date from this week. Anything less is not the board.");
console.log("");

const winner = out.find(
  (r) => r.status >= 200 && r.status < 400 && !r.bounced && r.tickerCount >= 20,
);
if (!winner) {
  console.error("No candidate serves a full public board. Do not write a parser yet.");
  process.exit(1);
}
console.log(`BOARD FOUND: ${winner.id} at ${winner.landed}`);
console.log(`  ${winner.tickerCount} tickers, SCOM at ${winner.scomPrice}, dated ${winner.dateOnPage}`);
