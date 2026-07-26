import { PDFParse } from "pdf-parse";

/// Text layer and page count from a PDF.
///
/// The ONE place the library is touched, and it is exported so pipeline.ts uses
/// this rather than opening its own parser. Two call sites meant two chances to
/// forget destroy(), and pdf-parse v2 wraps pdfjs, which holds a worker open
/// until you do.
///
/// v2 is not v1 with a new version number. v1 exported a default function you
/// called with a Buffer; v2 exports a PDFParse class, takes a Uint8Array, and
/// returns { text, pages, total } from getText(). Nothing about the old call
/// survives, which is why the import alone failed to resolve.
export async function pdfText(buf: ArrayBuffer): Promise<{ text: string; pages: number }> {
  // COPY. Not a view.
  //
  // pdf-parse v2 hands the array to pdfjs, which TRANSFERS it to its worker and
  // leaves the caller holding a detached buffer. `new Uint8Array(buf)` is a
  // view onto the original, so the caller's PDF is destroyed by the act of
  // reading it, and every later use fails with "Cannot perform Construct on a
  // detached ArrayBuffer".
  //
  // That is fatal to the pipeline specifically, because it reads the same PDF
  // up to three times: prefilter for the date, anchors for the text, and
  // base64 for the model. Under v1 this was free; under v2 the second read
  // throws. buf.slice(0) allocates a fresh ArrayBuffer, so pdfjs consumes the
  // copy and the caller keeps its own.
  const parser = new PDFParse({ data: new Uint8Array(buf.slice(0)) });
  try {
    const r = await parser.getText();
    return { text: r.text ?? "", pages: r.total ?? 0 };
  } finally {
    // In a finally, not after the return. A malformed sheet throws inside
    // getText and the worker would otherwise stay open for the life of the
    // process, which on a long-running server is a leak per bad PDF.
    await parser.destroy();
  }
}

/// The free tier.
///
/// Three checks that cost nothing and, on a weekly schedule across forty
/// managers, remove most of the calls that would otherwise be made. Runs BEFORE
/// extract.ts, never after.
///
/// The point is not that the model is expensive. At roughly six cents a sheet
/// it is cheaper than the database it writes to. The point is that most fetches
/// on a schedule are of documents that have not changed, do not contain the
/// fund, or are older than what we already hold, and paying anything at all to
/// rediscover that is silly.
///
/// Uses `pdf-parse`, which is a text layer read in pure JS. It cannot tell you
/// which caption sits beside which number, which is exactly why extraction
/// still needs the model. It can tell you whether a fund is mentioned and what
/// date is on the page, and those two facts are enough to skip.
///
///   npm i pdf-parse

export type Prefilter = {
  proceed: boolean;
  reason: string;
  /** Sheet date read off the page, when one could be found. */
  detectedAsOf: string | null;
  /** Page count, for the cost estimate shown in admin. */
  pages: number;
  /** Rough token estimate, so a reviewer sees what a run will cost. */
  estimatedTokens: number;
  /** The text layer, already read. Passed on so no caller parses the same PDF
   *  twice: the anchor tier needs exactly this and used to re-open the file. */
  text: string;
};

const MONTHS = [
  "january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december",
];

/// Words that carry no identifying power, so a fund is not matched on them.
/// Without this, "Special Fund" alone matches every sheet in the corpus.
const NOISE = new Set([
  "fund", "funds", "the", "and", "of", "a", "kes", "usd", "shilling", "dollar",
  "unit", "trust", "scheme", "special", "limited", "ltd", "plc", "investment",
  "investments", "asset", "managers", "management", "capital",
]);

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9\s]/g, " ");

/// Distinctive words from a fund name: the ones that would actually appear on
/// its own sheet and not on a sibling's.
function keyTerms(fundName: string): string[] {
  return norm(fundName)
    .split(/\s+/)
    .filter((w) => w.length > 2 && !NOISE.has(w));
}

/// Find the date the sheet is FOR.
///
/// Tries the formats these managers actually use, in order of how unambiguous
/// they are. Returns the LATEST plausible date found rather than the first,
/// because sheets carry an issue date and a period date and quote historical
/// months throughout the commentary; the newest is the one that describes the
/// document.
///
/// Never returns a future date. African Alliance's June 2026 sheet carries a
/// July 2026 issue stamp, and the period is what matters.
export function detectSheetDate(text: string, today = new Date()): string | null {
  const t = text.toLowerCase();
  const found: string[] = [];
  const todayIso = today.toISOString().slice(0, 10);

  // 31/03/2026 and 31-03-2026
  for (const m of t.matchAll(/\b(\d{1,2})[/-](\d{1,2})[/-](20\d{2})\b/g)) {
    const [, d, mo, y] = m;
    found.push(`${y}-${mo.padStart(2, "0")}-${d.padStart(2, "0")}`);
  }
  // 2026-03-31
  for (const m of t.matchAll(/\b(20\d{2})-(\d{2})-(\d{2})\b/g)) found.push(m[0]);

  // "March 2026", "Mar 2026", "Q1 2026", "Jun-26"
  for (const m of t.matchAll(/\b([a-z]{3,9})[\s-]+(20\d{2}|\d{2})\b/g)) {
    const mi = MONTHS.findIndex((x) => x.startsWith(m[1]) && m[1].length >= 3);
    if (mi < 0) continue;
    const yr = m[2].length === 2 ? `20${m[2]}` : m[2];
    const last = new Date(Number(yr), mi + 1, 0).getDate();
    found.push(`${yr}-${String(mi + 1).padStart(2, "0")}-${last}`);
  }
  for (const m of t.matchAll(/\bq([1-4])[''\s-]*(20\d{2})\b/g)) {
    const endMonth = Number(m[1]) * 3;
    const last = new Date(Number(m[2]), endMonth, 0).getDate();
    found.push(`${m[2]}-${String(endMonth).padStart(2, "0")}-${last}`);
  }

  const valid = found
    .filter((d) => !Number.isNaN(Date.parse(d)) && d <= todayIso && d >= "2015-01-01")
    .sort();
  return valid.length ? valid[valid.length - 1] : null;
}

export async function prefilter(
  buf: ArrayBuffer,
  fundName: string,
  /** Newest as_of already held for this fund, if any. */
  heldAsOf?: string | null,
): Promise<Prefilter> {
  let text = "";
  let pages = 0;
  try {
    const parsed = await pdfText(buf);
    text = parsed.text;
    pages = parsed.pages;
  } catch {
    // A scanned sheet has no text layer. That is not a reason to skip: it is
    // precisely the case where the model earns its keep, because OCR and layout
    // are what it is for. Proceed and let extraction handle it.
    return {
      proceed: true,
      reason: "No text layer, so this is probably a scan. Extracting.",
      detectedAsOf: null,
      pages: 0,
      estimatedTokens: 12000,
      text: "",
    };
  }

  const estimatedTokens = pages * 2500 + 2000;
  const detectedAsOf = detectSheetDate(text);

  // ── 1. Is the fund even in here? ─────────────────────────────────────────
  //
  // Half these documents are range decks. Lofty-Corban's has six funds, Old
  // Mutual's six, Etica's eight. Asking for a fund that is not in the file
  // wastes a call and, worse, invites the model to answer about a neighbour.
  const hay = norm(text);
  const terms = keyTerms(fundName);
  const hits = terms.filter((w) => hay.includes(w));
  if (terms.length > 0 && hits.length === 0) {
    return {
      proceed: false,
      reason: `No sign of "${fundName}" in this document. Nothing matched on ${terms.join(", ")}.`,
      detectedAsOf, pages, estimatedTokens, text,
    };
  }

  // ── 2. Is it older than what we already hold? ────────────────────────────
  //
  // The biggest saver, and the one that would have caught Old Mutual. Its April
  // 2025 booklet quotes 13.4% while the database holds a newer 11.37 from a
  // scraper; importing it would have replaced a current figure with a
  // fifteen-month-old one. Here it costs nothing to find that out.
  //
  // Same date is allowed through: a manager reissuing a corrected sheet keeps
  // the period and fixes a number.
  if (detectedAsOf && heldAsOf && detectedAsOf < heldAsOf) {
    return {
      proceed: false,
      reason: `Sheet is dated ${detectedAsOf}; we already hold ${heldAsOf}. Older, so skipped.`,
      detectedAsOf, pages, estimatedTokens, text,
    };
  }

  // ── 3. Sanity ────────────────────────────────────────────────────────────
  if (pages > 40) {
    return {
      proceed: false,
      reason: `${pages} pages. This looks like an annual report rather than a fact sheet. Extract the relevant pages first.`,
      detectedAsOf, pages, estimatedTokens, text,
    };
  }

  return {
    proceed: true,
    reason: detectedAsOf
      ? `Dated ${detectedAsOf}, ${pages} pages, mentions ${hits.join(", ")}.`
      : `${pages} pages, no date found on the page. Confirm it yourself after extracting.`,
    detectedAsOf, pages, estimatedTokens, text,
  };
}

/// What a run will cost, in cents, for the admin to show before spending it.
/// Rough by design: the point is order of magnitude, not accounting.
export function estimateCents(tokens: number, outTokens = 1500): number {
  const inUsd = (tokens / 1_000_000) * 3;
  const outUsd = (outTokens / 1_000_000) * 15;
  return Math.round((inUsd + outUsd) * 100 * 100) / 100;
}
