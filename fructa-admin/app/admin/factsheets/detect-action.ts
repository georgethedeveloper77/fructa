"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { pdfText } from "@/lib/factsheet/prefilter";
import { fetchPdf } from "@/lib/factsheet/extract";
import { detectFunds, shouldAutoSelect, detectCurrency, type Candidate } from "@/lib/factsheet/detect";

export interface DetectResult {
  ok: boolean;
  error: string | null;
  candidates: {
    id: string; name: string; currency: string; manager: string | null;
    score: number; matched: string[]; exact: boolean; currencyAgrees: boolean;
  }[];
  /// Preselect this one. Null when nothing is clear enough to choose for you.
  autoId: string | null;
  detectedCurrency: string | null;
  detectedAsOf: string | null;
  pages: number;
  /// The opening lines, so a reviewer can see what the detector read.
  preview: string;
}

const fail = (e: string): DetectResult => ({
  ok: false, error: e, candidates: [], autoId: null,
  detectedCurrency: null, detectedAsOf: null, pages: 0, preview: "",
});

/// Read a PDF and work out which fund it is about. FREE: no model, no spend.
///
/// Runs the moment a file is chosen, before anything is extracted, so the
/// operator is confirming a suggestion rather than hunting through a dropdown
/// of two hundred funds for the one already printed at the top of the page.
export async function detectFromPdf(formData: FormData): Promise<DetectResult> {
  const url = String(formData.get("source_url") ?? "").trim();
  const file = formData.get("file") as File | null;

  let pdf: ArrayBuffer;
  let filename = "";
  if (file && file.size > 0) {
    pdf = await file.arrayBuffer();
    filename = file.name;
  } else if (url) {
    const got = await fetchPdf(url);
    if (!got.pdf) return fail(got.error ?? "Could not fetch that URL.");
    pdf = got.pdf;
    filename = url.split("/").pop() ?? "";
  } else {
    return fail("Choose a PDF or paste a URL first.");
  }

  let text = "";
  let pages = 0;
  try {
    const r = await pdfText(pdf);
    text = r.text;
    pages = r.pages;
  } catch {
    return fail("No text layer in that PDF. It is probably a scan, so pick the fund by hand and let the model read it.");
  }
  if (!text.trim()) {
    return fail("That PDF has no readable text. Pick the fund by hand; the model can still read a scan.");
  }

  const { data: funds } = await supabaseAdmin()
    .from("funds")
    .select("id,name,currency,manager")
    .eq("kind", "fund")
    .order("name");

  const cands: Candidate[] = detectFunds(text, funds ?? [], filename);

  // Date detection is deliberately NOT done here.
  //
  // prefilter and the extractor each read the sheet's date for their own
  // purposes, and a third reading in the UI would be a third answer to compare.
  // What the operator needs at this point is only which fund.
  return {
    ok: true,
    error: null,
    candidates: cands.map((c) => ({
      id: c.fund.id,
      name: c.fund.name,
      currency: c.fund.currency,
      manager: c.fund.manager ?? null,
      score: c.score,
      matched: c.matched,
      exact: c.exact,
      currencyAgrees: c.currencyAgrees,
    })),
    autoId: shouldAutoSelect(cands) ? cands[0].fund.id : null,
    detectedCurrency: detectCurrency(text.slice(0, 6000)),
    detectedAsOf: null,
    pages,
    preview: text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(0, 3).join("  /  ").slice(0, 220),
  };
}
