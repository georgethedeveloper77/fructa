import { createHash } from "crypto";
import { supabaseAdmin } from "@/lib/supabase/server";
import { prefilter, estimateCents } from "./prefilter";
import { extractByAnchors, type Recipe } from "./anchors";
import { extractFactsheet } from "./extract";
import { validate, type Payload } from "./schema";

/// The orchestrator.
///
/// Four modules existed and nothing called them in order, so every extraction
/// went straight to the model and the free tiers cost money anyway. This is the
/// file that makes the ordering real.
///
///   1  HASH      seen this exact PDF before                     free
///   2  PREFILTER fund absent, or sheet older than what we hold   free
///   3  ANCHORS   read it with the manager's stored recipe        free
///   4  MODEL     six cents, and only if asked                    paid
///
/// Tier 4 NEVER runs unless the caller passes allowModel. Discovery on a
/// schedule calls this without it, so a scheduled run can resolve a sheet for
/// nothing or report that it needs a human, and can never spend.

export type Tier = "duplicate" | "skipped" | "anchored" | "needs_model" | "extracted" | "error";

export type PipelineResult = {
  tier: Tier;
  reason: string;
  payload: Payload | null;
  /// Staged import id, when one was created.
  importId: number | null;
  cents: number;
  /// What tier 4 would cost, so a caller can show the price before spending.
  estimateCents: number;
  sha: string | null;
  detectedAsOf: string | null;
  errors: string[];
  warnings: string[];
};

const base = (t: Tier, reason: string): PipelineResult => ({
  tier: t, reason, payload: null, importId: null, cents: 0,
  estimateCents: 0, sha: null, detectedAsOf: null, errors: [], warnings: [],
});

export type RunInput = {
  pdf: ArrayBuffer;
  fundId: string;
  sourceUrl?: string | null;
  sourceId?: string | null;
  /// Tier 4 is opt-in, per call, always.
  allowModel?: boolean;
  hint?: string;
};

export async function runPipeline(input: RunInput): Promise<PipelineResult> {
  const db = supabaseAdmin();

  const { data: fund } = await db
    .from("funds").select("id,name,currency,source_type").eq("id", input.fundId).single();
  if (!fund) return base("error", "That fund does not exist.");

  // ── 1. Hash ──────────────────────────────────────────────────────────────
  const sha = createHash("sha256").update(Buffer.from(input.pdf)).digest("hex");
  const { data: seen } = await db
    .from("factsheet_imports").select("id,status").eq("pdf_sha256", sha).maybeSingle();
  if (seen) {
    return { ...base("duplicate", `Already staged as #${seen.id} (${seen.status}).`), sha };
  }

  // ── 2. Prefilter ─────────────────────────────────────────────────────────
  //
  // Needs the newest as_of already held, which is what turns "is this sheet
  // old" from a judgement into a comparison.
  const { data: held } = await db
    .from("factsheet_imports")
    .select("as_of").eq("fund_id", input.fundId).eq("status", "applied")
    .order("as_of", { ascending: false }).limit(1).maybeSingle();

  const pre = await prefilter(input.pdf, fund.name as string, held?.as_of ?? null);
  const est = estimateCents(pre.estimatedTokens);

  if (!pre.proceed) {
    return {
      ...base("skipped", pre.reason),
      sha, detectedAsOf: pre.detectedAsOf, estimateCents: est,
    };
  }

  // ── 3. Anchors ───────────────────────────────────────────────────────────
  //
  // Only when this manager has a recipe AND it has not been failing. Three
  // consecutive failures means they redesigned, and retrying a dead recipe on
  // every sheet just delays the fallback while producing confusing errors.
  if (input.sourceId) {
    const { data: src } = await db
      .from("factsheet_sources")
      .select("recipe,recipe_fail_count")
      .eq("id", input.sourceId).maybeSingle();

    const recipe = src?.recipe as Recipe | null;
    const fails = Number(src?.recipe_fail_count ?? 0);

    if (recipe && fails < 3) {
      // Reuse the text prefilter already read. Re-parsing was both wasteful
      // and, under pdf-parse v2, impossible: the first read detaches the
      // buffer.
      const text = pre.text;
      const anchored = extractByAnchors(text, recipe);

      if (anchored.payload) {
        // The same validator the model's output faces. This is the whole reason
        // a brittle recipe is safe: a stale one produces validation ERRORS, not
        // wrong numbers, and errors route to a human rather than to the funds
        // table.
        const v = validate(JSON.stringify(anchored.payload));
        if (v.ok && v.payload) {
          const id = await stage(db, {
            fundId: input.fundId,
            fundName: fund.name as string,
            payload: { ...v.payload, _tier: "anchors", _source: input.sourceId },
            sha,
            url: input.sourceUrl ?? null,
            notes: v.warnings.join(" | ") || null,
          });
          await db.from("factsheet_sources")
            .update({ recipe_fail_count: 0 }).eq("id", input.sourceId);
          await logCheck(db, input.sourceId, input.sourceUrl, sha, "anchored", pre, "Read by recipe, no model.");
          return {
            ...base("anchored", `Read with ${input.sourceId}'s recipe. Cost nothing.`),
            payload: v.payload, importId: id, sha,
            detectedAsOf: v.payload.as_of ?? pre.detectedAsOf,
            estimateCents: est, warnings: v.warnings,
          };
        }
        // Failed validation: count it, so a redesigned layout stops being tried.
        await db.from("factsheet_sources")
          .update({ recipe_fail_count: fails + 1 }).eq("id", input.sourceId);
      }
    }
  }

  // ── 4. The model, only if asked ──────────────────────────────────────────
  if (!input.allowModel) {
    await logCheck(db, input.sourceId, input.sourceUrl, sha, "needs_model", pre,
      "Free tiers could not resolve it. Waiting on a human to approve the spend.");
    return {
      ...base("needs_model",
        `The free path could not read this one. Extracting with the model costs about ${(est / 100).toFixed(2)} dollars.`),
      sha, detectedAsOf: pre.detectedAsOf, estimateCents: est,
    };
  }

  const out = await extractFactsheet({
    pdf: input.pdf,
    fundName: fund.name as string,
    currency: fund.currency as string,
    hint: input.hint,
    sheetDateHint: pre.detectedAsOf ?? undefined,
  });

  if (!out.ok || !out.payload) {
    await logCheck(db, input.sourceId, input.sourceUrl, sha, "error", pre, out.errors.join(" | "));
    return {
      ...base("error", "Extraction failed."),
      sha, detectedAsOf: pre.detectedAsOf, estimateCents: est,
      cents: out.cents, errors: out.errors, warnings: out.warnings,
    };
  }

  const id = await stage(db, {
    fundId: input.fundId,
    fundName: fund.name as string,
    payload: { ...out.payload, _tier: "model", _model: out.model },
    sha,
    url: input.sourceUrl ?? null,
    notes: out.warnings.join(" | ") || null,
  });
  await logCheck(db, input.sourceId, input.sourceUrl, sha, "new", pre, `Extracted by ${out.model}.`);

  return {
    ...base("extracted", `Extracted with ${out.model}.`),
    payload: out.payload, importId: id, sha,
    detectedAsOf: out.payload.as_of ?? pre.detectedAsOf,
    estimateCents: est, cents: out.cents, warnings: out.warnings,
  };
}

/// Stage a payload. Identical for anchors and model output, deliberately: the
/// review page must not treat one as more trustworthy than the other, and the
/// _tier marker in the payload is there for the reviewer to read, not for the
/// writer to branch on.
async function stage(
  db: ReturnType<typeof supabaseAdmin>,
  a: { fundId: string; fundName: string; payload: Record<string, unknown>; sha: string; url: string | null; notes: string | null },
): Promise<number | null> {
  const { data } = await db.from("factsheet_imports").insert({
    fund_id: a.fundId,
    source_label: `${a.fundName} ${a.payload.as_of ?? ""}`.trim(),
    source_url: a.url,
    as_of: a.payload.as_of,
    payload: a.payload,
    confidence: typeof a.payload.confidence === "number" ? a.payload.confidence : null,
    pdf_sha256: a.sha,
    notes: a.notes,
    status: "pending",
  }).select("id").single();
  return (data?.id as number) ?? null;
}

async function logCheck(
  db: ReturnType<typeof supabaseAdmin>,
  sourceId: string | null | undefined,
  url: string | null | undefined,
  sha: string,
  outcome: string,
  pre: { pages: number; detectedAsOf: string | null },
  note: string,
) {
  if (!sourceId) return;
  await db.from("factsheet_checks").insert({
    source_id: sourceId,
    url: url ?? null,
    pdf_sha256: sha,
    changed: true,
    detected_as_of: pre.detectedAsOf,
    pages: pre.pages,
    outcome,
    note,
  });
}
