import type { SourceAdapter, SourceRow } from "../../_shared/types.ts";
import { SERRARI_KES_MMF_MAP, normalize } from "./fund-name-map.ts";

// Serrari (serrarigroup.com/ke/mmf) aggregates KES money-market EAR figures for
// ~27 funds, server-rendered in a single <table>. This is a THIRD-PARTY,
// DERIVED source (their computed effective annual rate, not the manager's
// published figure) and a competitor product — treat it as a cross-check /
// fallback lane, keep the fetch to the once-daily cron, and attribute the
// source in provenance (source: "serrari-mmf"). Confirm robots.txt / ToS
// before leaving this enabled long-term.
//
// The page uses non-official casual labels ("Nabo", "Orient Kasha"). We map
// each to its OFFICIAL CMA fund name via SERRARI_KES_MMF_MAP, then emit that
// name so the aggregator's central NAME_MAP resolves it to a fund_id. Labels
// with no alias are emitted raw and surface as `unmapped` for the admin.
//
// WARNING: the table markup is heuristic. Columns are [#, Company, Annual
// Yield, Min. Investment, News]. If Serrari restructures the table, the row
// parse throws and the aggregator logs it for that run — adjust the anchors.

const TABLE_RE = /<table[^>]*min-w-\[700px\][^>]*>([\s\S]*?)<\/table>/i;
const ROW_RE = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
const CELL_RE = /<td[^>]*>([\s\S]*?)<\/td>/gi;

function stripTags(html: string): string {
  return html
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&#39;|&rsquo;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function cells(rowHtml: string): string[] {
  const out: string[] = [];
  for (const m of rowHtml.matchAll(CELL_RE)) out.push(stripTags(m[1]));
  return out;
}

// A company cell may carry a "Top"/"Best" badge and a logo; keep just the name.
function cleanCompany(s: string): string {
  return s.replace(/\b(Top|Best|New)\b/gi, "").replace(/\s+/g, " ").trim();
}

function parsePct(s: string): number | null {
  const m = s.match(/(\d{1,2}(?:\.\d{1,2})?)\s*%/);
  const v = m ? Number(m[1]) : NaN;
  return Number.isFinite(v) && v > 0 && v < 30 ? v : null;
}

export function serrariMmfAdapter(url: string): SourceAdapter {
  return {
    id: "serrari-mmf",
    async fetchRows(): Promise<SourceRow[]> {
      const res = await fetch(url, {
        headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
      });
      if (!res.ok) throw new Error(`serrari HTTP ${res.status}`);
      const html = await res.text();

      const table = html.match(TABLE_RE)?.[1];
      if (!table) throw new Error("serrari: funds table not found (layout changed?)");

      const rows: SourceRow[] = [];
      for (const rm of table.matchAll(ROW_RE)) {
        const c = cells(rm[1]);
        if (c.length < 4) continue; // header row (<th>) yields no <td>, and sub-rows are skipped
        const company = cleanCompany(c[1]);
        const rate = parsePct(c[2]);
        if (!company || rate == null) continue;

        // Resolve casual label -> official CMA name; emit raw label if unknown
        // so the aggregator records it as unmapped.
        const official = SERRARI_KES_MMF_MAP[normalize(company)] ?? company;
        rows.push({ name: official, rate, currency: "KES" });
      }

      if (rows.length === 0) throw new Error("serrari: no rows parsed (check fixture)");
      return rows;
    },
  };
}
