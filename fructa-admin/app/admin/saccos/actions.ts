"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { slugify } from "@/lib/publish";

// Every mutation republishes, same as the funds and stocks lanes: the app reads
// the snapshot, not these tables.
async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch { /* ignore */ }
}

function refresh(id?: string) {
  revalidatePath("/admin/saccos");
  revalidatePath("/admin");
  if (id) revalidatePath(`/admin/saccos/${id}`);
}

const numOrNull = (v: FormDataEntryValue | null) => {
  const n = Number(v);
  return v === null || v === "" || !Number.isFinite(n) ? null : n;
};
const strOrNull = (v: FormDataEntryValue | null) => {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
};
const intOrNull = (v: FormDataEntryValue | null) => {
  const n = numOrNull(v);
  return n == null ? null : Math.round(n);
};

const BONDS = ["open", "closed", "unknown"];
const CLASSES = ["dt", "nwdt", "credit_only"];

// ── Society ─────────────────────────────────────────────────────────────────

export async function addSacco(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;

  const id = slugify(name);
  if (!id) return;

  // licence_class defaults to 'dt' and common_bond defaults to 'unknown'.
  //
  // Unknown is the honest default and it is deliberately not 'open'. SASRA does
  // not publish the common bond, so we usually do not know it, and defaulting to
  // open would tell a user they can join a society whose membership is closed to
  // them. The snapshot treats unknown as not joinable for exactly this reason.
  const classRaw = strOrNull(formData.get("licence_class"));

  await supabaseAdmin().from("saccos").insert({
    id,
    name,
    display_name: strOrNull(formData.get("display_name")) ?? name,
    licence_class: classRaw && CLASSES.includes(classRaw) ? classRaw : "dt",
    common_bond: "unknown",
    county: strOrNull(formData.get("county")),
    active: true,
  });
  await republishSnapshot();
  refresh(id);
}

// Profile. Section-scoped: touches ONLY the fields this form carries. Bond,
// joining terms, institution figures and rates each have their own writer and
// never ride here, because a writer that reads a field its form does not carry
// gets null back and wipes the column.
export async function updateSaccoProfile(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  await supabaseAdmin().from("saccos").update({
    name: String(formData.get("name")),
    display_name: strOrNull(formData.get("display_name")),
    county: strOrNull(formData.get("county")),
    physical_location: strOrNull(formData.get("physical_location")),
    postal_address: strOrNull(formData.get("postal_address")),
    branches: intOrNull(formData.get("branches")),
    website: strOrNull(formData.get("website")),
    phone: strOrNull(formData.get("phone")),
    email: strOrNull(formData.get("email")),
    logo_url: strOrNull(formData.get("logo_url")),
    brand_color: strOrNull(formData.get("brand_color")),
    about: strOrNull(formData.get("about")),
  }).eq("id", id);

  await republishSnapshot();
  refresh(id);
}

// Bond. Its own writer, and its own form, because it is the single field that
// decides whether a SACCO is shown to a user as joinable at all. A society you
// cannot join has no business outranking one you can, however good its rate.
export async function updateSaccoBond(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const bondRaw = String(formData.get("common_bond") ?? "unknown");
  const bond = BONDS.includes(bondRaw) ? bondRaw : "unknown";

  await supabaseAdmin().from("saccos").update({
    common_bond: bond,
    bond_note: strOrNull(formData.get("bond_note")),
  }).eq("id", id);

  await republishSnapshot();
  refresh(id);
}

// Joining terms, from the SACCO's own published terms.
export async function updateSaccoTerms(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const fosaRaw = strOrNull(formData.get("has_fosa"));

  await supabaseAdmin().from("saccos").update({
    registration_fee_kes: numOrNull(formData.get("registration_fee_kes")),
    min_share_capital_kes: numOrNull(formData.get("min_share_capital_kes")),
    min_monthly_deposit_kes: numOrNull(formData.get("min_monthly_deposit_kes")),
    loan_multiple: numOrNull(formData.get("loan_multiple")),
    deposit_notice_days: intOrNull(formData.get("deposit_notice_days")),
    // Three states, not two. "We have not checked" is not "no FOSA".
    has_fosa: fosaRaw === "yes" ? true : fosaRaw === "no" ? false : null,
  }).eq("id", id);

  await republishSnapshot();
  refresh(id);
}

// Institution figures, from the SASRA Sacco Supervision Annual Report. Annual,
// and always carried with the year they belong to: an asset figure with no
// as-of date is a number pretending to be current.
export async function updateSaccoInstitution(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const tier = intOrNull(formData.get("tier"));

  await supabaseAdmin().from("saccos").update({
    tier: tier != null && tier >= 1 && tier <= 3 ? tier : null,
    total_assets_kes: numOrNull(formData.get("total_assets_kes")),
    deposits_kes: numOrNull(formData.get("deposits_kes")),
    members: intOrNull(formData.get("members")),
    registered_year: intOrNull(formData.get("registered_year")),
    financials_as_of: strOrNull(formData.get("financials_as_of")),
    sasra_licensed_until: strOrNull(formData.get("sasra_licensed_until")),
  }).eq("id", id);

  await republishSnapshot();
  refresh(id);
}

export async function toggleSaccoActive(formData: FormData) {
  const id = String(formData.get("id"));
  const value = formData.get("value") === "true";
  if (!id) return;
  await supabaseAdmin().from("saccos").update({ active: value }).eq("id", id);
  await republishSnapshot(); // inactive societies drop out of the snapshot
  refresh(id);
}

export async function deleteSacco(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  await supabaseAdmin().from("saccos").delete().eq("id", id); // rates cascade
  await republishSnapshot();
  refresh();
}

// ── Rates ───────────────────────────────────────────────────────────────────
// TWO rates per year, and they are not interchangeable.
//
//   interest_on_deposits       paid on member savings. Uncapped pot. This is
//                              what the app ranks on.
//   dividend_on_share_capital  paid on share capital, which is capped. Almost
//                              always the bigger percentage and almost always
//                              the smaller cheque.
//
// Upserts on (sacco_id, financial_year), so re-entering a year corrects it
// rather than duplicating.
export async function saveSaccoRate(formData: FormData) {
  const sacco_id = String(formData.get("sacco_id"));
  const fy = intOrNull(formData.get("financial_year"));
  const dep = numOrNull(formData.get("interest_on_deposits"));
  const div = numOrNull(formData.get("dividend_on_share_capital"));
  if (!sacco_id || fy == null) return;
  // The table's own check constraint requires at least one. Fail here rather
  // than let Postgres throw.
  if (dep == null && div == null) return;

  await supabaseAdmin().from("sacco_rates").upsert({
    sacco_id,
    financial_year: fy,
    interest_on_deposits: dep,
    dividend_on_share_capital: div,
    declared_on: strOrNull(formData.get("declared_on")),
    source_url: strOrNull(formData.get("source_url")),
    source_doc: strOrNull(formData.get("source_doc")),
  }, { onConflict: "sacco_id,financial_year" });

  await republishSnapshot();
  refresh(sacco_id);
}

export async function deleteSaccoRate(formData: FormData) {
  const id = String(formData.get("id"));
  const sacco_id = String(formData.get("sacco_id"));
  if (!id) return;
  await supabaseAdmin().from("sacco_rates").delete().eq("id", id);
  await republishSnapshot();
  refresh(sacco_id);
}

// ── Rate bulk import ────────────────────────────────────────────────────────
// SACCO rates are DECLARED at the AGM, once a year, in the January to April
// window. There is nothing to poll, which is why this is an import and not a
// scraper: the number does not move for the other eight months of the year.
//
// Format: sacco,financial_year,interest_on_deposits,dividend_on_share_capital[,declared_on][,source_url]
//   tower-sacco,2025,13.0,20.0,2026-03-21,https://...
//   Nyati Sacco Society Ltd,2025,11.3,21.0
//
// Matching is on the slug id first, then on a normalised name. It NEVER guesses:
// a name that hits two societies is reported as ambiguous rather than assigned
// to the first one, and a name that hits none is reported as unmatched.

export type SaccoImportRow = {
  key: string;
  financialYear: number | null;
  deposits: number | null;
  dividend: number | null;
  declaredOn: string | null;
  sourceUrl: string | null;
};

export type SaccoMatchRow = {
  saccoId: string;
  saccoName: string;
  financialYear: number;
  depositsFrom: number | null;
  depositsTo: number | null;
  dividendFrom: number | null;
  dividendTo: number | null;
  declaredOn: string | null;
  sourceUrl: string | null;
  // Set when the numbers look like the two columns were swapped. Not an error,
  // because it is occasionally real, so the row still imports if you leave it
  // ticked. See the note in previewSaccoRateImport.
  warn: string | null;
};

export type SaccoPreview = {
  matched: SaccoMatchRow[];
  unmatched: string[];
  ambiguous: string[];
  invalid: string[];
};

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

// Strips the legal suffixes the SASRA register carries so a spreadsheet that
// says "Tower Sacco" still lands on "Tower Sacco Society Ltd".
function normName(s: string): string {
  return s
    .toLowerCase()
    .replace(/\bsociety\b/g, " ")
    .replace(/\b(limited|ltd)\b/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export async function previewSaccoRateImport(
  rows: SaccoImportRow[],
): Promise<SaccoPreview> {
  const db = supabaseAdmin();

  const [{ data: saccos }, { data: existing }] = await Promise.all([
    db.from("saccos").select("id,name,display_name").eq("active", true),
    db.from("sacco_rates").select(
      "sacco_id,financial_year,interest_on_deposits,dividend_on_share_capital",
    ),
  ]);

  const byId = new Map<string, { id: string; name: string }>();
  // A normalised name can map to more than one society (there are two Biasharas
  // and two Jamiis in the register). Keep every hit so a collision is REPORTED
  // rather than silently resolved to whichever row the database returned first.
  const byName = new Map<string, { id: string; name: string }[]>();

  for (const s of saccos ?? []) {
    const entry = { id: s.id, name: s.name };
    byId.set(s.id, entry);
    for (const n of [s.name, s.display_name].filter(Boolean) as string[]) {
      const k = normName(n);
      if (!k) continue;
      const arr = byName.get(k) ?? [];
      if (!arr.some((e) => e.id === entry.id)) arr.push(entry);
      byName.set(k, arr);
    }
  }

  const prior = new Map<
    string,
    { dep: number | null; div: number | null }
  >();
  for (const r of existing ?? []) {
    prior.set(`${r.sacco_id}|${r.financial_year}`, {
      dep: r.interest_on_deposits == null
        ? null
        : Number(r.interest_on_deposits),
      div: r.dividend_on_share_capital == null
        ? null
        : Number(r.dividend_on_share_capital),
    });
  }

  const matched: SaccoMatchRow[] = [];
  const unmatched: string[] = [];
  const ambiguous: string[] = [];
  const invalid: string[] = [];

  for (const r of rows) {
    const raw = r.key.trim();
    if (!raw) continue;

    if (r.financialYear == null || r.financialYear < 2000 || r.financialYear > 2100) {
      invalid.push(`${raw}: financial year missing or implausible`);
      continue;
    }
    if (r.deposits == null && r.dividend == null) {
      invalid.push(`${raw}: no rate on the row`);
      continue;
    }
    const bad = [r.deposits, r.dividend].some(
      (v) => v != null && (v < 0 || v > 100),
    );
    if (bad) {
      invalid.push(`${raw}: a rate is outside 0 to 100`);
      continue;
    }
    if (r.declaredOn && !ISO_DATE.test(r.declaredOn)) {
      invalid.push(`${raw}: declared date must be YYYY-MM-DD`);
      continue;
    }

    let hit = byId.get(raw) ?? byId.get(raw.toLowerCase()) ?? null;
    if (!hit) {
      const hits = byName.get(normName(raw)) ?? [];
      if (hits.length > 1) {
        ambiguous.push(`${raw} matches ${hits.map((h) => h.id).join(", ")}`);
        continue;
      }
      hit = hits[0] ?? null;
    }
    if (!hit) {
      unmatched.push(raw);
      continue;
    }

    // The swap check, and the reason this importer exists rather than a generic
    // two-column one.
    //
    // A SACCO's dividend on shares is nearly always the higher percentage and
    // the deposit rate the lower one. A row where the deposit rate is the bigger
    // number is usually a spreadsheet with its columns the wrong way round, and
    // the cost of getting that wrong is not cosmetic: the deposit rate is the
    // number the app RANKS on, so a swapped row would put a society at the top
    // of the league table on the strength of a percentage paid on a capped pot
    // of shares. Flag it, show both numbers, let a human decide.
    let warn: string | null = null;
    if (
      r.deposits != null && r.dividend != null && r.deposits > r.dividend
    ) {
      warn = "deposit rate is above the dividend, which is unusual. Check the columns are not swapped.";
    }

    const p = prior.get(`${hit.id}|${r.financialYear}`) ?? null;

    matched.push({
      saccoId: hit.id,
      saccoName: hit.name,
      financialYear: r.financialYear,
      depositsFrom: p?.dep ?? null,
      depositsTo: r.deposits,
      dividendFrom: p?.div ?? null,
      dividendTo: r.dividend,
      declaredOn: r.declaredOn,
      sourceUrl: r.sourceUrl,
      warn,
    });
  }

  return { matched, unmatched, ambiguous, invalid };
}

export async function applySaccoRateImport(
  rows: SaccoMatchRow[],
): Promise<{ written: number }> {
  if (rows.length === 0) return { written: 0 };

  const payload = rows.map((r) => ({
    sacco_id: r.saccoId,
    financial_year: r.financialYear,
    interest_on_deposits: r.depositsTo,
    dividend_on_share_capital: r.dividendTo,
    declared_on: r.declaredOn,
    source_url: r.sourceUrl,
  }));

  await supabaseAdmin()
    .from("sacco_rates")
    .upsert(payload, { onConflict: "sacco_id,financial_year" });

  await republishSnapshot();
  refresh();
  return { written: payload.length };
}
