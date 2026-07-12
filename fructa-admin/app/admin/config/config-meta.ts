// Operational metadata the registry does not carry: how often a key is SUPPOSED
// to reprint, and which surfaces read it.
//
// Freshness is per key, because the cadences differ wildly. A 91-day T-bill
// auctions weekly, so a 27-day-old print is stale. The CBR is reset at MPC,
// roughly every two months, so 32 days is perfectly normal. Judging both against
// one threshold would either cry wolf on the CBR or stay silent on a dead T-bill.

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
  "insure.industry_combined_ratio": { due: 400, stale: 550, note: "IRA reports annually" },
  "insure.industry_loss_ratio": { due: 400, stale: 550, note: "IRA reports annually" },
  "insure.class_combined_ratios": { due: 400, stale: 550, note: "IRA reports annually" },
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

export type Consumer = { surface: "App" | "Landing"; where: string };

/** Where a key is actually read. The blast radius of a publish. */
export const CONSUMERS: Record<string, Consumer[]> = {
  "benchmark.tbill_91": [
    { surface: "App", where: "Markets, benchmark strip" },
    { surface: "App", where: "Fund detail, signals" },
    { surface: "Landing", where: "yield curve" },
    { surface: "Landing", where: "ticker" },
  ],
  "benchmark.tbill_182": [
    { surface: "App", where: "Markets, T-bill strip" },
    { surface: "Landing", where: "yield curve" },
  ],
  "benchmark.tbill_364": [
    { surface: "App", where: "Markets, T-bill strip" },
    { surface: "Landing", where: "yield curve" },
  ],
  "benchmark.cbr": [
    { surface: "App", where: "Markets, benchmark strip" },
    { surface: "Landing", where: "yield curve reference line" },
  ],
  "benchmark.inflation": [
    { surface: "App", where: "real yield, every fund" },
    { surface: "App", where: "Markets context card" },
    { surface: "Landing", where: "net of tax chart, real bar" },
  ],
  "benchmark.wht_pct": [
    { surface: "App", where: "net yield, every fund" },
    { surface: "App", where: "Compare, net column" },
    { surface: "Landing", where: "net of tax chart" },
  ],
  "insurance.launched": [
    { surface: "App", where: "Insure tab" },
    { surface: "App", where: "Markets, insurance spotlight" },
  ],
  "market.aum_by_fund_type": [
    { surface: "App", where: "Markets donut" },
    { surface: "Landing", where: "market donut" },
  ],
  "market.asset_classes": [{ surface: "App", where: "Markets context card" }],
  "search.placeholder": [{ surface: "App", where: "Search field" }],
  "search.suggestions": [{ surface: "App", where: "Search, empty state chips" }],
  "insure.industry_combined_ratio": [{ surface: "App", where: "Insure, motor quote context" }],
  "insure.industry_loss_ratio": [{ surface: "App", where: "Insure, market context" }],
  "insure.class_combined_ratios": [{ surface: "App", where: "Insure, motor quote context" }],
};

/* ── Colour ────────────────────────────────────────────────────────────────
 * Colour carries meaning here, it is not decoration. Each group owns a hue, so
 * a key is identifiable by colour alone in the list, the detail header and the
 * editor accent. Each value kind owns a tone, so a rate reads differently from
 * a flag at a glance. Everything comes from the admin token set: no raw hex.
 */

export type Tone = {
  /** text colour class */
  text: string;
  /** tinted background */
  bg: string;
  /** tinted border */
  border: string;
  /** solid, for dots and rules */
  solid: string;
};

export const GROUP_TONE: Record<string, Tone> = {
  Benchmarks: { text: "text-gold", bg: "bg-gold/10", border: "border-gold/40", solid: "bg-gold" },
  "Feature flags": { text: "text-violet", bg: "bg-violet/10", border: "border-violet/40", solid: "bg-violet" },
  Insurance: { text: "text-blue", bg: "bg-blue/10", border: "border-blue/40", solid: "bg-blue" },
  "Market (CMA)": { text: "text-teal", bg: "bg-teal/10", border: "border-teal/40", solid: "bg-teal" },
  Search: { text: "text-live", bg: "bg-live/10", border: "border-live/40", solid: "bg-live" },
  Onboarding: { text: "text-warn", bg: "bg-warn/10", border: "border-warn/40", solid: "bg-warn" },
  Learn: { text: "text-warn", bg: "bg-warn/10", border: "border-warn/40", solid: "bg-warn" },
};

const NEUTRAL: Tone = { text: "text-mute", bg: "bg-panel2", border: "border-line2", solid: "bg-line2" };

export function groupTone(group: string): Tone {
  return GROUP_TONE[group] ?? NEUTRAL;
}

/** A short label for the value kind, shown as a chip. */
export const KIND_LABEL: Record<string, string> = {
  rate: "rate",
  flag: "flag",
  text: "copy",
  stringList: "chips",
  table: "table",
  json: "json",
};
