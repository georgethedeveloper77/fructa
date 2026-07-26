/// The payload shape and its validator.
///
/// TWO GATES, NOT ONE. This is the machine gate and it runs first, before the
/// review page renders anything. Its job is not to judge whether a figure is
/// right, which needs a person, but to refuse anything structurally incapable
/// of being judged: a number with no caption, a date in the future, a rate of
/// 400%, a missing `excluded` array.
///
/// A reviewer reading twenty sheets a week will approve on rhythm. Everything
/// that can be checked without judgement should be checked here, so the human
/// gate spends its attention on the part that actually needs a human.

export type Figure<T = number | string> = {
  value: T;
  caption?: string;
  reason?: string;
};

export type PeriodRow = {
  period_end: string;
  period: string;
  net_pct: number;
  gross_pct?: number | null;
  net_of?: string;
  caption?: string;
};

export type RateRow = { as_of: string; rate: number; caption?: string };

export type Payload = {
  as_of?: string;
  basis?: Figure<string>;
  net_of?: Figure<string>;
  terms?: Record<string, Figure>;
  periods?: PeriodRow[];
  rates?: RateRow[];
  custody?: Record<string, Figure<string>>;
  excluded: { value: unknown; caption?: string; reason?: string }[];
  warnings?: string[];
  confidence?: number;
};

const BASES = ["yield", "nav", "return", "none"];
const NET_OF = ["nothing", "fees", "fees_and_tax"];
const PERIODS = ["month", "quarter", "half", "year", "ytd", "since_inception"];
const FEE_KINDS = ["mgmt", "service", "none"];

const TERM_KEYS = new Set([
  "min_invest", "top_up_min", "lock_in_months", "mgmt_fee", "expense_ratio",
  "redemption_fee", "perf_fee_pct", "hurdle_pct", "fee_kind", "inception_date",
  "aum_native", "objective", "withdraw_note", "benchmark_key",
  "class_group", "class_label",
]);

const isDate = (s: unknown) =>
  typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));

export type Validation = {
  ok: boolean;
  errors: string[];   // block staging
  warnings: string[]; // shown to the reviewer, do not block
  payload: Payload | null;
};

/// Parse and check a model response.
export function validate(raw: string, sheetDateHint?: string): Validation {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Models fence JSON even when told not to. Strip it rather than fail on it:
  // refusing here would send a reviewer to re-run an extraction that was fine.
  const cleaned = raw.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();

  let p: Payload;
  try {
    p = JSON.parse(cleaned) as Payload;
  } catch {
    return { ok: false, errors: ["The model did not return valid JSON."], warnings, payload: null };
  }

  if ((p as unknown as { error?: string }).error) {
    return {
      ok: false,
      errors: [`Extractor says: ${(p as unknown as { error: string }).error}`],
      warnings, payload: null,
    };
  }

  // ── excluded is required, and its emptiness is information ────────────────
  //
  // Not a formality. Every sheet reviewed so far printed at least one figure
  // that is not a return: a target, an annualised quarter, a benchmark, a
  // pre-fee number, or a neighbouring fund. An empty array is possible and it
  // is worth a second look at the PDF, so it warns rather than blocks.
  if (!Array.isArray(p.excluded)) {
    errors.push("No `excluded` array. The extractor must state which figures on the sheet are not returns.");
  } else if (p.excluded.length === 0) {
    warnings.push("Nothing excluded. Unusual: check the sheet for a target, an annualised column, or a benchmark row.");
  } else {
    p.excluded.forEach((x, i) => {
      if (!x.caption) warnings.push(`Excluded item ${i + 1} has no caption, so it cannot be checked against the sheet.`);
    });
  }

  // ── the sheet's own date ──────────────────────────────────────────────────
  if (!isDate(p.as_of)) {
    errors.push("Missing or unreadable `as_of`. A sheet without a date cannot be ranked against what the fund already holds.");
  } else {
    const today = new Date().toISOString().slice(0, 10);
    if (p.as_of! > today) errors.push(`as_of ${p.as_of} is in the future.`);
    if (sheetDateHint && p.as_of !== sheetDateHint) {
      warnings.push(`Extractor read the sheet date as ${p.as_of}; you entered ${sheetDateHint}.`);
    }
  }

  // ── basis and net_of ──────────────────────────────────────────────────────
  if (p.basis && !BASES.includes(p.basis.value)) {
    errors.push(`basis "${p.basis.value}" is not one of ${BASES.join(", ")}.`);
  }
  if (p.basis && !p.basis.caption) {
    warnings.push("The basis decision has no caption. That decision changes how every number on the fund page is read.");
  }
  if (p.net_of && !NET_OF.includes(p.net_of.value)) {
    errors.push(`net_of "${p.net_of.value}" is not one of ${NET_OF.join(", ")}.`);
  }
  if (!p.net_of && p.basis && p.basis.value !== "none") {
    warnings.push("No net_of. The app will assume net of fees and gross of tax, which is right for most Kenyan funds and wrong for some.");
  }

  // ── terms ─────────────────────────────────────────────────────────────────
  for (const [k, f] of Object.entries(p.terms ?? {})) {
    if (!TERM_KEYS.has(k)) { warnings.push(`Unknown term "${k}" will be ignored on apply.`); continue; }
    if (f?.value === undefined || f.value === null || f.value === "") {
      warnings.push(`Term "${k}" has no value.`);
      continue;
    }
    // THE RULE. A figure with no caption cannot be checked against the sheet,
    // so it is not staged at all.
    if (!f.caption) errors.push(`Term "${k}" has no caption.`);
    if (k === "fee_kind" && !FEE_KINDS.includes(String(f.value))) {
      errors.push(`fee_kind "${f.value}" is not one of ${FEE_KINDS.join(", ")}.`);
    }
    if (k === "inception_date" && !isDate(f.value)) errors.push("inception_date is not a valid date.");
    if (k === "lock_in_months") {
      const n = Number(f.value);
      if (!Number.isFinite(n) || n < 0 || n > 120) errors.push(`lock_in_months ${f.value} is out of range.`);
    }
    if (["mgmt_fee", "expense_ratio", "redemption_fee", "perf_fee_pct", "hurdle_pct"].includes(k)) {
      const n = Number(f.value);
      if (!Number.isFinite(n) || n < 0 || n > 100) errors.push(`${k} ${f.value} is not a plausible percentage.`);
    }
  }

  // ── period returns ────────────────────────────────────────────────────────
  (p.periods ?? []).forEach((r, i) => {
    const at = `period row ${i + 1}`;
    if (!isDate(r.period_end)) errors.push(`${at}: period_end "${r.period_end}" is not a date.`);
    if (!PERIODS.includes(r.period)) errors.push(`${at}: period "${r.period}" is not one of ${PERIODS.join(", ")}.`);
    if (typeof r.net_pct !== "number" || !Number.isFinite(r.net_pct)) {
      errors.push(`${at}: net_pct is not a number.`);
    } else {
      // NO lower bound. A negative return is ordinary and the app is built for
      // it. The upper bound catches a cumulative total mislabelled as a single
      // period, which is the realistic failure: a since-inception 259% filed as
      // a quarter would put one bar off the top of every chart.
      if (r.net_pct > 200 && r.period !== "since_inception") {
        errors.push(`${at}: ${r.net_pct}% for a single ${r.period} is implausible. Is it a since-inception total?`);
      }
      if (r.net_pct < -100) errors.push(`${at}: ${r.net_pct}% would mean losing more than everything.`);
    }
    if (r.gross_pct != null && typeof r.gross_pct === "number" && r.gross_pct < r.net_pct) {
      warnings.push(`${at}: gross ${r.gross_pct}% is below net ${r.net_pct}%. Fees do not work that way; check they are not swapped.`);
    }
    if (r.net_of && !NET_OF.includes(r.net_of)) errors.push(`${at}: net_of "${r.net_of}" is invalid.`);
    if (!r.caption) errors.push(`${at}: no caption.`);
  });

  // ── rate points ───────────────────────────────────────────────────────────
  (p.rates ?? []).forEach((r, i) => {
    const at = `rate row ${i + 1}`;
    if (!isDate(r.as_of)) errors.push(`${at}: as_of "${r.as_of}" is not a date.`);
    if (typeof r.rate !== "number" || !Number.isFinite(r.rate) || r.rate <= 0) {
      errors.push(`${at}: rate is not a positive number.`);
    } else if (r.rate > 40) {
      // Not an error. Cytonn's High Yield Fund genuinely printed 21.9%, and a
      // hard ceiling would have thrown away a real figure. But 40% wants eyes.
      warnings.push(`${at}: ${r.rate}% is far above the market. Real, or a period return mistaken for a yield?`);
    }
    if (!r.caption) errors.push(`${at}: no caption.`);
  });

  // ── shape ─────────────────────────────────────────────────────────────────
  const b = p.basis?.value;
  if (b === "return" && (p.periods ?? []).length === 0) {
    warnings.push("Basis is return but no periods were extracted. The fund page will have nothing to draw.");
  }
  if (b === "yield" && (p.rates ?? []).length === 0) {
    warnings.push("Basis is yield but no rate points were extracted.");
  }
  if ((p.periods ?? []).length > 0 && (p.rates ?? []).length > 0) {
    warnings.push("Both period returns and rate points. A fund normally quotes one or the other; check which the sheet leads with.");
  }
  if (typeof p.confidence === "number" && p.confidence < 0.6) {
    warnings.push(`Extractor reported low confidence (${p.confidence}).`);
  }
  for (const w of p.warnings ?? []) warnings.push(`Extractor: ${w}`);

  return { ok: errors.length === 0, errors, warnings, payload: p };
}
