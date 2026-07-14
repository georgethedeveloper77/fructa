// Operational metadata the registry does not carry: how often a key is SUPPOSED
// to reprint, and which surfaces read it.
//
// Freshness is per key, because the cadences differ wildly. A 91-day T-bill
// auctions weekly, so a 27-day-old print is stale. The CBR is reset at MPC,
// roughly every two months, so 32 days is perfectly normal. Judging both against
// one threshold would either cry wolf on the CBR or stay silent on a dead T-bill.
//
// Colour rule for this whole page: COLOUR IS STATE, SHAPE IS IDENTITY.
// Hue is spent only on freshness (live, warn, bad) and on staged (gold). Groups
// get no hue at all, they are ordered and labelled instead. That is why there is
// no GROUP_TONE here any more: when seven groups each owned a hue, gold meant
// both "Benchmarks" and "staged", and warn meant both "Onboarding" and "due", so
// no colour on the page meant anything.

export type Freshness =
  | { kind: "ok"; days: number }
  | { kind: "due"; days: number }
  | { kind: "stale"; days: number }
  | { kind: "constant" }
  | { kind: "undated" };

/** Days after which a key's `as_of` is due, then stale. */
export const CADENCE: Record<string, { due: number; stale: number; note: string }> = {
  "benchmark.tbill_91": { due: 8, stale: 14, note: "CBK auctions weekly" },
  "benchmark.tbill_182": { due: 8, stale: 14, note: "CBK auctions weekly" },
  "benchmark.tbill_364": { due: 8, stale: 14, note: "CBK auctions weekly" },
  "benchmark.inflation": { due: 35, stale: 50, note: "KNBS publishes monthly" },
  "benchmark.cbr": { due: 70, stale: 100, note: "MPC meets about every two months" },
  // Combined ratios by class. These used to key on insure.industry_* and
  // insure.class_combined_ratios, which the registry retired, so every ratio
  // silently reported "undated" with no consumers. Repointed to the live keys.
  "insure.cr.motor_private": { due: 400, stale: 550, note: "IRA reports annually" },
  "insure.cr.motor_commercial": { due: 400, stale: 550, note: "IRA reports annually" },
  "insure.cr.medical": { due: 400, stale: 550, note: "IRA reports annually" },
  "insure.cr.marine": { due: 400, stale: 550, note: "IRA reports annually" },
  "market.aum_by_fund_type": { due: 100, stale: 140, note: "CMA reports quarterly" },
  "market.asset_classes": { due: 100, stale: 140, note: "CMA reports quarterly" },
};

/** Keys that are policy constants, not dated prints. Dating them would be a lie. */
export const CONSTANT_KEYS = new Set(["benchmark.wht_pct"]);

export function freshness(key: string, asOf: string | null | undefined): Freshness {
  if (CONSTANT_KEYS.has(key)) return { kind: "constant" };
  const cad = CADENCE[key];
  if (!cad || !asOf) return { kind: "undated" };
  const t = Date.parse(asOf);
  if (!Number.isFinite(t)) return { kind: "undated" };
  const days = Math.max(0, Math.floor((Date.now() - t) / 86_400_000));
  if (days >= cad.stale) return { kind: "stale", days };
  if (days >= cad.due) return { kind: "due", days };
  return { kind: "ok", days };
}

/** True when the operator owes this key a reprint. Drives the rail filter. */
export function needsReprint(f: Freshness): boolean {
  return f.kind === "due" || f.kind === "stale";
}

/* Freshness rendering. One ladder, used identically in the rail dot, the header
 * pill and the age meter, so a colour learned in one place reads in all three. */

export function freshDot(f: Freshness): string {
  switch (f.kind) {
    case "stale":
      return "bg-bad";
    case "due":
      return "bg-warn";
    case "ok":
      return "bg-live";
    default:
      // undated and constant carry no state, so they carry no hue: a hollow ring
      return "border border-line2";
  }
}

export function freshPill(f: Freshness): { cls: string; label: string } | null {
  switch (f.kind) {
    case "stale":
      return { cls: "border-bad/40 text-bad", label: `${f.days} days old, stale` };
    case "due":
      return { cls: "border-warn/40 text-warn", label: `${f.days} days old, due` };
    case "ok":
      return { cls: "border-line2 text-mute", label: `${f.days} days old` };
    case "constant":
      return { cls: "border-line text-faint", label: "policy constant" };
    default:
      return null;
  }
}

/** How far through its life this print is, 0 to 1. Feeds the age meter. */
export function agePosition(key: string, f: Freshness): number | null {
  const cad = CADENCE[key];
  if (!cad || (f.kind !== "ok" && f.kind !== "due" && f.kind !== "stale")) return null;
  return Math.min(1, f.days / cad.stale);
}

/** The cadence rule spelled out, so the pill is a judgement with its reasons. */
export function cadenceRule(key: string): string | null {
  const cad = CADENCE[key];
  if (!cad) return null;
  return `${cad.note}. Due after ${cad.due} days, stale at ${cad.stale}.`;
}

export type Consumer = { surface: "App" | "Landing"; where: string };

/** Where a key is actually read. The blast radius of a publish. */
export const CONSUMERS: Record<string, Consumer[]> = {
  "benchmark.tbill_91": [
    { surface: "App", where: "Markets, benchmark strip" },
    { surface: "App", where: "Fund detail, signals" },
    { surface: "Landing", where: "Yield curve" },
    { surface: "Landing", where: "Ticker" },
  ],
  "benchmark.tbill_182": [
    { surface: "App", where: "Markets, T-bill strip" },
    { surface: "Landing", where: "Yield curve" },
  ],
  "benchmark.tbill_364": [
    { surface: "App", where: "Markets, T-bill strip" },
    { surface: "Landing", where: "Yield curve" },
  ],
  "benchmark.cbr": [
    { surface: "App", where: "Markets, benchmark strip" },
    { surface: "Landing", where: "Yield curve reference line" },
  ],
  "benchmark.inflation": [
    { surface: "App", where: "Real yield, every fund" },
    { surface: "App", where: "Markets context card" },
    { surface: "Landing", where: "Net of tax chart, real bar" },
  ],
  "benchmark.wht_pct": [
    { surface: "App", where: "Net yield, every fund" },
    { surface: "App", where: "Compare, net column" },
    { surface: "Landing", where: "Net of tax chart" },
  ],
  "insurance.launched": [
    { surface: "App", where: "Insure tab" },
    { surface: "App", where: "Markets, insurance spotlight" },
  ],
  "insure.cr.motor_private": [{ surface: "App", where: "Insure, motor quote context" }],
  "insure.cr.motor_commercial": [{ surface: "App", where: "Insure, motor quote context" }],
  "insure.cr.medical": [{ surface: "App", where: "Insure, medical context" }],
  "insure.cr.marine": [{ surface: "App", where: "Insure, market context" }],
  "market.aum_by_fund_type": [
    { surface: "App", where: "Markets donut" },
    { surface: "Landing", where: "Market donut" },
  ],
  "market.asset_classes": [{ surface: "App", where: "Markets context card" }],
  "search.placeholder": [{ surface: "App", where: "Search field" }],
  "search.suggestions": [{ surface: "App", where: "Search, empty state chips" }],
};

/** A short label for the value kind, shown as a chip. */
export const KIND_LABEL: Record<string, string> = {
  rate: "rate",
  flag: "flag",
  text: "copy",
  stringList: "chips",
  table: "table",
  json: "json",
};
