import { DOMParser } from "https://deno.land/x/deno_dom@v0.1.45/deno-dom-wasm.ts";
import type { SourceAdapter, SourceRow } from "../../_shared/types.ts";

// ─────────────────────────────────────────────────────────────────────────
// Source-AGNOSTIC adapter. It parses a server-rendered HTML table of
// (fund name, yield) rows into SourceRow[]. The source URL is configuration
// (env), NOT hard-coded — so which site this points at is your decision,
// made AFTER you've checked that site's robots.txt and terms of service.
//
// ⚠️  VERIFY BEFORE TRUSTING: I could not run the real Deno fetch here, so the
//     row/column extraction below is a reasonable default, not confirmed
//     against live HTML. Test it against a saved fixture first:
//
//       deno run --allow-read scripts/test-adapter.ts fixture.html
//
//     If the source turns out to be client-rendered (no table in the raw
//     HTML a server-side fetch receives), parse its embedded JSON
//     (e.g. a __NEXT_DATA__ script) instead — or drop it in favour of the
//     first-party sources (CBK, fund fact sheets).
// ─────────────────────────────────────────────────────────────────────────

const PERCENT = /(\d{1,2}(?:\.\d{1,2})?)\s*%/;

export function parseTable(html: string, currency: "KES" | "USD"): SourceRow[] {
  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) throw new Error("failed to parse HTML");

  const rows: SourceRow[] = [];
  for (const tr of doc.querySelectorAll("table tr")) {
    const cells = [...(tr as any).querySelectorAll("td")].map((c) => c.textContent.trim());
    if (cells.length < 2) continue; // header / spacer rows

    // rate = first cell that reads like a percentage
    const rateCell = cells.find((c) => PERCENT.test(c));
    if (!rateCell) continue;
    const rate = parseFloat(rateCell.match(PERCENT)![1]);

    // name = first non-numeric, non-percent text cell
    const name = cells.find((c) => c && !/^\d/.test(c) && !PERCENT.test(c));
    if (!name) continue;

    rows.push({ name, rate, currency });
  }
  return rows;
}

export function industryTableAdapter(sourceUrl: string, currency: "KES" | "USD"): SourceAdapter {
  return {
    id: `industry-table-${currency.toLowerCase()}`,
    async fetchRows(): Promise<SourceRow[]> {
      const res = await fetch(sourceUrl, {
        headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
      });
      if (!res.ok) throw new Error(`source returned ${res.status}`);
      return parseTable(await res.text(), currency);
    },
  };
}
