// scrapers/probe-sources.mjs
//
// Which NSE price sources can we actually reach, and are they actually current?
//
// Run this INSTEAD OF GUESSING. It writes nothing and touches no database. It
// exists because we have now burned two rounds on a source that silently drops
// our connection, and the next round should start from evidence.
//
// It answers three questions per source, in this order, because a No at any step
// makes the later steps irrelevant:
//
//   1. REACHABLE?  Does it answer a real browser from a datacenter IP at all?
//   2. HAS THE DATA? Is SCOM on the page, with a number next to it?
//   3. IS IT FRESH?  Does that number look like this week, not 2020?
//
// Question 3 is not paranoia. african-markets.com passed every structural check
// we had while serving dividend dates from 2020. A source that is confidently
// STALE is more dangerous than one that is honestly blocked: the blocked one
// fails loudly, the stale one publishes wrong numbers to users forever.
//
// Run: node scrapers/probe-sources.mjs

import { chromium } from "playwright";

const SOURCES = [
  // The incumbent. Included as the control: if this now passes, the TLS
  // fingerprint theory was right and nothing else here is needed.
  { id: "afx-nse", url: "https://afx.kwayisi.org/nse/" },
  { id: "afx-scom", url: "https://afx.kwayisi.org/nse/scom.html" },

  // Kenyan, and it quoted SCOM at 34.20 on the same day afx did, which is a
  // point in its favour: two independent sources agreeing is worth more than one
  // source asserting.
  { id: "mystocks", url: "https://live.mystocks.co.ke/stock=SCOM" },

  // The exchange itself. The daily PDF is image-only (we tested: 0 characters,
  // OCR misread 2026 as 2025 on dividend dates), but the site may carry an HTML
  // board that the PDF does not.
  { id: "nse-official", url: "https://www.nse.co.ke/" },

  // Prices may be fine even though its DIVIDEND data was three years stale. Kept
  // in the probe precisely so that judgement is made on evidence, not on a bad
  // memory of one bad table.
  { id: "african-markets", url: "https://african-markets.com/en/stock-markets/nse" },
];

// Any four-figure or better price next to SCOM. Safaricom trades in the tens of
// shillings, so this deliberately does NOT assert a range: a source quoting a
// wildly wrong number is a finding, not something to filter out.
const PRICE_NEAR_SCOM = /SCOM[\s\S]{0,400}?(\d{1,3}\.\d{2})/i;

const browser = await chromium.launch();
const ctx = await browser.newContext({
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  locale: "en-GB",
  viewport: { width: 1280, height: 900 },
});

const results = [];

for (const s of SOURCES) {
  const t0 = Date.now();
  const row = { id: s.id, url: s.url };
  const page = await ctx.newPage();
  try {
    const res = await page.goto(s.url, {
      waitUntil: "domcontentloaded",
      timeout: 30_000,
    });
    row.status = res?.status() ?? 0;
    row.ms = Date.now() - t0;

    const html = await page.content();
    row.bytes = html.length;
    row.scom = /\bSCOM\b/i.test(html) || /Safaricom/i.test(html);
    row.tables = (html.match(/<table/gi) ?? []).length;

    const m = html.match(PRICE_NEAR_SCOM);
    row.samplePrice = m ? m[1] : null;

    // Freshness. A source that prints a date is a source we can check. One that
    // does not is one we would be trusting blind.
    const year = html.match(/\b20(2[4-9]|3\d)\b/g) ?? [];
    row.yearsSeen = [...new Set(year)].sort().slice(-3);
  } catch (e) {
    row.status = 0;
    row.ms = Date.now() - t0;
    row.error = e instanceof Error ? e.message.split("\n")[0].slice(0, 90) : String(e);
  } finally {
    await page.close();
  }
  results.push(row);
}

await browser.close();

console.log("");
console.log("SOURCE PROBE");
console.log("============");
for (const r of results) {
  const ok = r.status >= 200 && r.status < 400;
  console.log("");
  console.log(`${r.id}  ${r.url}`);
  console.log(`   reachable : ${ok ? `yes (HTTP ${r.status}, ${r.ms}ms)` : `NO  ${r.error ?? `HTTP ${r.status}`}`}`);
  if (!ok) continue;
  console.log(`   bytes     : ${r.bytes}`);
  console.log(`   tables    : ${r.tables}`);
  console.log(`   has SCOM  : ${r.scom ? "yes" : "NO, this is not the board"}`);
  console.log(`   price near SCOM : ${r.samplePrice ?? "none found"}`);
  console.log(`   years on page   : ${r.yearsSeen.join(", ") || "none"}`);
}

console.log("");
console.log("READ IT LIKE THIS:");
console.log("  reachable NO            -> blocked. Do not write a parser for it.");
console.log("  has SCOM NO             -> we got a page, but not the board.");
console.log("  years on page all old   -> STALE. The most dangerous outcome:");
console.log("                             it will parse cleanly and be wrong.");
console.log("  reachable + SCOM + this year -> candidate. Verify the price by");
console.log("                             hand against a second source, then");
console.log("                             write the adapter.");
console.log("");

const usable = results.filter((r) => r.status >= 200 && r.status < 400 && r.scom);
if (usable.length === 0) {
  console.error("No source is both reachable and carrying the board.");
  process.exit(1);
}
console.log(`${usable.length} candidate source(s): ${usable.map((r) => r.id).join(", ")}`);
