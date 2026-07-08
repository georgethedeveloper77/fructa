// Config registry — the human face of the app's machine contract.
//
// The snapshot keys (`benchmark.cbr`, `insurance.launched`, …) are the strings
// the Flutter side reads (see remote_config.dart) and snapshot.ts publishes.
// We do NOT rename them — that would break the app in lockstep. Instead this
// registry decides how each key is LABELLED and EDITED, so an operator sees
// "Central Bank Rate" with a number field, not `benchmark.cbr` with raw JSON.
//
// Keys with no entry degrade gracefully: we infer an editor from the value's
// shape (bool → toggle, string → text, string[] → chips, else → JSON), so
// adding a key never requires touching this file — it just gets a nicer editor
// when you describe it here.

export type FieldKind = "rate" | "flag" | "text" | "stringList" | "table" | "json";

export interface TableColumn {
  key: string; // property name on each row object
  label: string;
  type: "text" | "number";
  suffix?: string; // e.g. "%"
}

interface Base {
  label: string;
  help: string;
  group: string;
  /** Prefill used when creating this key from the "Add predefined key" list. */
  seed?: unknown;
}

export type Field =
  | (Base & { kind: "rate"; showMeta?: boolean }) // { rate, as_of?, source? }
  | (Base & { kind: "flag" }) // boolean
  | (Base & { kind: "text"; multiline?: boolean }) // JSON string
  | (Base & { kind: "stringList" }) // JSON string[]
  | (Base & {
      kind: "table";
      rowsKey: string; // property holding the row array
      columns: TableColumn[];
      addLabel: string;
      totalKey?: string; // if set, sum a column into this property
      totalFromColumn?: string;
    })
  | (Base & { kind: "json" }); // free-form, current behaviour

// ── The registry ──────────────────────────────────────────────────────────

export const CONFIG_SCHEMA: Record<string, Field> = {
  // Benchmarks — the market anchors, highest-churn operator keys.
  "benchmark.inflation": {
    kind: "rate",
    group: "Benchmarks",
    label: "Inflation (headline CPI)",
    help: "KNBS month-on-month headline inflation. Drives the real-yield line on the hero and the market context card.",
  },
  "benchmark.cbr": {
    kind: "rate",
    group: "Benchmarks",
    label: "Central Bank Rate (CBR)",
    help: "CBK policy rate. Reset at MPC meetings, roughly every two months.",
  },
  "benchmark.tbill_91": {
    kind: "rate",
    group: "Benchmarks",
    label: "91-day T-bill",
    help: "Latest CBK auction weighted-average rate. The risk-free anchor every fund is measured against.",
  },
  "benchmark.tbill_182": {
    kind: "rate",
    group: "Benchmarks",
    label: "182-day T-bill",
    help: "Latest CBK auction weighted-average rate. Middle of the yield curve.",
  },
  "benchmark.tbill_364": {
    kind: "rate",
    group: "Benchmarks",
    label: "364-day T-bill",
    help: "Latest CBK auction weighted-average rate. Long end of the yield curve.",
  },
  "benchmark.wht_pct": {
    kind: "rate",
    group: "Benchmarks",
    label: "Withholding tax",
    help: "WHT rate used to compute net-of-tax yield. 15% for residents on most funds.",
    showMeta: false, // no as-of / source — it's a policy constant, not a dated print
  },

  // Feature flags.
  "insurance.launched": {
    kind: "flag",
    group: "Feature flags",
    label: "Insurance live",
    help: "Shows the insurance spotlight on Markets and enables the Insure tab.",
  },

  // Search.
  "search.placeholder": {
    kind: "text",
    group: "Search",
    label: "Search placeholder",
    help: "Hint text inside the global search field when it's empty.",
  },
  "search.suggestions": {
    kind: "stringList",
    group: "Search",
    label: "Search suggestion chips",
    help: "Chips offered under the empty search field. Tapped, they run as a query.",
  },

  // Market (CMA) — authoritative quarterly figures. Editable grid, not a blob.
  "market.aum_by_fund_type": {
    kind: "table",
    group: "Market (CMA)",
    label: "Market by fund type",
    help: "Authoritative AUM split from the CMA CIS quarterly report. Powers the Markets donut — the real market, not the funds we happen to track.",
    rowsKey: "types",
    addLabel: "Add fund type",
    totalKey: "total_kes",
    totalFromColumn: "aum_kes",
    columns: [
      { key: "type", label: "Type", type: "text" },
      { key: "aum_kes", label: "AUM (KES)", type: "number" },
      { key: "share", label: "Share", type: "number", suffix: "%" },
    ],
    seed: {
      as_of: "2026-03-31",
      source: "CMA CIS Quarterly Report Q1 2026",
      types: [
        { type: "mmf", aum_kes: 442199966997, share: 51.9 },
        { type: "special", aum_kes: 203565448012, share: 23.9 },
        { type: "fixed_income", aum_kes: 198991286618, share: 23.4 },
        { type: "equity", aum_kes: 4751495471, share: 0.6 },
        { type: "balanced", aum_kes: 2200313187, share: 0.3 },
      ],
    },
  },
  "market.asset_classes": {
    kind: "table",
    group: "Market (CMA)",
    label: "Market by asset class",
    help: "CMA CIS Table 9 — where the whole market's money actually sits. Feeds the market context card.",
    rowsKey: "classes",
    addLabel: "Add asset class",
    columns: [
      { key: "class", label: "Class", type: "text" },
      { key: "share", label: "Share", type: "number", suffix: "%" },
    ],
    seed: {
      as_of: "2026-03-31",
      source: "CMA CIS Quarterly Report Q1 2026",
      classes: [
        { class: "gok", share: 44.0 },
        { class: "fixed_deposits", share: 23.5 },
        { class: "cash", share: 14.1 },
        { class: "unlisted", share: 8.8 },
        { class: "listed", share: 7.0 },
        { class: "offshore", share: 1.9 },
        { class: "other_cis", share: 0.4 },
        { class: "alternative", share: 0.3 },
      ],
    },
  },
};

// Groups render in this order; anything else falls after, alphabetically.
export const GROUP_ORDER = [
  "Benchmarks",
  "Feature flags",
  "Market (CMA)",
  "Search",
  "Onboarding",
  "Learn",
];

export function groupRank(g: string): number {
  const i = GROUP_ORDER.indexOf(g);
  return i === -1 ? GROUP_ORDER.length : i;
}

// ── Key helpers ─────────────────────────────────────────────────────────────

export const ns = (key: string) => (key.includes(".") ? key.split(".")[0] : "misc");

function titleCase(s: string): string {
  return s
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Human group for an unschema'd key: its namespace, title-cased. */
function inferredGroup(key: string): string {
  return titleCase(ns(key));
}

/** Human label for an unschema'd key: the part after the first dot. */
function inferredLabel(key: string): string {
  const tail = key.includes(".") ? key.slice(key.indexOf(".") + 1) : key;
  return titleCase(tail) || titleCase(key);
}

/** Resolve the editor+copy for a row: registry first, else inferred by shape. */
export function fieldFor(row: { key: string; value: unknown }): Field {
  const s = CONFIG_SCHEMA[row.key];
  if (s) return s;

  const group = inferredGroup(row.key);
  const label = inferredLabel(row.key);
  const v = row.value;

  if (typeof v === "boolean") return { kind: "flag", label, help: "", group };
  if (typeof v === "string")
    return { kind: "text", label, help: "", group, multiline: v.length > 60 };
  if (Array.isArray(v) && v.every((x) => typeof x === "string"))
    return { kind: "stringList", label, help: "", group };
  return { kind: "json", label, help: "", group };
}

// ── Value models (input-friendly, all strings) ──────────────────────────────

export type RateModel = { rate: string; as_of: string; source: string };
export type TableModel = { as_of: string; source: string; rows: Record<string, string>[] };
export type Model = RateModel | TableModel | boolean | string | string[];

function asRecord(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}

/** Build an editable model from the stored value. */
export function parseModel(field: Field, value: unknown): Model {
  switch (field.kind) {
    case "rate": {
      const o = asRecord(value);
      return {
        rate: o.rate != null ? String(o.rate) : "",
        as_of: typeof o.as_of === "string" ? o.as_of : "",
        source: typeof o.source === "string" ? o.source : "",
      };
    }
    case "flag":
      return value === true;
    case "text":
      return typeof value === "string" ? value : value == null ? "" : JSON.stringify(value);
    case "stringList":
      return Array.isArray(value) ? value.filter((x): x is string => typeof x === "string") : [];
    case "table": {
      const o = asRecord(value);
      const rows = Array.isArray(o[field.rowsKey]) ? (o[field.rowsKey] as unknown[]) : [];
      return {
        as_of: typeof o.as_of === "string" ? o.as_of : "",
        source: typeof o.source === "string" ? o.source : "",
        rows: rows.map((r) => {
          const rr = asRecord(r);
          const cells: Record<string, string> = {};
          for (const col of field.columns) cells[col.key] = rr[col.key] != null ? String(rr[col.key]) : "";
          return cells;
        }),
      };
    }
    case "json":
      return typeof value === "string" ? value : JSON.stringify(value, null, 2);
  }
}

export function defaultModel(field: Field): Model {
  if (field.seed !== undefined) return parseModel(field, field.seed);
  switch (field.kind) {
    case "rate":
      return { rate: "", as_of: "", source: "" };
    case "flag":
      return false;
    case "text":
      return "";
    case "stringList":
      return [];
    case "table":
      return { as_of: "", source: "", rows: [] };
    case "json":
      return "";
  }
}

/** Serialize a model into the string the `value` form field carries. */
export function serializeValue(field: Field, model: Model): string {
  switch (field.kind) {
    case "rate": {
      const m = model as RateModel;
      const out: Record<string, unknown> = { rate: Number(m.rate) };
      if (field.showMeta !== false) {
        if (m.as_of.trim()) out.as_of = m.as_of.trim();
        if (m.source.trim()) out.source = m.source.trim();
      }
      return JSON.stringify(out);
    }
    case "flag":
      return JSON.stringify(model as boolean);
    case "text":
      return JSON.stringify(model as string);
    case "stringList":
      return JSON.stringify((model as string[]).map((s) => s.trim()).filter(Boolean));
    case "table": {
      const m = model as TableModel;
      const out: Record<string, unknown> = {};
      if (m.as_of.trim()) out.as_of = m.as_of.trim();
      if (m.source.trim()) out.source = m.source.trim();
      out[field.rowsKey] = m.rows.map((r) => {
        const o: Record<string, unknown> = {};
        for (const col of field.columns) {
          o[col.key] = col.type === "number" ? Number(r[col.key]) : (r[col.key] ?? "").trim();
        }
        return o;
      });
      if (field.totalKey && field.totalFromColumn) {
        out[field.totalKey] = m.rows.reduce((s, r) => s + Number(r[field.totalFromColumn!] || 0), 0);
      }
      return JSON.stringify(out);
    }
    case "json":
      return model as string; // raw — actions.ts parses JSON-or-text
  }
}

export interface Validity {
  ok: boolean;
  msg?: string;
  warn?: string;
}

export function validate(field: Field, model: Model): Validity {
  switch (field.kind) {
    case "rate": {
      const m = model as RateModel;
      if (m.rate.trim() === "") return { ok: false, msg: "Enter a rate." };
      const n = Number(m.rate);
      if (!Number.isFinite(n)) return { ok: false, msg: "Rate must be a number." };
      if (n < 0 || n > 100) return { ok: false, msg: "Rate should be between 0 and 100." };
      return { ok: true };
    }
    case "text":
      return (model as string).trim() ? { ok: true } : { ok: false, msg: "Copy can't be empty." };
    case "flag":
    case "stringList":
      return { ok: true };
    case "table": {
      const m = model as TableModel;
      if (m.rows.length === 0) return { ok: false, msg: "Add at least one row." };
      for (const [i, r] of m.rows.entries()) {
        for (const col of field.columns) {
          const cell = (r[col.key] ?? "").trim();
          if (col.type === "text" && !cell) return { ok: false, msg: `Row ${i + 1}: ${col.label} is empty.` };
          if (col.type === "number" && !Number.isFinite(Number(cell)))
            return { ok: false, msg: `Row ${i + 1}: ${col.label} must be a number.` };
        }
      }
      const shareCol = field.columns.find((c) => c.suffix === "%");
      if (shareCol) {
        const sum = m.rows.reduce((s, r) => s + Number(r[shareCol.key] || 0), 0);
        if (Math.abs(sum - 100) > 0.5) return { ok: true, warn: `Shares sum to ${sum.toFixed(1)}%, not 100%.` };
      }
      return { ok: true };
    }
    case "json": {
      const raw = (model as string).trim();
      if (!raw) return { ok: false, msg: "Value is empty." };
      if (raw[0] === "{" || raw[0] === "[") {
        try {
          JSON.parse(raw);
        } catch {
          return { ok: false, msg: "That looks like JSON but doesn't parse." };
        }
      }
      return { ok: true };
    }
  }
}

/** The serialized form of the stored value, for dirty comparison. */
export function initialSerialized(field: Field, value: unknown): string {
  return serializeValue(field, parseModel(field, value));
}
