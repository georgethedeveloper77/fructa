"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { slugify } from "@/lib/publish";

// Every mutation republishes, same as the funds lane: the app reads the
// snapshot, not these tables.
async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch { /* ignore */ }
}

function refresh(id?: string) {
  revalidatePath("/admin/stocks");
  revalidatePath("/admin");
  if (id) revalidatePath(`/admin/stocks/${id}`);
}

const numOrNull = (v: FormDataEntryValue | null) => {
  const n = Number(v);
  return v === null || v === "" || !Number.isFinite(n) ? null : n;
};
const strOrNull = (v: FormDataEntryValue | null) => {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
};

const SEGMENTS = ["MIM", "AIM", "GEMS"];
const DIV_KINDS = ["interim", "final", "special"];

// Create a listed company. Ticker is the join key the price lane maps on, so it
// is uppercased and required.
export async function addStock(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const ticker = String(formData.get("ticker") ?? "").trim().toUpperCase();
  if (!name || !ticker) return;

  const id = slugify(name);
  if (!id) return;

  const segRaw = strOrNull(formData.get("segment"));
  await supabaseAdmin().from("stocks").insert({
    id,
    ticker,
    name,
    sector: strOrNull(formData.get("sector")),
    segment: segRaw && SEGMENTS.includes(segRaw) ? segRaw : "MIM",
    active: true,
  });
  await republishSnapshot();
  refresh(id);
}

// Full profile edit. Section-scoped: touches ONLY the fields this form carries.
// Dividends and prices are owned by their own writers and never ride here.
export async function updateStock(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const segRaw = strOrNull(formData.get("segment"));
  const sharesRaw = numOrNull(formData.get("shares_outstanding"));

  await supabaseAdmin().from("stocks").update({
    name: String(formData.get("name")),
    ticker: String(formData.get("ticker") ?? "").trim().toUpperCase(),
    sector: strOrNull(formData.get("sector")),
    segment: segRaw && SEGMENTS.includes(segRaw) ? segRaw : null,
    isin: strOrNull(formData.get("isin")),
    about: strOrNull(formData.get("about")),
    logo_url: strOrNull(formData.get("logo_url")),
    brand_color: strOrNull(formData.get("brand_color")),
    website: strOrNull(formData.get("website")),
    ir_url: strOrNull(formData.get("ir_url")),
    listed_on: strOrNull(formData.get("listed_on")),
    // bigint column, so no stray decimals
    shares_outstanding: sharesRaw == null ? null : Math.round(sharesRaw),
  }).eq("id", id);

  await republishSnapshot();
  refresh(id);
}

export async function toggleStockActive(formData: FormData) {
  const id = String(formData.get("id"));
  const value = formData.get("value") === "true";
  if (!id) return;
  await supabaseAdmin().from("stocks").update({ active: value }).eq("id", id);
  await republishSnapshot(); // inactive stocks drop out of the snapshot
  refresh(id);
}

export async function deleteStock(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  // dividends and prices cascade (0047)
  await supabaseAdmin().from("stocks").delete().eq("id", id);
  await republishSnapshot();
  refresh();
}

// ── Dividends ───────────────────────────────────────────────────────────────
// Public data (company announcements / annual reports). Not licence gated, so
// this is the lane that makes a stock page useful with no price feed at all.
// Upserts on (stock_id, financial_year, kind), so re-entering a year corrects
// it rather than duplicating.
export async function saveDividend(formData: FormData) {
  const stock_id = String(formData.get("stock_id"));
  const fy = numOrNull(formData.get("financial_year"));
  const dps = numOrNull(formData.get("dps_kes"));
  const kindRaw = String(formData.get("kind") ?? "final");
  if (!stock_id || fy == null || dps == null || dps <= 0) return;

  const kind = DIV_KINDS.includes(kindRaw) ? kindRaw : "final";

  await supabaseAdmin().from("stock_dividends").upsert({
    stock_id,
    financial_year: Math.round(fy),
    kind,
    dps_kes: dps,
    declared_on: strOrNull(formData.get("declared_on")),
    book_closure: strOrNull(formData.get("book_closure")),
    payment_date: strOrNull(formData.get("payment_date")),
    source_url: strOrNull(formData.get("source_url")),
  }, { onConflict: "stock_id,financial_year,kind" });

  await republishSnapshot();
  refresh(stock_id);
}

export async function deleteDividend(formData: FormData) {
  const id = String(formData.get("id"));
  const stock_id = String(formData.get("stock_id"));
  if (!id) return;
  await supabaseAdmin().from("stock_dividends").delete().eq("id", id);
  await republishSnapshot();
  refresh(stock_id);
}

// ── Dividend bulk import ────────────────────────────────────────────────────
// The stocks equivalent of the funds importer. Dividends are DECLARED, once or
// twice a year at results season, not quoted continuously, so this is the right
// shape for the lane: a CSV you run when the announcements land, not a cron.
//
// Matched on TICKER, which is exact. No fuzzy name matching (contrast the MMF
// lane, where sources use casual labels like "Nabo"), so a row either lands on
// the right company or is reported unmatched. It never guesses.
//
// Format: ticker,financial_year,kind,dps_kes[,payment_date][,source_url]
//   SCOM,2025,final,1.20,2025-08-31,https://...
//   EQTY,2025,interim,0.50

export type DivImportRow = {
  ticker: string;
  financialYear: number | null;
  kind: string;
  dpsKes: number | null;
  paymentDate: string | null;
  sourceUrl: string | null;
};

export type DivMatchRow = {
  stockId: string;
  stockName: string;
  ticker: string;
  financialYear: number;
  kind: string;
  dpsFrom: number | null; // existing value for this (stock, year, kind)
  dpsTo: number;
  paymentDate: string | null;
  sourceUrl: string | null;
};

export type DivPreview = {
  matched: DivMatchRow[];
  unmatched: string[];
  invalid: string[];
};

const DIV_KINDS_IMPORT = ["interim", "final", "special"];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export async function previewDividendImport(
  rows: DivImportRow[],
): Promise<DivPreview> {
  const db = supabaseAdmin();

  const [{ data: stocks }, { data: existing }] = await Promise.all([
    db.from("stocks").select("id,name,ticker"),
    db.from("stock_dividends").select("stock_id,financial_year,kind,dps_kes"),
  ]);

  const byTicker = new Map<string, { id: string; name: string; ticker: string }>();
  for (const s of stocks ?? []) {
    byTicker.set(String(s.ticker).trim().toUpperCase(), {
      id: s.id,
      name: s.name,
      ticker: s.ticker,
    });
  }

  // (stock, year, kind) -> current dps, so the preview shows a real before/after
  const prior = new Map<string, number>();
  for (const d of existing ?? []) {
    prior.set(`${d.stock_id}|${d.financial_year}|${d.kind}`, Number(d.dps_kes));
  }

  const matched: DivMatchRow[] = [];
  const unmatched: string[] = [];
  const invalid: string[] = [];

  for (const r of rows) {
    const key = r.ticker.trim().toUpperCase();
    if (!key) continue;

    // A bad year, kind or amount is called out rather than silently dropped.
    if (
      r.financialYear == null ||
      r.dpsKes == null ||
      r.dpsKes <= 0 ||
      !DIV_KINDS_IMPORT.includes(r.kind)
    ) {
      invalid.push(`${key}: bad year, kind or amount`);
      continue;
    }
    if (r.paymentDate && !ISO_DATE.test(r.paymentDate)) {
      invalid.push(`${key}: payment date must be YYYY-MM-DD`);
      continue;
    }

    const s = byTicker.get(key);
    if (!s) {
      unmatched.push(key);
      continue;
    }

    matched.push({
      stockId: s.id,
      stockName: s.name,
      ticker: s.ticker,
      financialYear: r.financialYear,
      kind: r.kind,
      dpsFrom: prior.get(`${s.id}|${r.financialYear}|${r.kind}`) ?? null,
      dpsTo: r.dpsKes,
      paymentDate: r.paymentDate,
      sourceUrl: r.sourceUrl,
    });
  }

  return { matched, unmatched, invalid };
}

export async function applyDividendImport(
  rows: DivMatchRow[],
): Promise<{ written: number }> {
  if (rows.length === 0) return { written: 0 };

  // Upsert on (stock_id, financial_year, kind): re-importing a corrected
  // announcement fixes the row rather than duplicating it.
  const payload = rows.map((r) => ({
    stock_id: r.stockId,
    financial_year: r.financialYear,
    kind: r.kind,
    dps_kes: r.dpsTo,
    payment_date: r.paymentDate,
    source_url: r.sourceUrl,
  }));

  await supabaseAdmin()
    .from("stock_dividends")
    .upsert(payload, { onConflict: "stock_id,financial_year,kind" });

  await republishSnapshot();
  refresh();
  return { written: payload.length };
}
