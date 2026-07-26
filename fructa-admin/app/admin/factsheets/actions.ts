"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { republishSnapshot } from "@/lib/publish";
import { revalidatePath } from "next/cache";

// ── The vocabularies, mirroring the CHECK constraints in 0074 and 0075 ──────
const BASES = ["yield", "nav", "return", "none"];
const NET_OF = ["nothing", "fees", "fees_and_tax"];
const PERIODS = ["month", "quarter", "half", "year", "ytd", "since_inception"];

// Columns a payload is ALLOWED to set, and nothing else.
//
// An allowlist rather than a passthrough, because this writer takes its input
// from a machine reading a PDF. Without it, a hallucinated key called `status`
// or `verified` or `featured` would be written straight into the funds table by
// a reviewer who was looking at the numbers, not the key names.
const TERM_COLUMNS = new Set([
  "min_invest", "top_up_min", "lock_in_months", "mgmt_fee", "expense_ratio",
  "redemption_fee", "perf_fee_pct", "hurdle_pct", "fee_kind", "inception_date",
  "aum_native", "objective", "withdraw_note", "benchmark_key",
  "class_group", "class_label",
]);

type Figure = { value?: unknown; caption?: string };

const num = (f: Figure | undefined): number | null => {
  const v = f?.value;
  return typeof v === "number" && Number.isFinite(v) ? v : null;
};
const str = (f: Figure | undefined): string | null => {
  const v = f?.value;
  const s = typeof v === "string" ? v.trim() : "";
  return s === "" ? null : s;
};

export interface StageResult {
  ok: boolean;
  id: number | null;
  error: string | null;
  /** Figures the extractor says it saw and deliberately did not use. */
  excluded: { value: unknown; caption: string; reason: string }[];
}

/// Stage a payload for review. Writes NOTHING to funds.
export async function stageFactsheet(formData: FormData): Promise<StageResult> {
  const fundId = String(formData.get("fund_id") ?? "").trim() || null;
  const label = String(formData.get("source_label") ?? "").trim();
  const asOf = String(formData.get("as_of") ?? "").trim();
  const sourceUrl = String(formData.get("source_url") ?? "").trim() || null;
  const raw = String(formData.get("payload") ?? "");

  if (!label) return { ok: false, id: null, error: "Give the sheet a label, e.g. 'MansaX Q1 2026'.", excluded: [] };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(asOf)) {
    return { ok: false, id: null, error: "Pick the date printed ON THE SHEET, not today.", excluded: [] };
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(raw);
  } catch {
    return { ok: false, id: null, error: "That isn't valid JSON.", excluded: [] };
  }

  // `excluded` is required, and an empty array is a claim rather than a
  // default. It is the extractor stating which numbers it saw and chose not to
  // use, which is the only way to tell "this sheet printed no target" from "the
  // extractor did not look for one". Every sheet reviewed so far has had at
  // least one: a target, an annualised quarter, or a figure before fees.
  if (!Array.isArray(payload.excluded)) {
    return {
      ok: false, id: null, excluded: [],
      error: "Payload needs an `excluded` array, even if empty. It records the figures on the sheet that are NOT returns.",
    };
  }

  const { data, error } = await supabaseAdmin()
    .from("factsheet_imports")
    .insert({
      fund_id: fundId,
      source_label: label,
      source_url: sourceUrl,
      as_of: asOf,
      payload,
      confidence: num(payload.confidence as Figure) ?? null,
      status: "pending",
    })
    .select("id")
    .single();

  if (error) return { ok: false, id: null, error: error.message, excluded: [] };

  revalidatePath("/admin/factsheets");
  return {
    ok: true,
    id: data.id as number,
    error: null,
    excluded: payload.excluded as StageResult["excluded"],
  };
}

export interface ApplyResult {
  ok: boolean;
  error: string | null;
  /** What was written, in words, so the reviewer sees the consequence. */
  applied: string[];
  /** What was deliberately skipped, and why. */
  skipped: string[];
}

/// Apply a staged import. Field-scoped: touches only the columns the payload
/// carries, and refuses outright on a hand-maintained fund.
export async function applyFactsheet(formData: FormData): Promise<ApplyResult> {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return { ok: false, error: "Bad id.", applied: [], skipped: [] };

  const db = supabaseAdmin();
  const { data: imp } = await db
    .from("factsheet_imports")
    .select("id,fund_id,as_of,payload,source_label")
    .eq("id", id)
    .eq("status", "pending")
    .single();
  if (!imp) return { ok: false, error: "Not found, or already decided.", applied: [], skipped: [] };
  if (!imp.fund_id) return { ok: false, error: "Assign this import to a fund first.", applied: [], skipped: [] };

  const { data: fund } = await db
    .from("funds")
    .select("id,name,basis,current_rate,source_type")
    .eq("id", imp.fund_id)
    .single();
  if (!fund) return { ok: false, error: "That fund no longer exists.", applied: [], skipped: [] };

  // A hand-maintained fund is one somebody decided the pipeline should keep off.
  // Refused rather than warned: the whole reason source_type flips to manual is
  // that an automated writer got it wrong there once already.
  if (fund.source_type === "manual") {
    return {
      ok: false, applied: [], skipped: [],
      error: `${fund.name} is set to manual sourcing. Change it on the fund page first if you really want the pipeline writing to it.`,
    };
  }

  const p = imp.payload as Record<string, Record<string, Figure> & Figure[]>;
  const applied: string[] = [];
  const skipped: string[] = [];
  const patch: Record<string, unknown> = {};

  // ── basis and net_of ─────────────────────────────────────────────────────
  const basis = str(p.basis as unknown as Figure);
  if (basis && BASES.includes(basis)) {
    patch.basis = basis;
    if (basis !== fund.basis) {
      applied.push(`basis ${fund.basis ?? "unset"} to ${basis}`);
    }
    // A fund that no longer quotes a yield must not keep one lying around.
    // current_rate is the field the app taxes and compounds, and a stale value
    // there is one backfill away from undoing this whole import.
    if (basis !== "yield" && fund.current_rate != null) {
      patch.current_rate = null;
      applied.push("cleared the stale current_rate");
    }
  }
  const netOf = str(p.net_of as unknown as Figure);
  if (netOf && NET_OF.includes(netOf)) {
    patch.net_of = netOf;
    applied.push(`net of ${netOf.replace(/_/g, " ")}`);
  }

  // ── terms, allowlisted ───────────────────────────────────────────────────
  const terms = (p.terms ?? {}) as Record<string, Figure>;
  for (const [k, f] of Object.entries(terms)) {
    if (!TERM_COLUMNS.has(k)) { skipped.push(`${k} is not a writable column`); continue; }
    const v = typeof f?.value === "number" || typeof f?.value === "string" ? f.value : null;
    if (v === null || v === "") continue;
    patch[k] = v;
    applied.push(`${k.replace(/_/g, " ")} = ${v}`);
  }

  if (Object.keys(patch).length) {
    await db.from("funds").update(patch).eq("id", imp.fund_id);
  }

  // ── period returns ───────────────────────────────────────────────────────
  const periods = Array.isArray(p.periods) ? p.periods : [];
  const periodRows = [];
  for (const row of periods as unknown as Record<string, unknown>[]) {
    const end = String(row.period_end ?? "");
    const kind = String(row.period ?? "");
    const netPct = typeof row.net_pct === "number" ? row.net_pct : null;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(end) || !PERIODS.includes(kind) || netPct === null) {
      skipped.push(`period row ${end || "?"} ${kind || "?"} was unreadable`);
      continue;
    }
    periodRows.push({
      fund_id: imp.fund_id,
      period_end: end,
      period: kind,
      net_pct: netPct,          // NO sign check: a losing quarter is ordinary
      gross_pct: typeof row.gross_pct === "number" ? row.gross_pct : null,
      net_of: NET_OF.includes(String(row.net_of)) ? String(row.net_of) : (netOf ?? "fees"),
      source: `factsheet:${imp.source_label}`,
    });
  }
  if (periodRows.length) {
    await db.from("return_history").upsert(periodRows, { onConflict: "fund_id,period_end,period" });
    applied.push(`${periodRows.length} period return${periodRows.length === 1 ? "" : "s"}`);
  }

  // ── rate points, with the staleness gate ─────────────────────────────────
  //
  // This is the Old Mutual rule. Its April 2025 sheet quotes 13.4% while the
  // database held 11.37 from a scraper. Importing the sheet wholesale would
  // have replaced a current figure with a fifteen-month-old one and called it
  // an update. So rates are skipped when the fund already holds something
  // newer, while the static terms above still apply, because that same sheet
  // also corrected the minimum investment from 1,000,000 to 50,000.
  const rates = Array.isArray(p.rates) ? p.rates : [];
  if (rates.length) {
    const { data: newer } = await db
      .from("rate_history")
      .select("as_of")
      .eq("fund_id", imp.fund_id)
      .gt("as_of", imp.as_of)
      .limit(1);

    if (newer && newer.length) {
      skipped.push(`${rates.length} rate point(s): the fund already holds a figure newer than ${imp.as_of}`);
    } else {
      const rateRows = [];
      for (const row of rates as unknown as Record<string, unknown>[]) {
        const asOf = String(row.as_of ?? "");
        const rate = typeof row.rate === "number" ? row.rate : null;
        if (!/^\d{4}-\d{2}-\d{2}$/.test(asOf) || rate === null || rate <= 0) {
          skipped.push(`rate row ${asOf || "?"} was unreadable`);
          continue;
        }
        rateRows.push({ fund_id: imp.fund_id, as_of: asOf, rate, source: `factsheet:${imp.source_label}` });
      }
      if (rateRows.length) {
        await db.from("rate_history").upsert(rateRows, { onConflict: "fund_id,as_of" });
        applied.push(`${rateRows.length} rate point${rateRows.length === 1 ? "" : "s"}`);

        // Promote only the newest, and only when the fund quotes a yield.
        const latest = rateRows.reduce((a, b) => (a.as_of >= b.as_of ? a : b));
        const finalBasis = (patch.basis as string) ?? fund.basis ?? "yield";
        if (finalBasis === "yield") {
          await db.from("funds").update({ current_rate: latest.rate }).eq("id", imp.fund_id);
          applied.push(`current rate ${latest.rate}`);
        }
      }
    }
  }

  await db.from("factsheet_imports")
    .update({ status: "applied", reviewed_at: new Date().toISOString() })
    .eq("id", id);

  // Any older pending import for the same fund is now moot.
  await db.from("factsheet_imports")
    .update({ status: "superseded" })
    .eq("fund_id", imp.fund_id)
    .eq("status", "pending")
    .lt("as_of", imp.as_of);

  await republishSnapshot();
  revalidatePath("/admin/factsheets");
  revalidatePath("/admin/funds");
  revalidatePath("/admin");
  return { ok: true, error: null, applied, skipped };
}

export async function rejectFactsheet(formData: FormData) {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  await supabaseAdmin()
    .from("factsheet_imports")
    .update({
      status: "rejected",
      reviewed_at: new Date().toISOString(),
      notes: String(formData.get("notes") ?? "").trim() || null,
    })
    .eq("id", id);
  revalidatePath("/admin/factsheets");
}

/// Attach a staged import to a fund, for payloads that arrived unassigned.
export async function assignFactsheet(formData: FormData) {
  const id = Number(formData.get("id"));
  const fundId = String(formData.get("fund_id") ?? "").trim();
  if (!Number.isFinite(id) || !fundId) return;
  await supabaseAdmin().from("factsheet_imports").update({ fund_id: fundId }).eq("id", id);
  revalidatePath("/admin/factsheets");
}
