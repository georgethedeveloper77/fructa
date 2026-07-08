// import-cma-cis.ts
// Parse a quarterly CMA "Collective Investment Schemes" report into the
// `cma_imports` staging table for admin review, then (with `apply`) promote it
// onto funds.composition/aum_kes + companies.aum_kes/market_share.
//
// Reads the PDF DIRECTLY (no pdftotext needed) — it reconstructs column layout
// from pdfjs text coordinates, then reconciles every composition row against
// its own stated Total (must match within 0.5%) so misparses are flagged, not
// written.
//
//   # test parsing only — no DB, no env, no install:
//   deno run -A supabase/scripts/import-cma-cis.ts stage \
//       --pdf CISReportQ1-2026.pdf --period 2026-03-31 --dry --out cma.json
//
//   # stage to Supabase (env via --env-file):
//   deno run -A --env-file=fructa-admin/.env.local \
//       supabase/scripts/import-cma-cis.ts stage \
//       --pdf CISReportQ1-2026.pdf --period 2026-03-31 \
//       --source https://www.cmarcp.or.ke/.../CISReportQ1-2026.pdf
//
//   # promote reconciled rows onto funds/companies:
//   deno run -A --env-file=fructa-admin/.env.local \
//       supabase/scripts/import-cma-cis.ts apply --period 2026-03-31
//
// Env (either name works): SUPABASE_URL | NEXT_PUBLIC_SUPABASE_URL, and
// SUPABASE_SERVICE_ROLE_KEY (sb_secret_…).

import { createClient } from "npm:@supabase/supabase-js@2";
import { getDocumentProxy } from "npm:unpdf";

// ── CMA Table 18 columns, in PDF order → the 8 canonical app keys ──────────
const COMP_COLUMNS = [
  "cash",           // Cash & Demand Deposits
  "fixed_deposits", // Fixed Deposits
  "listed",         // Listed Securities
  "gok",            // Securities Issued by GoK
  "unlisted",       // Unlisted Securities
  "other_cis",      // Other Collective Investment Schemes
  "offshore",       // Off-shore investments
  "alternative",    // Alternative Investments
] as const;

type FundAum = { scheme: string; fund: string; aum: number };
type CompRow = {
  fund: string;
  byClass: Record<string, number>;
  total: number;
  reconciles: boolean;
};
type Scheme = { name: string; aum: number; marketShare: number };
type Payload = {
  period: string;
  source_url: string | null;
  schemes: Scheme[];
  fund_aum: FundAum[];
  composition: CompRow[];
  stats: { comp_ok: number; comp_review: number };
};

// ── PDF → column-preserving text (replaces `pdftotext -layout`) ────────────
async function extractPdfLayout(bytes: Uint8Array): Promise<string> {
  // unpdf bundles pdfjs with the worker disabled — works headless in Deno.
  const doc = await getDocumentProxy(bytes);

  const out: string[] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const tc = await page.getTextContent();
    type It = { x: number; y: number; w: number; s: string };
    const items: It[] = [];
    // deno-lint-ignore no-explicit-any
    for (const it of tc.items as any[]) {
      const s: string = it.str ?? "";
      if (s === "") continue;
      items.push({ x: it.transform[4], y: it.transform[5], w: it.width ?? 0, s });
    }
    // group items into lines by y, then order by x within a line
    items.sort((a, b) => b.y - a.y || a.x - b.x);
    const lines: It[][] = [];
    let cur: It[] = [];
    let curY = Infinity;
    for (const it of items) {
      if (cur.length && Math.abs(it.y - curY) > 2.5) {
        lines.push(cur);
        cur = [];
      }
      if (!cur.length) curY = it.y;
      cur.push(it);
    }
    if (cur.length) lines.push(cur);

    for (const ln of lines) {
      ln.sort((a, b) => a.x - b.x);
      let s = "";
      let prevEnd: number | null = null;
      for (const it of ln) {
        if (prevEnd !== null) {
          const gap = it.x - prevEnd;
          s += gap > 8 ? "  " : gap > 1.2 ? " " : ""; // ≥2 spaces = column break
        }
        s += it.s;
        prevEnd = it.x + it.w;
      }
      out.push(s);
    }
    out.push(""); // page break
  }
  return out.join("\n");
}

// ── number parsing: "1,234", "(402,587)", "-", "" → number ─────────────────
function num(tok: string): number {
  const t = tok.trim();
  if (t === "" || t === "-") return 0;
  const neg = /^\(.*\)$/.test(t);
  const n = Number(t.replace(/[(),\s]/g, ""));
  if (!Number.isFinite(n)) return NaN;
  return neg ? -n : n;
}

function trailingNumbers(line: string): number[] {
  const toks = line.trim().split(/\s{2,}|\t/).map((s) => s.trim());
  const nums: number[] = [];
  for (let i = toks.length - 1; i >= 0; i--) {
    const t = toks[i];
    if (t === "") continue;
    if (/^\(?-?[\d,]+\.?\d*\)?$/.test(t) || t === "-") {
      const v = num(t);
      if (Number.isFinite(v)) { nums.unshift(v); continue; }
    }
    break;
  }
  return nums;
}

function normName(s: string): string {
  return s.toLowerCase()
    .replace(/\bfund\b/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

// ── Table 1: CIS Market Share ──────────────────────────────────────────────
function parseMarketShare(text: string): Scheme[] {
  const out: Scheme[] = [];
  const seen = new Set<string>();
  const re = /^\s*\d+\.\s+(.+?)\s+([\d,]{6,})\s+([\d.]+)\s*%\s*$/;
  for (const line of text.split("\n")) {
    const m = line.match(re);
    if (!m) continue;
    const name = m[1].trim();
    if (/TOTAL/i.test(name)) continue;
    const key = normName(name);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name, aum: num(m[2]), marketShare: num(m[3]) });
  }
  return out;
}

// ── Tables 11–15: per-fund AUM (clean fund-name list) ──────────────────────
function parseFundAum(text: string): FundAum[] {
  const out: FundAum[] = [];
  const re = /^\s*\d+\.\s+(.+?)\s{2,}(.+?)\s+([\d,]{4,})\s+[\d.]+\s*%?\s*$/;
  for (const line of text.split("\n")) {
    const m = line.match(re);
    if (!m) continue;
    const fund = m[2].trim();
    if (!/fund/i.test(fund)) continue;
    out.push({ scheme: m[1].trim(), fund, aum: num(m[3]) });
  }
  return out;
}

// ── Table 18 (§2.7): per-fund composition, reconciled against Total ────────
function parseComposition(text: string, knownFunds: string[]): CompRow[] {
  const known = knownFunds
    .map((f) => ({ orig: f, n: normName(f) }))
    .filter((k) => k.n.length > 4)
    .sort((a, b) => b.n.length - a.n.length);

  const start = text.search(/Investment Vehicles by Different Funds/i);
  const body = start >= 0 ? text.slice(start) : text;

  const rows: CompRow[] = [];
  for (const raw of body.split("\n")) {
    const line = raw.replace(/\s+$/, "");
    const nl = normName(line);
    const hit = known.find((k) => nl.includes(k.n));
    if (!hit) continue;

    const nums = trailingNumbers(line);
    let byClass: Record<string, number> = {};
    let total = 0;
    let reconciles = false;
    if (nums.length >= 2) {
      total = nums[nums.length - 1];
      if (nums.length === COMP_COLUMNS.length + 1) {
        COMP_COLUMNS.forEach((k, i) => (byClass[k] = nums[i]));
        const sum = COMP_COLUMNS.reduce((a, k) => a + (byClass[k] || 0), 0);
        reconciles = total > 0 && Math.abs(sum - total) / total < 0.005;
      }
    }
    rows.push({ fund: hit.orig, byClass, total, reconciles });
  }

  const seen = new Set<string>();
  const out: CompRow[] = [];
  for (const r of rows) {
    const k = normName(r.fund);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(r);
  }
  return out;
}

export function parseCisReport(
  text: string,
  period: string,
  sourceUrl: string | null,
): Payload {
  const schemes = parseMarketShare(text);
  const fundAum = parseFundAum(text);
  const composition = parseComposition(text, fundAum.map((f) => f.fund));
  return {
    period,
    source_url: sourceUrl,
    schemes,
    fund_aum: fundAum,
    composition,
    stats: {
      comp_ok: composition.filter((c) => c.reconciles).length,
      comp_review: composition.filter((c) => !c.reconciles).length,
    },
  };
}

// ── db ─────────────────────────────────────────────────────────────────────
function db() {
  const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("NEXT_PUBLIC_SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error(
      "Set SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL) + SUPABASE_SERVICE_ROLE_KEY " +
      "— or pass --env-file=fructa-admin/.env.local, or use --dry to skip the DB.",
    );
  }
  return createClient(url, key, { auth: { persistSession: false } });
}

function arg(flag: string): string | undefined {
  const i = Deno.args.indexOf(flag);
  return i >= 0 ? Deno.args[i + 1] : undefined;
}
const has = (flag: string) => Deno.args.includes(flag);

async function loadText(): Promise<string> {
  const pdfPath = arg("--pdf");
  const textPath = arg("--text");
  if (pdfPath) return extractPdfLayout(await Deno.readFile(pdfPath));
  if (textPath) return Deno.readTextFile(textPath);
  console.error("Provide --pdf <file.pdf> or --text <file.txt>");
  Deno.exit(1);
}

async function stage() {
  const period = arg("--period");
  const source = arg("--source") ?? null;
  if (!period) {
    console.error("usage: stage --pdf report.pdf --period YYYY-MM-DD [--source URL] [--dry] [--out f.json]");
    Deno.exit(1);
  }
  const text = await loadText();
  const payload = parseCisReport(text, period, source);
  console.log(
    `Parsed: ${payload.schemes.length} schemes, ${payload.fund_aum.length} fund AUMs, ` +
    `${payload.composition.length} composition rows ` +
    `(${payload.stats.comp_ok} ok / ${payload.stats.comp_review} need review)`,
  );

  const outPath = arg("--out");
  if (outPath) {
    await Deno.writeTextFile(outPath, JSON.stringify(payload, null, 2));
    console.log(`Wrote ${outPath}`);
  }
  if (has("--dry")) {
    console.log("--dry: skipped DB write.");
    // preview a few review rows to eyeball the parse
    for (const c of payload.composition.filter((c) => !c.reconciles).slice(0, 5)) {
      console.log(`  review: ${c.fund} (total ${c.total}, classes ${Object.keys(c.byClass).length})`);
    }
    return;
  }
  const { error } = await db().from("cma_imports").upsert(
    { period, source_url: source, status: "staged", payload },
    { onConflict: "period" },
  );
  if (error) throw error;
  console.log(`Staged for ${period}. Review, then: apply --period ${period}`);
}

async function apply() {
  const period = arg("--period");
  if (!period) { console.error("usage: apply --period YYYY-MM-DD"); Deno.exit(1); }
  const sb = db();

  const { data: row, error } = await sb.from("cma_imports")
    .select("payload,source_url").eq("period", period).maybeSingle();
  if (error) throw error;
  if (!row) { console.error(`No staged import for ${period}`); Deno.exit(1); }
  const p = row.payload as Payload;

  const { data: funds } = await sb.from("funds").select("id,name,company_id");
  // deno-lint-ignore no-explicit-any
  const byName = new Map((funds ?? []).map((f: any) => [normName(f.name), f]));
  const aumByFund = new Map(p.fund_aum.map((f) => [normName(f.fund), f.aum]));

  let applied = 0;
  const unmapped: string[] = [];
  for (const c of p.composition) {
    if (!c.reconciles) continue;
    const f = byName.get(normName(c.fund));
    if (!f) { unmapped.push(c.fund); continue; }
    const { error: e } = await sb.from("funds").update({
      composition: c.byClass,
      aum_kes: aumByFund.get(normName(c.fund)) ?? c.total,
      aum_as_of: period,
      composition_source_url: row.source_url,
    }).eq("id", f.id);
    if (e) { console.warn(`  ${c.fund}: ${e.message}`); continue; }
    applied++;
  }

  const { data: cos } = await sb.from("companies").select("id,name");
  // deno-lint-ignore no-explicit-any
  const coByName = new Map((cos ?? []).map((c: any) => [normName(c.name), c]));
  let coApplied = 0;
  for (const s of p.schemes) {
    const co = coByName.get(normName(s.name));
    if (!co) continue;
    await sb.from("companies").update({
      aum_kes: s.aum, market_share: s.marketShare, aum_as_of: period,
    }).eq("id", co.id);
    coApplied++;
  }

  await sb.from("cma_imports").update({ status: "applied" }).eq("period", period);
  console.log(`Applied composition to ${applied} funds, AUM/share to ${coApplied} companies.`);
  if (unmapped.length) {
    console.log(`Unmapped funds (add to fund-name-map): ${unmapped.join(" · ")}`);
  }
}

if (import.meta.main) {
  const cmd = Deno.args[0];
  if (cmd === "stage") await stage();
  else if (cmd === "apply") await apply();
  else { console.error("commands: stage | apply"); Deno.exit(1); }
}
