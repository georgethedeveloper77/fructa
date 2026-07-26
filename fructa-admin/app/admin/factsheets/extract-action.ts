"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { fetchPdf } from "@/lib/factsheet/extract";
import { runPipeline, type Tier } from "@/lib/factsheet/pipeline";
import { revalidatePath } from "next/cache";

export interface ExtractActionResult {
  ok: boolean;
  id: number | null;
  errors: string[];
  warnings: string[];
  /** Rendered back so a reviewer can see what was seen and not used. */
  excluded: { value: unknown; caption?: string; reason?: string }[];
  model: string | null;
  duplicateOf: number | null;
  /** Which tier resolved it. `anchored` means it cost nothing. */
  tier: Tier | null;
  /** Actually spent, in cents. 0 on every free tier. */
  cents: number;
  /** What the model WOULD cost, shown when the free path could not resolve it. */
  estimateCents: number;
}

const fail = (e: string): ExtractActionResult => ({
  ok: false, id: null, errors: [e], warnings: [], excluded: [],
  model: null, duplicateOf: null, tier: null, cents: 0, estimateCents: 0,
});

/// Upload or fetch a fact sheet and run it through the pipeline.
///
/// THIS NOW GOES THROUGH runPipeline, and that is the point of the change.
/// Before, it called extractFactsheet directly, so hash-dedupe, the staleness
/// prefilter and the anchor tier all existed and none of them ran. Every sheet
/// cost six cents whether it needed to or not.
///
/// Writes nothing to funds either way: the result lands in the review queue and
/// goes through the same human gate as a hand-written payload.
export async function extractAndStage(formData: FormData): Promise<ExtractActionResult> {
  const fundId = String(formData.get("fund_id") ?? "").trim();
  const url = String(formData.get("source_url") ?? "").trim();
  const hint = String(formData.get("hint") ?? "").trim() || undefined;
  const sourceId = String(formData.get("source_id") ?? "").trim() || undefined;
  const file = formData.get("file") as File | null;

  // Present and default TRUE, because a person clicked a button labelled
  // Extract. A scheduled caller passes runPipeline `allowModel: false` and can
  // never spend; a human pressing this one has already decided to.
  const allowModel = String(formData.get("allow_model") ?? "1") !== "0";

  if (!fundId) {
    return fail("Pick the fund this sheet is for. Naming it removes any chance the extractor picks the wrong fund out of a six-fund deck.");
  }

  const db = supabaseAdmin();
  const { data: fund } = await db.from("funds").select("id").eq("id", fundId).single();
  if (!fund) return fail("That fund no longer exists.");

  // ── bytes ────────────────────────────────────────────────────────────────
  let pdf: ArrayBuffer;
  if (file && file.size > 0) {
    pdf = await file.arrayBuffer();
  } else if (url) {
    const got = await fetchPdf(url);
    if (!got.pdf) return fail(got.error ?? "Could not fetch that URL.");
    pdf = got.pdf;
  } else {
    return fail("Upload a PDF or give a URL.");
  }

  // ── the pipeline ─────────────────────────────────────────────────────────
  //
  // Hash, then staleness, then anchors, then the model. Dedupe and the sheet's
  // own date are handled inside, so neither is repeated here; doing it in two
  // places is how the two answers start to disagree.
  const r = await runPipeline({
    pdf,
    fundId,
    sourceUrl: url || null,
    sourceId: sourceId ?? null,
    allowModel,
    hint,
  });

  revalidatePath("/admin/factsheets");

  const shared = {
    tier: r.tier,
    cents: r.cents,
    estimateCents: r.estimateCents,
    warnings: r.warnings,
    model: null as string | null,
  };

  switch (r.tier) {
    case "duplicate":
      return {
        ...shared, ok: false, id: null, excluded: [], errors: [r.reason],
        // Parsed back out of the reason so the UI can link to the existing row
        // rather than making a reviewer go and find it.
        duplicateOf: Number(r.reason.match(/#(\d+)/)?.[1] ?? 0) || null,
      };

    case "skipped":
      // Not a failure. The sheet was older than what the fund already holds, or
      // the fund is not in the document. Both are correct outcomes that cost
      // nothing, and calling them errors would train a reviewer to ignore them.
      return { ...shared, ok: false, id: null, excluded: [], errors: [r.reason], duplicateOf: null };

    case "needs_model":
      return { ...shared, ok: false, id: null, excluded: [], errors: [r.reason], duplicateOf: null };

    case "error":
      return { ...shared, ok: false, id: null, excluded: [], errors: r.errors.length ? r.errors : [r.reason], duplicateOf: null };

    case "anchored":
    case "extracted":
      return {
        ...shared,
        ok: true,
        id: r.importId,
        errors: [],
        excluded: r.payload?.excluded ?? [],
        model: r.tier === "anchored" ? "recipe (no model)" : (process.env.FACTSHEET_MODEL ?? "claude-sonnet-4-6"),
        duplicateOf: null,
      };
  }
}
