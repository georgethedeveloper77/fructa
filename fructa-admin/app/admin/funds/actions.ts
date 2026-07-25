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

// CIS fund_type values vs legacy category (non-CIS instrument) values. The Type
// control on the detail form sends one union value; updateFund routes it to the
// matching column and clears the other so the two never drift out of sync.
const FUND_TYPES = ["mmf", "fixed_income", "equity", "balanced", "special"];
const LEGACY_TYPES = ["tbill", "bond", "sacco", "stock"];
const CURRENCIES = ["KES", "USD", "GBP", "EUR", "ZAR"];
const BENCHMARK_KEYS = ["tbill_91", "tbill_182", "tbill_364", "cbr"];

// 0074 vocabularies. Every one of these mirrors a CHECK constraint in the
// database, and the reason they are repeated here rather than trusted to the
// database is that a constraint violation surfaces as a failed save with no
// useful message, while an unknown value caught here can be turned into a null
// and reported. Keep them in step with the migration or the form will offer
// options the database refuses.
const NET_OF = ["nothing", "fees", "fees_and_tax"];
const RETURN_PERIODS = ["month", "quarter", "half", "year", "ytd", "since_inception"];
const FEE_KINDS = ["mgmt", "service", "none"];
// Rows in return_history. `since_inception` is legal here too (0075) but it is
// a cumulative total, not a member of the series, and the form writes it from
// its own field rather than the period dropdown.
const HISTORY_PERIODS = ["month", "quarter", "half", "year", "ytd", "since_inception"];

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

/// The NAV twin of [setRate]. A priced fund's mark goes into nav_history AND
/// onto the row, exactly as a yield goes into rate_history and onto the row.
///
/// This exists because updatePricing only ever wrote price_per_unit, a single
/// scalar. One point. You cannot draw a line through one point, so a NAV fund
/// had no chart, no sparkline and no way to show what it already did. Every
/// fact sheet you enter from here on adds a point to a real series.
///
/// The price is in the FUND'S OWN currency and is never converted. A USD fund's
/// NAV is in dollars, and the column is called `price` rather than `price_kes`
/// for the same reason `aum_native` is not `aum_kes`.
export async function setPrice(formData: FormData) {
  const id = String(formData.get("id"));
  const price = Number(formData.get("price"));
  // A price of zero is not a low price, it is a missing one.
  if (!id || !Number.isFinite(price) || price <= 0) return;

  // The as-of date is the FACT SHEET'S date, not today's. A June NAV entered in
  // July is a June mark, and stamping it "today" would bend the series.
  const asOf =
    strOrNull(formData.get("as_of")) ??
    new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT

  const db = supabaseAdmin();
  await db.from("nav_history").upsert(
    { fund_id: id, as_of: asOf, price, source: "manual" },
    { onConflict: "fund_id,as_of" },
  );

  // The row carries the LATEST mark. An older fact sheet keyed in after a newer
  // one still lands in the series, but it must not overwrite the current price,
  // so the row is only touched when this mark is at least as recent as the one
  // already on it.
  const { data: cur } = await db
    .from("funds")
    .select("price_as_of")
    .eq("id", id)
    .maybeSingle();
  const prev = (cur?.price_as_of as string | null) ?? null;
  if (prev == null || asOf >= prev) {
    await db
      .from("funds")
      .update({ price_per_unit: price, price_as_of: asOf, status: "live" })
      .eq("id", id);
  }

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

// Auto vs manual sourcing (admin metadata only, no snapshot change).
export async function setSourceType(formData: FormData) {
  const id = String(formData.get("id"));
  const type = String(formData.get("type"));
  if (type !== "auto" && type !== "manual") return;
  await supabaseAdmin().from("funds").update({ source_type: type }).eq("id", id);
  refresh(id);
}

// Full metadata edit (does not touch current_rate; use setRate for that).
export async function updateFund(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  const srcType = String(formData.get("source_type"));

  // Benchmark: only accept a known key, else clear it (constraint-safe).
  const bkRaw = strOrNull(formData.get("benchmark_key"));
  const benchmark_key = bkRaw && BENCHMARK_KEYS.includes(bkRaw) ? bkRaw : null;
  // Lock-in is an int column, so round any stray decimal.
  const lockRaw = numOrNull(formData.get("lock_in_months"));
  const lock_in_months = lockRaw == null ? null : Math.round(lockRaw);

  const patch: Record<string, unknown> = {
    name: String(formData.get("name")),
    manager: String(formData.get("manager")),
    currency: String(formData.get("currency")),
    tax_free: formData.get("tax_free") === "on",
    min_invest: numOrNull(formData.get("min_invest")),
    mgmt_fee: numOrNull(formData.get("mgmt_fee")),
    // AUM in the fund's OWN currency. It used to be `aum`, a free-text box, and
    // it held whatever anyone typed: 'KES 3.80 billion' on one fund and a naked
    // '1150000' on another. The currency does not belong in the value; the row
    // already carries it.
    aum_native: numOrNull(formData.get("aum_native")),
    withdraw_note: strOrNull(formData.get("withdraw_note")),
    site_url: strOrNull(formData.get("site_url")),
    invest_url: strOrNull(formData.get("invest_url")),
    contact_url: strOrNull(formData.get("contact_url")),
    logo_domain: strOrNull(formData.get("logo_domain")),
    rate_source_url: strOrNull(formData.get("rate_source_url")),
    source_type: srcType === "manual" ? "manual" : "auto",
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

  // Single Type control routes to the right column and keeps the two mutually
  // exclusive: a CIS value sets fund_type and clears category; a legacy value
  // sets category and clears fund_type. An empty/unknown value leaves both
  // untouched, so a save never silently reclassifies or nulls the type.
  const primaryType = strOrNull(formData.get("type"));
  if (primaryType && FUND_TYPES.includes(primaryType)) {
    patch.fund_type = primaryType;
    patch.category = null;
  } else if (primaryType && LEGACY_TYPES.includes(primaryType)) {
    patch.category = primaryType;
    patch.fund_type = null;
  }

  await supabaseAdmin().from("funds").update(patch).eq("id", id);
  await republishSnapshot();
  refresh(id);
}

// Field-scoped pricing writer (basis + NAV price fields). Touches ONLY these
// four columns  like updateCustody/updateContact  so a yield fund's rate
// stays with setRate and never rides here. Selecting yield/none clears the
// price fields, so a fund flipped off NAV can't keep a stale unit price.
// 'return' added in 0074. Its absence here was not a missing feature, it was a
// data-destroying default: an unrecognised basis fell through to "yield", so
// opening this form on a return-basis fund and pressing Save silently retyped it
// as a yield fund, and the app then taxed and compounded a quarterly figure.
// The fund in question published its returns net of tax already.
//
// The fallback is now null rather than a guess. A writer that cannot tell what
// kind of number a fund quotes must not decide on the fund's behalf, and null
// leaves the row alone for a human to fix rather than confidently mislabelling
// it. This is the same fail-open defect as Fund.showsYield's `basis ?? 'yield'`
// on the app side, except a reader showing the wrong thing can be corrected by
// a rebuild and a writer storing the wrong thing cannot.
const BASES = ["yield", "nav", "return", "none"];
export async function updatePricing(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const basisRaw = strOrNull(formData.get("basis"));
  const basis = basisRaw && BASES.includes(basisRaw) ? basisRaw : null;
  if (basis === null) return; // unknown basis: change nothing, keep the row honest
  const isNav = basis === "nav";
  const isReturn = basis === "return";

  // Credit quality arrives as five numbers and is stored as one jsonb, shaped
  // like funds.composition. Zero-weight classes are dropped rather than stored as
  // 0, so "no unrated paper" and "we did not check" stay distinguishable.
  const CREDIT_KEYS = ["gov", "aa", "a", "bbb", "unrated"];
  const credit: Record<string, number> = {};
  for (const k of CREDIT_KEYS) {
    const v = numOrNull(formData.get(`credit_${k}`));
    if (v != null && v > 0) credit[k] = v;
  }

  const netOfRaw = strOrNull(formData.get("net_of"));
  const rp = strOrNull(formData.get("return_period"));
  const fk = strOrNull(formData.get("fee_kind"));

  const patch: Record<string, unknown> = {
    basis,

    // What is already deducted from the quoted number. Kept for EVERY basis,
    // not just return: an MMF quoting net of fees and gross of withholding tax
    // is making the same kind of statement, and writing it down is what lets
    // the app stop assuming it.
    net_of: netOfRaw && NET_OF.includes(netOfRaw) ? netOfRaw : null,

    // The period a realized return covers, and the date it closed. Cleared on
    // anything that is not a return fund, because a yield is per annum by
    // definition and a leftover "quarter" on one would label it wrongly.
    return_period: isReturn && rp && RETURN_PERIODS.includes(rp) ? rp : null,
    return_as_of: isReturn ? strOrNull(formData.get("return_as_of")) : null,

    // The fee is not always a management fee. A 5% p.a. financial services
    // charge plus 10% of everything above a 25% hurdle is two charges, and the
    // larger of them was invisible while only mgmt_fee existed.
    fee_kind: fk && FEE_KINDS.includes(fk) ? fk : null,
    perf_fee_pct: numOrNull(formData.get("perf_fee_pct")),
    hurdle_pct: numOrNull(formData.get("hurdle_pct")),

    // Share classes. One product, several lock-ins and fees and yields. Left
    // alone by basis, because a class group can sit under any of them.
    class_group: strOrNull(formData.get("class_group")),
    class_label: strOrNull(formData.get("class_label")),

    distribution_pct: isNav ? numOrNull(formData.get("distribution_pct")) : null,
    // Duration and credit belong to a fund that holds bonds, which is a NAV fund.
    // Flip a fund off NAV and they clear with the price, so nothing stale is left
    // claiming a rate sensitivity the fund no longer has.
    duration_years: isNav ? numOrNull(formData.get("duration_years")) : null,
    credit_quality: isNav && Object.keys(credit).length > 0 ? credit : null,
  };

  // This form no longer SETS a price. setPrice is the only writer that does,
  // because a price on the row with no dated mark behind it is a point that never
  // joins the series, and a fund whose chart disagrees with its headline is worse
  // than a fund with no chart.
  //
  // It can still CLEAR one. Flipping a fund off NAV must not leave a stale unit
  // price standing on a fund that no longer quotes one. The history is left
  // intact: a mis-click and a flip back should not destroy a series.
  if (!isNav) {
    patch.price_per_unit = null;
    patch.price_as_of = null;
  }

  await supabaseAdmin().from("funds").update(patch).eq("id", id);
  await republishSnapshot();
  refresh(id);
}

// ── Period returns (0074) ───────────────────────────────────────────────────
//
// The writer for return_history, and the sibling of setRate and setPrice. Kept
// separate from updatePricing for the reason setPrice is separate from it: a
// headline on the fund row with no dated mark behind it is a number that never
// joins a series, and a fund whose chart disagrees with its headline is worse
// than a fund with no chart.
//
// Unlike setRate and setPrice, this one does NOT promote anything onto the fund
// row. A quarterly return is not a current rate, and current_rate on a
// return-basis fund must stay null: it is the field the app taxes and compounds,
// and there is nothing here that may be taxed or compounded.

export async function setPeriodReturn(formData: FormData) {
  const id = String(formData.get("id"));
  const periodEnd = strOrNull(formData.get("period_end"));
  const period = strOrNull(formData.get("period"));
  const netPct = numOrNull(formData.get("net_pct"));

  // No sign check, and this is deliberate. setPrice refuses a zero or negative
  // price because a fund whose units are worthless has not published a price, it
  // has ceased to exist. A negative RETURN is an ordinary event: MansaX posted
  // 3.78% in one quarter and 6.05% two quarters later, and a rule that dropped
  // the bad periods would leave a chart showing only the good ones, which is a
  // more damaging lie than no chart at all.
  if (!id || !periodEnd || !period || netPct == null) return;
  if (!HISTORY_PERIODS.includes(period)) return;

  const netOfRaw = strOrNull(formData.get("net_of"));
  // Per row, not inherited from the fund. A manager can publish quarters net of
  // fees and an annual figure net of fees and tax on the same page, and the app
  // has to know which is which before it decides whether to deduct anything.
  const netOf = netOfRaw && NET_OF.includes(netOfRaw) ? netOfRaw : "fees";

  await supabaseAdmin().from("return_history").upsert(
    {
      fund_id: id,
      period_end: periodEnd,
      period,
      net_pct: netPct,
      gross_pct: numOrNull(formData.get("gross_pct")),
      net_of: netOf,
      source: "manual",
    },
    { onConflict: "fund_id,period_end,period" },
  );

  await republishSnapshot();
  refresh(id);
}

export async function deletePeriodReturn(formData: FormData) {
  const id = String(formData.get("id"));
  const periodEnd = strOrNull(formData.get("period_end"));
  const period = strOrNull(formData.get("period"));
  if (!id || !periodEnd || !period) return;

  await supabaseAdmin()
    .from("return_history")
    .delete()
    .eq("fund_id", id)
    .eq("period_end", periodEnd)
    .eq("period", period);

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
  aumNative: number | null;
  /** Currency code found IN the pasted value, if any. Null when bare. */
  aumCcy: string | null;
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
  /** The pasted value named a currency this fund is not denominated in. */
  aumCcyMismatch: boolean;
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
  aumNative?: number;
}

type FundLite = {
  id: string; name: string; manager: string; currency: string;
  fund_type: string | null; retail: boolean;
  current_rate: number | null; min_invest: number | null;
  mgmt_fee: number | null; aum_native: number | null;
};

// Normalise for matching: lowercase, strip accents/punctuation, and drop
// trailing currency tokens so "KCB Money Market Fund KES" matches "KCB Money
// Market Fund". Collisions (KES + USD sharing a base name) are resolved by
// pickCandidate, which uses the row's currency hint (see currencyHint) and
// falls back to the retail KES fund, the one the weekly MMF rows mean.
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

// Currency implied by the row name, e.g. "Stanbic Fixed Income Fund USD" or
// "NCBA Fixed Income Basket (USD) Fund" -> "USD". normName strips currency
// tokens, so a KES and a USD fund sharing a base name collapse to one key;
// this hint lets pickCandidate route each row to the fund in its own currency
// instead of both landing on the retail KES fund.
const CCY_HINTS = ["USD", "GBP", "EUR", "ZAR", "KES"];
function currencyHint(raw: string): string | null {
  const t = raw.toLowerCase();
  for (const c of CCY_HINTS) {
    const lc = c.toLowerCase();
    if (t.includes(`(${lc})`) || new RegExp(`(^|[^a-z])${lc}([^a-z]|$)`).test(t)) {
      return c;
    }
  }
  return null;
}

// Choose which DB fund a row lands on when its normalised name matches several
// (a KES/USD pair). A currency hint wins; otherwise prefer the retail KES fund.
function pickCandidate(list: FundLite[], ccyHint: string | null): FundLite {
  if (list.length === 1) return list[0];
  if (ccyHint) {
    const m = list.find((f) => f.currency === ccyHint);
    if (m) return m;
  }
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
    .select("id,name,manager,currency,fund_type,retail,current_rate,min_invest,mgmt_fee,aum_native")
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
  const unmatched: string[] = [];

  // Resolve each row to a single fund via its currency hint, then dedupe by
  // fundId. Two rows collapsing onto one fund (e.g. a USD row with no USD fund
  // in the DB falling back to the KES fund) keep the row whose currency
  // actually matches the fund, so a USD figure never overwrites the KES fund,
  // and the preview never emits two children with the same key.
  type Resolved = { f: FundLite; r: ImportRow; hintMatch: boolean };
  const byFund = new Map<string, Resolved>();

  for (const r of rows) {
    const cands = idx.get(normName(r.name));
    if (!cands || cands.length === 0) {
      unmatched.push(r.name);
      continue;
    }
    const hint = currencyHint(r.name);
    const f = pickCandidate(cands, hint);
    const hintMatch = hint != null && hint === f.currency;
    const prev = byFund.get(f.id);
    if (!prev || (hintMatch && !prev.hintMatch)) {
      byFund.set(f.id, { f, r, hintMatch });
    }
  }

  const matched: MatchRow[] = [];
  for (const { f, r } of byFund.values()) {
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
      aum: diff(f.aum_native, r.aumNative, fillOnly),
      // A row naming a currency the fund is not denominated in is never written.
      // The old importer stripped /kes/i from every input, so pasting 'KES 5M'
      // against a dollar fund imported five million DOLLARS, then stamped the
      // text column 'KES 5M' for good measure.
      aumCcyMismatch: r.aumCcy != null && r.aumCcy !== f.currency,
    });
  }
  return { matched, unmatched };
}

export async function applyFundImport(rows: ApplyRow[]): Promise<{ written: number }> {
  const db = supabaseAdmin();
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT
  let written = 0;
  for (const r of rows) {
    const patch: Record<string, unknown> = {};
    if (r.min != null) patch.min_invest = r.min;
    if (r.fee != null) patch.mgmt_fee = r.fee;
    // One column, in the fund's own currency. No text twin, and no currency
    // stamped onto the value: aumText() hardcoded 'KES' whatever the fund was.
    if (r.aumNative != null) patch.aum_native = r.aumNative;
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
