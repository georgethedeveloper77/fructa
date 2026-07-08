import type { SourceAdapter, SourceRow } from "../../_shared/types.ts";

// Weekly MMF backbone from a CSV you publish (Sheet → File → Share → Publish to
// web → CSV). Set PRESS_MMF_CSV_URL to that pub?output=csv link.
//
// Columns: name,rate[,currency][,as_of]  — currency (KES/USD) and as_of
// (YYYY-MM-DD) are optional and position-independent among the trailing cells.
// A per-row as_of overrides the run date, so the sheet's own date is respected.
//   Cytonn Money Market Fund,11.50,,2026-07-03
//   Etica Dollar Fund,6.45,USD

const DATE = /^\d{4}-\d{2}-\d{2}$/;

function parseCsv(text: string): SourceRow[] {
  const rows: SourceRow[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const cols = line.split(/[,\t]/).map((c) => c.trim().replace(/^"|"$/g, ""));
    if (cols.length < 2) continue;
    const name = cols[0];
    const rate = Number(String(cols[1]).replace(/[^0-9.]/g, ""));
    if (!name || !Number.isFinite(rate) || rate <= 0) continue; // skips header/blank

    let currency: "KES" | "USD" = "KES";
    let asOf: string | undefined;
    for (const extra of cols.slice(2)) {
      if (DATE.test(extra)) asOf = extra;
      else if (/usd/i.test(extra)) currency = "USD";
    }
    rows.push({ name, rate, currency, asOf });
  }
  return rows;
}

export function pressMmfAdapter(csvUrl: string): SourceAdapter {
  return {
    id: "press-mmf",
    async fetchRows(): Promise<SourceRow[]> {
      const res = await fetch(csvUrl, {
        headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
      });
      if (!res.ok) throw new Error(`press-mmf HTTP ${res.status}`);
      const rows = parseCsv(await res.text());
      if (rows.length === 0) throw new Error("press-mmf: no rows parsed (check CSV)");
      return rows;
    },
  };
}
