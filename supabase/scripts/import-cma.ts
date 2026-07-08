// import-cma.ts
// Seeds the DIRECTORY from the Capital Markets Authority licensee registry —
// the official source for scheme names, their constituent funds, the fund
// TYPE (money market / fixed income / equity / balanced), and websites.
//
//   Source (official): https://licensees.cma.or.ke/licenses/15/  (CIS list)
//
// It does NOT touch rates — current_rate is left to the rate sources (Etica /
// press CSV / manual). Upserts by id, so re-running is safe and never clobbers
// a rate. Company duplicates (CMA scheme vs. the manager-slug backfill) can be
// merged in the admin Companies page.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//     deno run --allow-env --allow-net import-cma.ts [--dry-run] [--all]
//
//   --dry-run  parse + print, write nothing (verify the parse first!)
//   --all      also import equity/balanced funds (default: yield vehicles only)
//
// ⚠️  VERIFY the parse against the live page before trusting it — CMA markup can
//     change. --dry-run prints exactly what would be written.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { DOMParser, type Element } from "jsr:@b-fuze/deno-dom";

const DRY = Deno.args.includes("--dry-run");
const ALL = Deno.args.includes("--all");
const URL =
  Deno.env.get("CMA_LICENSEES_URL") ?? "https://licensees.cma.or.ke/licenses/15/";

const slug = (s: string) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

// Fund name → real category. The extended types (equity/balanced/islamic/reit)
// only emit with --full, once the app can label them.
const SAFE = new Set(["mmf_kes", "mmf_usd", "bond"]);
function categoryOf(name: string): { category: string; currency: string } | null {
  const n = name.toLowerCase();
  const usd = /\busd\b|dollar|\$/.test(n);
  const ccy = usd ? "USD" : "KES";
  let category: string | null = null;
  if (/shari|islamic|halal/.test(n)) category = "islamic";
  else if (/reit|real estate|property/.test(n)) category = "reit";
  else if (/money market|enhanced yield|liquid/.test(n)) category = usd ? "mmf_usd" : "mmf_kes";
  else if (/fixed income|bond/.test(n)) category = "bond";
  else if (/balanced/.test(n)) category = "balanced";
  else if (/equity|growth|aggressive/.test(n)) category = "equity";
  if (!category) return null;
  if (!ALL && !SAFE.has(category)) return null; // extended types need --full
  return { category, currency: ccy };
}

// Manager class from the company name (bank-owned / insurance-owned / independent).
const BANKS = /\babsa\b|\bkcb\b|i\s*&\s*m|i and m|stanbic|standard chartered|co-?op|cooperative|\bequity\b bank|\bncba\b|\bdtb\b|family bank|\bfcb\b|sidian|housing finance|national bank|gulf african|\bhf\b/;
const INSURERS = /britam|\bcic\b|jubilee|madison|icea|old mutual|sanlam|metropolitan|\bcanon\b|apollo|pioneer|liberty|geminia|first assurance|heritage|kenya orient/;
function managerClass(name: string): string {
  const n = name.toLowerCase();
  if (BANKS.test(n)) return "bank";
  if (INSURERS.test(n)) return "insurance";
  return "independent";
}

// Strip the scheme suffix to a company-ish name.
function companyName(scheme: string): string {
  return scheme.replace(/\s+(unit trust|umbrella)?\s*scheme\s*$/i, "").trim() || scheme;
}

interface ParsedFund {
  name: string;
  scheme: string;
  website: string | null;
}

function parse(html: string): ParsedFund[] {
  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) return [];
  const out: ParsedFund[] = [];
  const rows = [...doc.querySelectorAll("table tr")] as Element[];
  for (const row of rows) {
    const cells = [...row.querySelectorAll("td")] as Element[];
    if (cells.length < 2) continue; // header / empty

    const nameCell = cells[0];
    // Scheme title = the cell's first strong/bold text, else its first line.
    const strong = nameCell.querySelector("strong,b");
    const scheme =
      (strong?.textContent ?? nameCell.textContent ?? "").split("\n")[0].trim();
    if (!scheme) continue;

    // Website = first link in the row, else any cell text that looks like a URL.
    const link = row.querySelector('a[href^="http"]') as Element | null;
    let website = link?.getAttribute("href") ?? null;
    if (!website) {
      const m = row.textContent?.match(/https?:\/\/\S+/);
      website = m ? m[0] : null;
    }

    // Constituent funds = the bullet list; if none, the scheme row IS a fund.
    const lis = [...nameCell.querySelectorAll("li")] as Element[];
    const funds = lis.length
      ? lis.map((li) => li.textContent.replace(/[;.]+$/, "").trim()).filter(Boolean)
      : /fund/i.test(scheme)
      ? [scheme]
      : [];

    for (const f of funds) out.push({ name: f, scheme, website });
  }
  return out;
}

async function main() {
  const supaUrl = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supaUrl || !key) {
    console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
    Deno.exit(1);
  }

  const res = await fetch(URL, {
    headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
  });
  if (!res.ok) {
    console.error(`CMA fetch failed: HTTP ${res.status}`);
    Deno.exit(1);
  }
  const parsed = parse(await res.text());
  if (parsed.length === 0) {
    console.error("Parsed 0 funds — the page markup likely changed. Check --dry-run output.");
    Deno.exit(1);
  }

  const companies = new Map<string, { id: string; name: string; website: string | null; manager_class: string }>();
  const funds: Record<string, unknown>[] = [];
  let skipped = 0;

  for (const p of parsed) {
    const cat = categoryOf(p.name);
    if (!cat) { skipped++; continue; }

    const coName = companyName(p.scheme);
    const coId = slug(coName);
    companies.set(coId, { id: coId, name: coName, website: p.website, manager_class: managerClass(coName) });

    funds.push({
      id: slug(p.name),
      name: p.name.replace(/\s+/g, " ").trim(),
      manager: coName,
      category: cat.category,
      currency: cat.currency,
      company_id: coId,
      site_url: p.website,
      kind: "fund",
    });
  }

  console.log(`Parsed ${parsed.length} funds → ${funds.length} funds, ${companies.size} companies (${skipped} skipped${ALL ? "" : "; extended types need --full"})`);

  if (DRY) {
    for (const f of funds) console.log(`  ${f.category.padEnd(8)} ${f.name}  (${f.company_id})`);
    console.log("\n--dry-run: nothing written.");
    return;
  }

  const db = createClient(supaUrl, key, { auth: { persistSession: false } });

  // Companies first (funds FK company_id). Upsert preserves brand_color/logo.
  const { error: cErr } = await db
    .from("companies")
    .upsert([...companies.values()].map((c) => ({
      id: c.id, name: c.name, website: c.website,
      type: c.manager_class === "insurance" ? "fund_manager" : "fund_manager",
      manager_class: c.manager_class,
    })), {
      onConflict: "id",
      ignoreDuplicates: false,
    });
  if (cErr) console.error(`companies upsert: ${cErr.message}`);

  // Funds — current_rate/status omitted, so existing rates are preserved.
  const { error: fErr } = await db
    .from("funds")
    .upsert(funds, { onConflict: "id", ignoreDuplicates: false });
  if (fErr) console.error(`funds upsert: ${fErr.message}`);

  console.log(`Wrote ${companies.size} companies, ${funds.length} funds. Re-run publish-snapshot to ship.`);
}

if (import.meta.main) await main();
