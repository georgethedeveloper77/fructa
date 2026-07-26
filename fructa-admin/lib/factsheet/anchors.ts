import type { Payload, Figure } from "./schema";

/// Tier 2: read a fact sheet with no model at all.
///
/// A fact sheet is mostly a label-value table. "Minimum Investment: KES 250,000"
/// needs no intelligence to read once you know the label, and the label is
/// stable per manager across years. So a recipe learned once serves every sheet
/// that manager publishes until they redesign.
///
/// WHY THIS IS SAFE DESPITE BEING BRITTLE
///
/// It is brittle. A layout change breaks it. The safety does not come from
/// reliability, it comes from the output going through the SAME validator as
/// the model's. A missed anchor produces an absent field, and an absent
/// required field produces a validation error, and a validation error routes to
/// the model instead of to the database. A stale recipe costs a fallback, not a
/// wrong number.
///
/// The one thing it CANNOT do is judgement. It cannot look at "20%" and decide
/// it is a target. That knowledge lives in the recipe's `exclude` list, learned
/// once per manager from a sheet a human or a model has already read.

export type Anchor = {
  /// Text immediately before the value, as printed. "Minimum Investment:"
  after?: string;
  /// Or a regex with one capture group, for values not in label-value form.
  pattern?: string;
  /// A constant, for facts that never change on a manager's sheets.
  value?: string | number;
  kind?: "percent" | "money" | "months" | "date" | "text" | "monthYear";
  /// How far past the label to look. Defaults to 120 characters, which spans a
  /// table cell without reaching the next row.
  within?: number;
};

export type Recipe = {
  as_of?: Anchor;
  basis?: Anchor;
  net_of?: Anchor;
  rate?: Anchor;
  terms?: Record<string, Anchor>;
  custody?: Record<string, Anchor>;
  /// Label fragments that sit above numbers which are NOT returns, on this
  /// manager's sheets. Required: a recipe without one fails validation, which
  /// is intended, because every sheet reviewed so far printed at least one.
  exclude?: string[];
};

export type AnchorResult = {
  payload: Payload | null;
  /// Which anchors found nothing. The diagnosis when a recipe goes stale.
  missed: string[];
  hit: number;
};

const MONTHS = [
  "january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december",
];

/// Collapse the whitespace a PDF text layer scatters through a line, so
/// "Minimum   Investment  :" matches "Minimum Investment:".
const flat = (s: string) => s.replace(/\s+/g, " ").trim();

/// Pull a value using one anchor, and return the SPAN IT CAME FROM as the
/// caption.
///
/// The caption is not decoration here. The whole pipeline rests on every figure
/// carrying the words printed beside it, and an anchor extraction gets that for
/// free and truthfully: the caption IS the matched text, so it cannot be
/// invented or paraphrased the way a model's could.
function read(text: string, a: Anchor, label: string): Figure | null {
  if (a.value !== undefined) {
    return { value: a.value, caption: `${label} (from recipe, not read off the sheet)` };
  }

  let span: string | null = null;

  if (a.pattern) {
    const m = text.match(new RegExp(a.pattern, "i"));
    if (!m) return null;
    span = m[1] ?? m[0];
  } else if (a.after) {
    // LINE AWARE, not document-flat.
    //
    // Flattening the whole document was the mistake. A fact sheet's key facts
    // are a table, and a table row IS the unit: "Trustee: Goal Advisory" ends
    // where the line ends. Flattened, that row runs into the next one and
    // "Goal Advisory" comes back as "Goal Advisory Custodian: SBM", after which
    // every attempt to trim it is guesswork about where a cell stopped.
    //
    // So match within a line and take the remainder of that line. The value
    // sometimes wraps, so one following line is appended when the matched line
    // has nothing after the label.
    const needle = flat(a.after).toLowerCase();
    const lines = text.split(/\r?\n/).map(flat).filter(Boolean);
    let found = -1;
    let at = -1;
    for (let li = 0; li < lines.length; li++) {
      const k = lines[li].toLowerCase().indexOf(needle);
      if (k >= 0) { found = li; at = k; break; }
    }
    if (found < 0) return null;
    const rest = lines[found].slice(at);
    span = rest.length > needle.length + 1
      ? rest
      : `${rest} ${lines[found + 1] ?? ""}`;
    if (a.within) span = span.slice(0, needle.length + a.within);
  } else {
    return null;
  }

  const caption = flat(span).slice(0, 160);
  const tail = a.after ? caption.slice(flat(a.after).length) : caption;

  switch (a.kind ?? "text") {
    case "percent": {
      const m = tail.match(/(-?\d+(?:\.\d+)?)\s*%/);
      // No sign restriction: Lofty-Corban Global Asset printed -0.73% and a
      // reader that refuses negatives silently drops the losing months.
      return m ? { value: Number(m[1]), caption } : null;
    }
    case "money": {
      const m = tail.match(/([\d][\d,\s]*(?:\.\d+)?)/);
      if (!m) return null;
      const n = Number(m[1].replace(/[,\s]/g, ""));
      return Number.isFinite(n) ? { value: n, caption } : null;
    }
    case "months": {
      const m = tail.match(/(\d+)\s*month/i);
      if (m) return { value: Number(m[1]), caption };
      if (/no\s+lock/i.test(tail)) return { value: 0, caption };
      return null;
    }
    case "date": {
      const iso = tail.match(/\b(20\d{2})-(\d{2})-(\d{2})\b/);
      if (iso) return { value: iso[0], caption };
      const dmy = tail.match(/\b(\d{1,2})[/-](\d{1,2})[/-](20\d{2})\b/);
      if (dmy) {
        return {
          value: `${dmy[3]}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`,
          caption,
        };
      }
      return monthYear(tail, caption);
    }
    case "monthYear":
      return monthYear(tail, caption);
    default: {
      // No label-cutting heuristic here any more. Matching is line aware, so a
      // value already ends where its row ends, and trimming further was cutting
      // real values short: "Goal Advisory" became "Goal".
      const t = flat(tail).replace(/^[:\s-]+/, "").trim().slice(0, 200);
      return t ? { value: t, caption } : null;
    }
  }
}

/// "March 2026" or "Q1 2026" to the LAST DAY of that period, which is what a
/// period end means everywhere else in the schema.
function monthYear(s: string, caption: string): Figure | null {
  const q = s.match(/\bq([1-4])[''\s-]*(20\d{2})\b/i);
  if (q) {
    const m = Number(q[1]) * 3;
    const last = new Date(Number(q[2]), m, 0).getDate();
    return { value: `${q[2]}-${String(m).padStart(2, "0")}-${last}`, caption };
  }
  const m = s.match(/\b([A-Za-z]{3,9})[\s,-]+(20\d{2}|\d{2})\b/);
  if (!m) return null;
  const mi = MONTHS.findIndex((x) => x.startsWith(m[1].toLowerCase()));
  if (mi < 0) return null;
  const yr = m[2].length === 2 ? `20${m[2]}` : m[2];
  const last = new Date(Number(yr), mi + 1, 0).getDate();
  return { value: `${yr}-${String(mi + 1).padStart(2, "0")}-${last}`, caption };
}

/// Apply a recipe to a text layer. Costs nothing.
export function extractByAnchors(text: string, recipe: Recipe): AnchorResult {
  const missed: string[] = [];
  let hit = 0;

  const take = (a: Anchor | undefined, label: string): Figure | null => {
    if (!a) return null;
    const f = read(text, a, label);
    if (f) hit++;
    else missed.push(label);
    return f;
  };

  const asOf = take(recipe.as_of, "as_of");
  const basis = take(recipe.basis, "basis");
  const netOf = take(recipe.net_of, "net_of");

  const terms: Record<string, Figure> = {};
  for (const [k, a] of Object.entries(recipe.terms ?? {})) {
    const f = take(a, `terms.${k}`);
    if (f) terms[k] = f;
  }

  const custody: Record<string, Figure<string>> = {};
  for (const [k, a] of Object.entries(recipe.custody ?? {})) {
    const f = take(a, `custody.${k}`);
    if (f) custody[k] = { value: String(f.value), caption: f.caption };
  }

  const rates = [];
  const rate = take(recipe.rate, "rate");
  if (rate && asOf && typeof rate.value === "number") {
    rates.push({
      as_of: String(asOf.value),
      rate: rate.value,
      caption: rate.caption ?? "",
    });
  }

  // ── excluded, the part anchors cannot reason about ───────────────────────
  //
  // A recipe cannot look at 20% and know it is a target. What it CAN do is
  // check whether the phrases a human already identified on this manager's
  // sheets are still present, and report them with the surrounding text so a
  // reviewer sees the same words the sheet prints.
  //
  // If the recipe carries no exclude list, the array comes back empty and the
  // validator warns. That is correct: nobody has yet looked at this manager's
  // sheet closely enough to say which of its numbers are not returns.
  const excluded: Payload["excluded"] = [];
  const hay = flat(text);
  for (const phrase of recipe.exclude ?? []) {
    const i = hay.toLowerCase().indexOf(phrase.toLowerCase());
    if (i < 0) continue;
    const around = hay.slice(i, i + phrase.length + 90);
    // The LAST percent in the span, not the first. A benchmark row reads
    // "Benchmark (182 day T-Bill + 5.0% points) 13.2%": the label itself
    // contains a number and the value trails it. Taking the first gave 5.
    const all = [...around.matchAll(/(-?\d+(?:\.\d+)?)\s*%/g)];
    const n = all.length ? all[all.length - 1] : null;
    excluded.push({
      value: n ? Number(n[1]) : phrase,
      caption: flat(around).slice(0, 140),
      reason: `matches "${phrase}", which is not a return on this manager's sheets`,
    });
  }

  if (!asOf) {
    return { payload: null, missed, hit };
  }

  return {
    hit,
    missed,
    payload: {
      as_of: String(asOf.value),
      basis: basis ? { value: String(basis.value), caption: basis.caption } : undefined,
      net_of: netOf ? { value: String(netOf.value), caption: netOf.caption } : undefined,
      terms: Object.keys(terms).length ? terms : undefined,
      rates: rates.length ? rates : undefined,
      custody: Object.keys(custody).length ? custody : undefined,
      excluded,
      // Not a probability. A blunt signal that this came from anchors, so a
      // reviewer knows no judgement was applied and reads the captions harder.
      confidence: 0.5,
      warnings: missed.length
        ? [`Anchors found nothing for: ${missed.join(", ")}. The layout may have changed.`]
        : [],
    },
  };
}
