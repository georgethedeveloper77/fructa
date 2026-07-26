import { EXTRACTION_SYSTEM, userPrompt } from "./prompt";
import { validate, type Validation } from "./schema";
import { checkBudget, recordSpend, fmt } from "./budget";
import { MAX_PDF_BYTES, tooBig } from "./limits";

/// One PDF to one validated payload.
///
/// Deliberately a plain module rather than a route or an action, so Phase 3's
/// scheduled discovery calls exactly the same code path as the admin form. The
/// alternative, a second extractor behind a cron job, is two prompts drifting
/// apart until a fund extracted by hand and the same fund extracted on a
/// schedule disagree.

const MODEL = process.env.FACTSHEET_MODEL ?? "claude-sonnet-4-6";

export type ExtractInput = {
  pdf: ArrayBuffer;
  fundName: string;
  currency: string;
  hint?: string;
  sheetDateHint?: string;
};

export type ExtractOutput = Validation & {
  model: string;
  raw: string | null;
  /** What this call cost, in cents. 0 when nothing was spent. */
  cents: number;
};

/// THE PDF GOES IN AS A DOCUMENT, NOT AS EXTRACTED TEXT, and that is the single
/// most important line in this file.
///
/// Text extraction flattens a page into a stream. Cytonn's sheet becomes
/// "21.9% 16.4% 15.3% AVERAGE 2024 PERFORMANCE SINCE INCEPTION 20.7% 13.2%",
/// in which no reader, human or otherwise, can tell which label owns which
/// number, or which of them is the benchmark. The whole design rests on every
/// figure carrying the caption printed BESIDE it, and beside is a fact about
/// layout that only survives if the model sees the page.
export async function extractFactsheet(input: ExtractInput): Promise<ExtractOutput> {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    return { ok: false, errors: ["ANTHROPIC_API_KEY is not set."], warnings: [], payload: null, model: MODEL, raw: null, cents: 0 };
  }
  if (input.pdf.byteLength === 0) {
    return { ok: false, errors: ["Empty file."], warnings: [], payload: null, model: MODEL, raw: null, cents: 0 };
  }
  // Same ceiling the browser and the framework use, from one constant, so the
  // three cannot drift into contradicting each other.
  const big = tooBig(input.pdf.byteLength);
  if (big) {
    return { ok: false, errors: [big], warnings: [], payload: null, model: MODEL, raw: null, cents: 0 };
  }

  // ── The guard ────────────────────────────────────────────────────────────
  //
  // Before the API, not after. A cap checked afterwards is a cap that is always
  // exceeded exactly once, and the estimate is deliberately generous so the
  // refusal lands before the breach rather than on it.
  const estimate = Math.ceil((input.pdf.byteLength / 3500) * 0.0006) + 6;
  const budget = await checkBudget(estimate);
  if (!budget.allowed) {
    return {
      ok: false, errors: [budget.reason], warnings: [], payload: null,
      model: MODEL, raw: null, cents: 0,
    };
  }

  const b64 = Buffer.from(input.pdf).toString("base64");

  let res: Response;
  try {
    res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 8000,
        // Zero temperature. Not for quality: for REPRODUCIBILITY. When a
        // reviewer disputes a figure, re-running must produce the same answer,
        // otherwise there is no way to tell a prompt problem from a sampling
        // one.
        temperature: 0,
        system: EXTRACTION_SYSTEM,
        messages: [{
          role: "user",
          content: [
            { type: "document", source: { type: "base64", media_type: "application/pdf", data: b64 } },
            { type: "text", text: userPrompt(input.fundName, input.currency, input.hint) },
          ],
        }],
      }),
    });
  } catch (e) {
    // Nothing reached the API, so nothing was billed, but the attempt is
    // recorded: a source that fails on every run is a loop worth seeing.
    await recordSpend({ purpose: "factsheet", model: MODEL, ok: false, error: String(e), ref: input.fundName });
    return { ok: false, errors: [`Could not reach the API: ${String(e)}`], warnings: [], payload: null, model: MODEL, raw: null, cents: 0 };
  }

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    await recordSpend({ purpose: "factsheet", model: MODEL, ok: false, error: `${res.status} ${body.slice(0, 200)}`, ref: input.fundName });
    return { ok: false, errors: [`API ${res.status}: ${body.slice(0, 300)}`], warnings: [], payload: null, model: MODEL, raw: null, cents: 0 };
  }

  const data = await res.json() as {
    content?: { type: string; text?: string }[];
    usage?: { input_tokens?: number; output_tokens?: number };
  };

  // Billed from the API's OWN token counts, never from an estimate. The
  // estimate exists to decide whether to spend; this decides what was spent.
  const cents = await recordSpend({
    purpose: "factsheet",
    model: MODEL,
    inputTokens: data.usage?.input_tokens,
    outputTokens: data.usage?.output_tokens,
    ok: true,
    ref: input.fundName,
  });
  const raw = (data.content ?? [])
    .filter((c) => c.type === "text")
    .map((c) => c.text ?? "")
    .join("\n")
    .trim();

  if (!raw) {
    return { ok: false, errors: ["The model returned no text."], warnings: [], payload: null, model: MODEL, raw: null, cents };
  }

  const v = validate(raw, input.sheetDateHint);
  const spent = budget.spentCents + cents;
  v.warnings.push(`Cost ${fmt(cents)}. Month to date ${fmt(spent)} of ${fmt(budget.capCents)}.`);
  return { ...v, model: MODEL, raw, cents };
}

/// Fetch a fact sheet by URL, for sources whose filenames are constructible.
/// Cytonn's are: chyf-fact-sheet-{mon}-{yy}.pdf, confirmed across five months.
export async function fetchPdf(url: string): Promise<{ pdf: ArrayBuffer | null; error: string | null }> {
  try {
    const res = await fetch(url, { redirect: "follow" });
    if (!res.ok) return { pdf: null, error: `${res.status} fetching the PDF.` };
    const type = res.headers.get("content-type") ?? "";
    const buf = await res.arrayBuffer();
    // Content-type is unreliable on these hosts, so sniff the magic bytes. A
    // 404 page served as 200 is otherwise a very confusing extraction.
    const magic = Buffer.from(buf.slice(0, 5)).toString("latin1");
    if (!magic.startsWith("%PDF") && !type.includes("pdf")) {
      return { pdf: null, error: "That URL did not return a PDF." };
    }
    return { pdf: buf, error: null };
  } catch (e) {
    return { pdf: null, error: String(e) };
  }
}
