"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { slugify } from "@/lib/publish";

// Manual changes must reach the app, so every rate/visibility mutation
// re-publishes the snapshot. Non-fatal: a hiccup shouldn't fail the edit.
async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch { /* ignore */ }
}

function refresh(id?: string) {
  revalidatePath("/admin/funds");
  revalidatePath("/admin/companies");
  revalidatePath("/admin/sources");
  revalidatePath("/admin");
  if (id) revalidatePath(`/admin/funds/${id}`);
}

const numOrNull = (v: FormDataEntryValue | null) => {
  const n = Number(v);
  return v === null || v === "" || !Number.isFinite(n) ? null : n;
};
const strOrNull = (v: FormDataEntryValue | null) => {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
};

const FUND_TYPES = ["mmf", "fixed_income", "equity", "balanced", "special"];
const CURRENCIES = ["KES", "USD", "GBP", "EUR", "ZAR"];
const BENCHMARK_KEYS = ["tbill_91", "tbill_182", "tbill_364", "cbr"];

// Create a fund under a company. manager defaults to the company's name.
export async function addFund(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const company_id = strOrNull(formData.get("company_id"));
  const fund_type = String(formData.get("fund_type") ?? "");
  const currency = String(formData.get("currency") ?? "KES");
  if (!name || !company_id || !FUND_TYPES.includes(fund_type)) return;

  const db = supabaseAdmin();
  const { data: co } = await db.from("companies").select("name").eq("id", company_id).single();
  const id = slugify(name);
  if (!id) return;

  await db.from("funds").insert({
    id,
    name,
    manager: co?.name ?? name,
    company_id,
    fund_type,
    currency: CURRENCIES.includes(currency) ? currency : "KES",
    kind: "fund",
    status: "live",
    retail: true,
    min_invest: numOrNull(formData.get("min_invest")),
    mgmt_fee: numOrNull(formData.get("mgmt_fee")),
  });
  await republishSnapshot();
  refresh(id);
}

// Manual rate override: append to history (source=manual) + set current_rate.
export async function setRate(formData: FormData) {
  const id = String(formData.get("id"));
  const rate = Number(formData.get("rate"));
  if (!id || !Number.isFinite(rate) || rate <= 0 || rate >= 30) return;

  const db = supabaseAdmin();
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT
  await db.from("rate_history").upsert(
    { fund_id: id, rate, as_of: asOf, source: "manual" },
    { onConflict: "fund_id,as_of" },
  );
  await db.from("funds").update({ current_rate: rate, status: "live" }).eq("id", id);
  await republishSnapshot();
  refresh(id);
}

export async function toggleFlag(formData: FormData) {
  const id = String(formData.get("id"));
  const field = String(formData.get("field")); // "verified" | "featured"
  if (field !== "verified" && field !== "featured") return;
  const value = formData.get("value") === "true";
  await supabaseAdmin().from("funds").update({ [field]: value }).eq("id", id);
  if (field === "featured") await republishSnapshot();
  refresh(id);
}

export async function setStatus(formData: FormData) {
  const id = String(formData.get("id"));
  const status = String(formData.get("status"));
  if (!["live", "stale", "hidden"].includes(status)) return;
  await supabaseAdmin().from("funds").update({ status }).eq("id", id);
  await republishSnapshot(); // hidden funds drop out of the snapshot
  refresh(id);
}

// Retail flag: whether the fund shows in the consumer app's lists.
export async function toggleRetail(formData: FormData) {
  const id = String(formData.get("id"));
  const value = formData.get("value") === "true";
  await supabaseAdmin().from("funds").update({ retail: value }).eq("id", id);
  await republishSnapshot();
  refresh(id);
}

// Auto vs manual sourcing (admin metadata only — no snapshot change).
export async function setSourceType(formData: FormData) {
  const id = String(formData.get("id"));
  const type = String(formData.get("type"));
  if (type !== "auto" && type !== "manual") return;
  await supabaseAdmin().from("funds").update({ source_type: type }).eq("id", id);
  refresh(id);
}

// Full metadata edit (does not touch current_rate — use setRate for that).
export async function updateFund(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  const type = String(formData.get("source_type"));
  const ft = formData.get("fund_type");

  // Benchmark: only accept a known key, else clear it (constraint-safe).
  const bkRaw = strOrNull(formData.get("benchmark_key"));
  const benchmark_key = bkRaw && BENCHMARK_KEYS.includes(bkRaw) ? bkRaw : null;
  // Lock-in is an int column — round any stray decimal.
  const lockRaw = numOrNull(formData.get("lock_in_months"));
  const lock_in_months = lockRaw == null ? null : Math.round(lockRaw);

  const patch: Record<string, unknown> = {
    name: String(formData.get("name")),
    manager: String(formData.get("manager")),
    category: strOrNull(formData.get("category")),
    currency: String(formData.get("currency")),
    tax_free: formData.get("tax_free") === "on",
    min_invest: numOrNull(formData.get("min_invest")),
    mgmt_fee: numOrNull(formData.get("mgmt_fee")),
    aum: strOrNull(formData.get("aum")),
    withdraw_note: strOrNull(formData.get("withdraw_note")),
    site_url: strOrNull(formData.get("site_url")),
    invest_url: strOrNull(formData.get("invest_url")),
    contact_url: strOrNull(formData.get("contact_url")),
    logo_domain: strOrNull(formData.get("logo_domain")),
    rate_source_url: strOrNull(formData.get("rate_source_url")),
    source_type: type === "manual" ? "manual" : "auto",
    status: String(formData.get("status")),
    // Profile & terms (0026).
    inception_date: strOrNull(formData.get("inception_date")),
    benchmark_key,
    expense_ratio: numOrNull(formData.get("expense_ratio")),
    redemption_fee: numOrNull(formData.get("redemption_fee")),
    lock_in_months,
    top_up_min: numOrNull(formData.get("top_up_min")),
    objective: strOrNull(formData.get("objective")),
  };
  // Only touch fund_type when the edit form actually sends it.
  if (ft !== null && FUND_TYPES.includes(String(ft))) patch.fund_type = String(ft);
  await supabaseAdmin().from("funds").update(patch).eq("id", id);
  await republishSnapshot();
  refresh(id);
}

// ── Bulk actions (called from the client table via useTransition) ────────────
export async function bulkSetVerified(ids: string[], value: boolean) {
  if (!ids.length) return;
  await supabaseAdmin().from("funds").update({ verified: value }).in("id", ids);
  await republishSnapshot();
  refresh();
}

export async function bulkSetStatus(ids: string[], status: string) {
  if (!ids.length || !["live", "stale", "hidden"].includes(status)) return;
  await supabaseAdmin().from("funds").update({ status }).in("id", ids);
  await republishSnapshot();
  refresh();
}

export async function bulkSetRetail(ids: string[], value: boolean) {
  if (!ids.length) return;
  await supabaseAdmin().from("funds").update({ retail: value }).in("id", ids);
  await republishSnapshot();
  refresh();
}

export async function bulkDeleteFunds(ids: string[]) {
  if (!ids.length) return;
  const db = supabaseAdmin();
  // Clear history/reviews first (rate_history has no cascade); rate_review cascades.
  await db.from("rate_history").delete().in("fund_id", ids);
  await db.from("funds").delete().in("id", ids);
  await republishSnapshot();
  refresh();
}

// ── Bulk fund-details import (name-matched merge) ────────────────────────────
// Loads a rate/min/fee/AUM board (the weekly MMF table) onto existing funds by
// name. Preview-first: previewFundImport reports what each row would land on
// and change; applyFundImport writes only the approved rows. "Fill blanks
// only" fills nulls and never clobbers an existing value; a written rate also
// appends to rate_history (source=import), matching the manual-rate flow.

export interface ImportRow {
  name: string;
  rate: number | null;
  min: number | null;
  fee: number | null;
  aumKes: number | null;
}
export interface FieldDiff {
  from: number | null;
  to: number | null;
  write: boolean;
}
export interface MatchRow {
  fundId: string;
  fundName: string;
  manager: string;
  currency: string;
  fundType: string | null;
  retail: boolean;
  rate: FieldDiff;
  min: FieldDiff;
  fee: FieldDiff;
  aum: FieldDiff;
}
export interface ImportPreview {
  matched: MatchRow[];
  unmatched: string[];
}
export interface ApplyRow {
  fundId: string;
  rate?: number;
  min?: number;
  fee?: number;
  aumKes?: number;
}

type FundLite = {
  id: string; name: string; manager: string; currency: string;
  fund_type: string | null; retail: boolean;
  current_rate: number | null; min_invest: number | null;
  mgmt_fee: number | null; aum_kes: number | null;
};

// Normalise for matching: lowercase, strip accents/punctuation, and drop
// trailing currency tokens so "KCB Money Market Fund KES" matches "KCB Money
// Market Fund". Collisions (KES + USD sharing a base name) are resolved by
// pickCandidate, which prefers the retail KES fund — the one these rows mean.
const CCY_TOKENS = new Set(["kes", "usd", "gbp", "eur", "zar"]);
function normName(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/&/g, "and")
    .split(/[^a-z0-9]+/)
    .filter((t) => t && !CCY_TOKENS.has(t))
    .join("");
}

function pickCandidate(list: FundLite[]): FundLite {
  if (list.length === 1) return list[0];
  return (
    list.find((f) => f.retail && f.currency === "KES") ??
    list.find((f) => f.currency === "KES") ??
    list[0]
  );
}

function diff(from: number | null, to: number | null, fillOnly: boolean): FieldDiff {
  const has = to != null;
  return { from, to: has ? to : null, write: has && (!fillOnly || from == null) };
}

async function loadFundIndex(): Promise<Map<string, FundLite[]>> {
  const db = supabaseAdmin();
  const { data } = await db
    .from("funds")
    .select("id,name,manager,currency,fund_type,retail,current_rate,min_invest,mgmt_fee,aum_kes")
    .eq("kind", "fund");
  const idx = new Map<string, FundLite[]>();
  for (const f of (data ?? []) as FundLite[]) {
    const k = normName(f.name);
    const arr = idx.get(k) ?? [];
    arr.push(f);
    idx.set(k, arr);
  }
  return idx;
}

export async function previewFundImport(
  rows: ImportRow[],
  fillOnly: boolean,
): Promise<ImportPreview> {
  const idx = await loadFundIndex();
  const matched: MatchRow[] = [];
  const unmatched: string[] = [];
  for (const r of rows) {
    const cands = idx.get(normName(r.name));
    if (!cands || cands.length === 0) {
      unmatched.push(r.name);
      continue;
    }
    const f = pickCandidate(cands);
    matched.push({
      fundId: f.id,
      fundName: f.name,
      manager: f.manager,
      currency: f.currency,
      fundType: f.fund_type,
      retail: f.retail,
      rate: diff(f.current_rate, r.rate, fillOnly),
      min: diff(f.min_invest, r.min, fillOnly),
      fee: diff(f.mgmt_fee, r.fee, fillOnly),
      aum: diff(f.aum_kes, r.aumKes, fillOnly),
    });
  }
  return { matched, unmatched };
}

function aumText(kes: number): string {
  if (kes >= 1e9) {
    const b = kes / 1e9;
    return `KES ${b >= 10 ? Math.round(b) : b.toFixed(1)}B`;
  }
  if (kes >= 1e6) return `KES ${Math.round(kes / 1e6)}M`;
  return `KES ${Math.round(kes)}`;
}

export async function applyFundImport(rows: ApplyRow[]): Promise<{ written: number }> {
  const db = supabaseAdmin();
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT
  let written = 0;
  for (const r of rows) {
    const patch: Record<string, unknown> = {};
    if (r.min != null) patch.min_invest = r.min;
    if (r.fee != null) patch.mgmt_fee = r.fee;
    if (r.aumKes != null) {
      patch.aum_kes = r.aumKes;
      patch.aum = aumText(r.aumKes);
    }
    if (r.rate != null && Number.isFinite(r.rate) && r.rate > 0 && r.rate < 30) {
      await db.from("rate_history").upsert(
        { fund_id: r.fundId, rate: r.rate, as_of: asOf, source: "import" },
        { onConflict: "fund_id,as_of" },
      );
      patch.current_rate = r.rate;
      patch.status = "live";
    }
    if (Object.keys(patch).length) {
      await db.from("funds").update(patch).eq("id", r.fundId);
      written++;
    }
  }
  await republishSnapshot();
  refresh();
  return { written };
}
