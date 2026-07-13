// scrapers/dump-board.mjs
//
// Print the mystocks pricelist table EXACTLY as it is, so the adapter can be
// written from fact instead of from a guess about column order.
//
// This exists because the last NSE parser in this repo (nse-price-table.ts) was
// a positional guesser: it assumed column 3 was the price because column 3 looked
// like a price. It is dead code now. A parser that counts columns breaks silently
// the day a site inserts a "Change %" column, and it does not break by throwing,
// it breaks by reading the wrong number and storing it as a price.
//
// So: read the HEADERS, and let the adapter find its columns BY NAME. To do that
// I need to know what the headers actually say. Hence this.
//
// It also uploads the raw HTML as an artifact, because a 28KB page is small
// enough to keep and a saved fixture is how the parser gets a regression test
// later.
//
// Run: node scrapers/dump-board.mjs

import { chromium } from "playwright";
import { writeFileSync } from "node:fs";

const URL = "https://live.mystocks.co.ke/m/pricelist";
const OUT = process.env.BOARD_HTML_FILE ?? "/tmp/board.html";

const browser = await chromium.launch();
const ctx = await browser.newContext({
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  locale: "en-GB",
});
const page = await ctx.newPage();

await page.goto(URL, { waitUntil: "domcontentloaded", timeout: 30_000 });
await page.waitForSelector("table", { timeout: 15_000 });

const html = await page.content();
writeFileSync(OUT, html, "utf8");
console.log(`saved ${html.length} bytes to ${OUT}`);

// Every table on the page, with its shape. The board is the one with ~60 rows;
// the others are navigation and index widgets. Print them all rather than
// assuming which is which: assuming which is which is the whole class of bug
// this script exists to prevent.
const tables = await page.$$eval("table", (els) =>
  els.map((t, i) => {
    const rows = [...t.querySelectorAll("tr")];
    return {
      index: i,
      rowCount: rows.length,
      rows: rows.slice(0, 6).map((r) =>
        [...r.querySelectorAll("th,td")].map((c) =>
          (c.textContent ?? "").replace(/\s+/g, " ").trim()
        )
      ),
    };
  })
);

console.log("");
console.log("TABLES ON THE PAGE");
console.log("==================");
for (const t of tables) {
  console.log("");
  console.log(`table[${t.index}]  ${t.rowCount} rows`);
  for (const r of t.rows) {
    console.log(`   ${JSON.stringify(r)}`);
  }
}

// Now find the board specifically, and show SCOM's own row in full. This is the
// row the adapter will live or die on, so look at it directly.
console.log("");
console.log("THE SCOM ROW, WHEREVER IT IS");
console.log("============================");
const scom = await page.$$eval("tr", (rows) =>
  rows
    .filter((r) => /\bSCOM\b|Safaricom/i.test(r.textContent ?? ""))
    .map((r) => ({
      cells: [...r.querySelectorAll("th,td")].map((c) =>
        (c.textContent ?? "").replace(/\s+/g, " ").trim()
      ),
      // The ticker is often a link, and a link is a far more reliable place to
      // read it from than the visible text, which may be a company name.
      links: [...r.querySelectorAll("a")].map((a) => a.getAttribute("href")),
    }))
);
for (const r of scom) {
  console.log(`   cells: ${JSON.stringify(r.cells)}`);
  console.log(`   links: ${JSON.stringify(r.links)}`);
}

await browser.close();
