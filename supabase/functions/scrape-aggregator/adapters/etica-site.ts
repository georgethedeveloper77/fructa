import type { SourceAdapter, SourceRow } from "../../_shared/types.ts";

// Etica publishes its official effective annual yield (EAY) server-rendered on
// its site (e.g. ~10.68% for the KES MMF). Per-provider fact sheet, not the
// press aggregate — so the headline vs effective distinction is exact.
//
// ⚠️  VERIFY: the two regexes below are heuristics. Save the page HTML to a
//     fixture and confirm they pull the right EAY figures; adjust the anchors
//     if the layout changes. Throwing is fine — the aggregator logs it per run.

// Find a percentage (e.g. "10.68%") appearing near a keyword.
function eayNear(html: string, anchor: RegExp): number | null {
  const m = html.match(anchor);
  if (!m || m.index == null) return null;
  const window = html.slice(m.index, m.index + 400);
  const pct = window.match(/(\d{1,2}(?:\.\d{1,2})?)\s*%/);
  const v = pct ? Number(pct[1]) : NaN;
  return Number.isFinite(v) && v > 0 && v < 30 ? v : null;
}

export function eticaSiteAdapter(url: string): SourceAdapter {
  return {
    id: "etica-site",
    async fetchRows(): Promise<SourceRow[]> {
      const res = await fetch(url, {
        headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
      });
      if (!res.ok) throw new Error(`etica HTTP ${res.status}`);
      const html = await res.text();

      const rows: SourceRow[] = [];
      const kes = eayNear(html, /money\s*market|MMF/i);
      if (kes != null) rows.push({ name: "Etica Money Market", rate: kes, currency: "KES" });
      const usd = eayNear(html, /dollar|USD/i);
      if (usd != null) rows.push({ name: "Etica Dollar Fund", rate: usd, currency: "USD" });

      if (rows.length === 0) throw new Error("etica: no EAY parsed (check fixture)");
      return rows;
    },
  };
}
