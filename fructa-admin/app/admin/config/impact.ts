// What a config value actually rewrites downstream.
//
// These keys are not settings, they are the constants the app computes with.
// Retyping benchmark.inflation silently moves every real-yield figure in the
// product. This file recomputes those figures against the live board so the
// operator sees the consequence before publishing, not after.
//
// Pure: takes the board snapshot the page loaded, plus the before/after models.

import type { Field, Model, RateModel, TableModel } from "./schema";
import { parseModel } from "./schema";

/** The live numbers the impact lines are computed against. */
export type Board = {
  topName: string | null;
  topRate: number | null;
  /** current_rate of every KES money market fund with a live yield */
  mmfRates: number[];
  /** published values, used as the "before" side of derived figures */
  wht: number;
  inflation: number;
};

export type ImpactRow = {
  label: string;
  sub: string;
  before: string;
  after: string;
  dir: "up" | "down" | "same";
};

const rateOf = (m: Model): number | null => {
  const n = Number((m as RateModel)?.rate);
  return Number.isFinite(n) ? n : null;
};

const dirOf = (a: number, b: number): ImpactRow["dir"] =>
  Math.abs(a - b) < 0.005 ? "same" : b > a ? "up" : "down";

const pct = (n: number) => `${n.toFixed(2)}%`;
const num = (n: number) => n.toFixed(2);

function row(label: string, sub: string, before: number, after: number, fmt: (n: number) => string): ImpactRow {
  return { label, sub, before: fmt(before), after: fmt(after), dir: dirOf(before, after) };
}

function countRow(label: string, sub: string, before: number, after: number): ImpactRow {
  return {
    label,
    sub,
    before: String(before),
    after: String(after),
    dir: before === after ? "same" : after > before ? "up" : "down",
  };
}

/** Sum of a table's numeric column. */
function sumCol(m: TableModel, col: string): number {
  return m.rows.reduce((s, r) => s + (Number(r[col]) || 0), 0);
}

export function computeImpact(
  key: string,
  field: Field,
  published: unknown,
  edited: Model,
  board: Board,
): ImpactRow[] {
  const top = board.topRate;
  const rates = board.mmfRates;
  const before0 = parseModel(field, published);

  // ── rate anchors ────────────────────────────────────────────────────────
  if (field.kind === "rate") {
    const a = rateOf(before0);
    const b = rateOf(edited);
    if (a == null || b == null) return [];

    if (key.startsWith("benchmark.tbill") || key === "benchmark.cbr") {
      const out: ImpactRow[] = [];
      if (top != null) {
        out.push(
          row(
            key === "benchmark.cbr" ? "Top MMF premium over policy" : "Spread over risk-free, top MMF",
            `${board.topName ?? "top fund"} at ${pct(top)} gross, minus this anchor`,
            top - a,
            top - b,
            num,
          ),
        );
      }
      if (rates.length) {
        out.push(
          countRow(
            key === "benchmark.cbr" ? "Funds yielding above policy" : "Funds beating the risk-free rate",
            `of ${rates.length} KES money market funds`,
            rates.filter((r) => r > a).length,
            rates.filter((r) => r > b).length,
          ),
        );
      }
      if (key !== "benchmark.cbr") {
        const tenor = key.split("_")[1];
        out.push(row(`Landing yield curve, ${tenor}d point`, "the published curve on fructa.africa", a, b, pct));
      } else {
        out.push(row("Landing curve reference line", "the dashed CBR line under the curve", a, b, pct));
      }
      return out;
    }

    if (key === "benchmark.inflation") {
      const out: ImpactRow[] = [];
      if (top != null) {
        const net = top * (1 - board.wht / 100);
        out.push(row("Real yield, top MMF", `${board.topName ?? "top fund"} net of tax, minus inflation`, net - a, net - b, num));
      }
      if (rates.length) {
        const realCount = (infl: number) =>
          rates.filter((r) => r * (1 - board.wht / 100) - infl > 0).length;
        out.push(
          countRow("Funds with a positive real return", `of ${rates.length} KES money market funds`, realCount(a), realCount(b)),
        );
      }
      return out;
    }

    if (key === "benchmark.wht_pct") {
      const out: ImpactRow[] = [];
      if (top != null) {
        out.push(row("Net yield, top MMF", `${board.topName ?? "top fund"} after withholding`, top * (1 - a / 100), top * (1 - b / 100), pct));
        out.push(
          row(
            "Real yield, top MMF",
            `net of tax, minus ${pct(board.inflation)} inflation`,
            top * (1 - a / 100) - board.inflation,
            top * (1 - b / 100) - board.inflation,
            num,
          ),
        );
      }
      if (rates.length) {
        const realCount = (w: number) => rates.filter((r) => r * (1 - w / 100) - board.inflation > 0).length;
        out.push(countRow("Funds with a positive real return", `of ${rates.length} KES money market funds`, realCount(a), realCount(b)));
      }
      return out;
    }

    // insurance ratios and any other rate key: no derived figure in the app yet
    return [];
  }

  // ── flags ───────────────────────────────────────────────────────────────
  if (field.kind === "flag") {
    const a = before0 === true;
    const b = edited === true;
    if (a === b) return [];
    return [
      {
        label: "Insure tab",
        sub: "the bottom-nav surface",
        before: a ? "visible" : "hidden",
        after: b ? "visible" : "hidden",
        dir: b ? "up" : "down",
      },
      {
        label: "Markets, insurance spotlight",
        sub: "the card on the Markets screen",
        before: a ? "visible" : "hidden",
        after: b ? "visible" : "hidden",
        dir: b ? "up" : "down",
      },
    ];
  }

  // ── tables ──────────────────────────────────────────────────────────────
  if (field.kind === "table") {
    const a = before0 as TableModel;
    const b = edited as TableModel;
    const out: ImpactRow[] = [];

    if (field.totalFromColumn) {
      const col = field.totalFromColumn;
      const ta = sumCol(a, col);
      const tb = sumCol(b, col);
      const bn = (n: number) => `${(n / 1e9).toFixed(1)}B`;
      out.push({ label: "Total AUM", sub: "computed from the rows, shown on the donut", before: bn(ta), after: bn(tb), dir: dirOf(ta, tb) });
    }

    const shareCol = field.columns.find((c) => c.suffix === "%");
    if (shareCol) {
      const sa = sumCol(a, shareCol.key);
      const sb = sumCol(b, shareCol.key);
      out.push({ label: "Shares total", sub: "should land on 100%", before: pct(sa), after: pct(sb), dir: dirOf(sa, sb) });
    }

    out.push(countRow("Slices on the donut", "one per row", a.rows.length, b.rows.length));
    return out;
  }

  // ── chips ───────────────────────────────────────────────────────────────
  if (field.kind === "stringList") {
    const a = (before0 as string[]).length;
    const b = (edited as string[]).length;
    if (a === b) return [];
    return [countRow("Chips under the search field", "shown when search is empty", a, b)];
  }

  return [];
}
