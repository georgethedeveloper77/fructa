// Market stories, built from approved rates only.
//
// rate_history holds only applied rates: a scraped jump beyond the review
// tolerance waits in rate_review and never lands here until approved. Reading
// rate_history alone is the data gate.
//
// A story is picked by how unusual it is, not just by its size: a move is
// measured against the fund's own normal weekly move, so 0.30 points is big
// news for a steady fund and nothing for a jumpy one. Market-wide stories
// (breadth, the median, a new leader, the bill) sit beside the fund stories,
// and the same fund does not lead the same story again for a few weeks unless
// the move is much bigger.
//
// Everything here is market data. Nothing about any user is read or written.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.85.0";

export type Period = "day" | "week" | "month" | "quarter" | "year";
export type Tone = "up" | "down" | "info" | "tbill" | "accent";

export interface StoryChart {
  kind: "line" | "step" | "band" | "rank" | "bars" | "none";
  /** [YYYY-MM-DD, rate] in date order. */
  points?: [string, number][];
  ref?: number | null;
  ref_key?: string | null;
  /** bars: every fund's rate, best first. band: [low, high]. */
  field?: number[];
  rank_from?: number;
  rank_to?: number;
  rank_of?: number;
}

export interface Story {
  key: string;
  type: string;
  tag_key: string;
  fund_id: string | null;
  title: string;
  big: string;
  unit: string;
  line: string;
  tone: Tone;
  chart: StoryChart;
  /** How unusual (move over the fund's normal weekly move) and the run of weeks in one direction. */
  stats: { value: number; ratio: number | null; trend_weeks: number | null };
  score: number;
}

export interface WrapRow {
  id: string;
  period: Period;
  period_start: string;
  period_end: string;
  stories: Story[];
  lead: string | null;
}

export interface Cfg {
  enabled: boolean;
  dailyRatio: number;
  dailyMinMove: number;
  dailyMax: number;
  weeklyMax: number;
  repeatWeeks: number;
  breadthMin: number;
  publishDow: number;
  publishHour: number;
  weeklyPush: boolean;
}

const DEFAULTS: Cfg = {
  enabled: true,
  dailyRatio: 3,
  dailyMinMove: 0.25,
  dailyMax: 3,
  weeklyMax: 8,
  repeatWeeks: 3,
  breadthMin: 8,
  publishDow: 5,
  publishHour: 18,
  weeklyPush: true,
};

/** The thresholds, from story.* keys in app_config, falling back to defaults. */
export async function loadCfg(db: SupabaseClient): Promise<Cfg> {
  const { data } = await db.from("app_config").select("key,value").like("key", "story.%");
  const v = new Map((data ?? []).map((r) => [r.key as string, r.value as unknown]));
  const num = (k: string, d: number) => {
    const x = Number(v.get(k));
    return Number.isFinite(x) ? x : d;
  };
  const bool = (k: string, d: boolean) => (v.has(k) ? v.get(k) === true || v.get(k) === "true" : d);
  return {
    enabled: bool("story.enabled", DEFAULTS.enabled),
    dailyRatio: num("story.daily_ratio", DEFAULTS.dailyRatio),
    dailyMinMove: num("story.daily_min_move", DEFAULTS.dailyMinMove),
    dailyMax: num("story.daily_max", DEFAULTS.dailyMax),
    weeklyMax: num("story.weekly_max", DEFAULTS.weeklyMax),
    repeatWeeks: num("story.repeat_weeks", DEFAULTS.repeatWeeks),
    breadthMin: num("story.breadth_min", DEFAULTS.breadthMin),
    publishDow: num("story.weekly_publish_dow", DEFAULTS.publishDow),
    publishHour: num("story.weekly_publish_hour", DEFAULTS.publishHour),
    weeklyPush: bool("story.weekly_push", DEFAULTS.weeklyPush),
  };
}

// ── Dates (all as Nairobi calendar days, YYYY-MM-DD) ───────────────────────

const DAY = 86_400_000;

export function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function addDays(day: string, n: number): string {
  return iso(new Date(Date.parse(day + "T00:00:00Z") + n * DAY));
}

/** Today's date and hour in Nairobi (UTC+3, no daylight saving). */
export function nairobiNow(now = new Date()): { day: string; hour: number; dow: number } {
  const t = new Date(now.getTime() + 3 * 3_600_000);
  return { day: iso(t), hour: t.getUTCHours(), dow: t.getUTCDay() };
}

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
const MON = MONTHS.map((m) => m.slice(0, 3));

export function dayLabel(day: string): string {
  const [, m, d] = day.split("-").map(Number);
  return `${d} ${MON[m - 1]}`;
}

// ── Data ───────────────────────────────────────────────────────────────────

export interface FundRow {
  id: string;
  name: string;
  manager: string | null;
  fund_type: string | null;
  currency: string | null;
  retail: boolean | null;
  category: string | null;
  current_rate: number | null;
}

export interface Market {
  funds: FundRow[];
  /** Prints per fund, date order. */
  prints: Map<string, [string, number][]>;
  tbill: number | null;
}

/** Retail funds and their approved prints between [from] and [to]. */
export async function loadMarket(db: SupabaseClient, from: string, to: string): Promise<Market> {
  const { data: fundRows } = await db
    .from("funds")
    .select("id,name,manager,fund_type,currency,retail,category,current_rate")
    .eq("kind", "fund")
    .neq("status", "hidden");
  const funds = (fundRows ?? []) as FundRow[];
  const ids = new Set(funds.map((f) => f.id));

  const prints = new Map<string, [string, number][]>();
  const page = 1000;
  for (let off = 0; ; off += page) {
    const { data, error } = await db
      .from("rate_history")
      .select("fund_id,as_of,rate")
      .gte("as_of", from)
      .lte("as_of", to)
      .order("as_of", { ascending: true })
      .order("fund_id", { ascending: true })
      .range(off, off + page - 1);
    if (error) throw new Error(`rate_history: ${error.message}`);
    for (const r of data ?? []) {
      if (!ids.has(r.fund_id)) continue;
      const list = prints.get(r.fund_id) ?? [];
      list.push([r.as_of as string, Number(r.rate)]);
      prints.set(r.fund_id, list);
    }
    if (!data || data.length < page) break;
  }

  const { data: cfg } = await db.from("app_config").select("value").eq("key", "benchmark.tbill_91").maybeSingle();
  const tb = cfg?.value as { rate?: number } | number | null | undefined;
  const tbill = typeof tb === "number" ? tb : (tb && typeof tb.rate === "number" ? tb.rate : null);

  return { funds, prints, tbill };
}

/** The rate in force on [day]: the last print on or before it. */
function rateAt(m: Market, id: string, day: string): number | null {
  const p = m.prints.get(id);
  if (!p) return null;
  let out: number | null = null;
  for (const [d, r] of p) {
    if (d > day) break;
    out = r;
  }
  return out;
}

/** Prints strictly after [from] and on or before [to]. */
function printsIn(m: Market, id: string, from: string, to: string): [string, number][] {
  return (m.prints.get(id) ?? []).filter(([d]) => d > from && d <= to);
}

/** One value per day from [from] to [to], each carrying the last print. */
function daily(m: Market, id: string, from: string, to: string, step = 1): [string, number][] {
  const out: [string, number][] = [];
  for (let d = from; d <= to; d = addDays(d, step)) {
    const r = rateAt(m, id, d);
    if (r != null) out.push([d, r]);
  }
  const last = rateAt(m, id, to);
  if (last != null && (out.length === 0 || out[out.length - 1][0] !== to)) out.push([to, last]);
  return out;
}

/** The fund's normal weekly move: median absolute week-on-week change over 12 weeks before [to]. */
function normalWeek(m: Market, id: string, to: string): number {
  const moves: number[] = [];
  for (let k = 0; k < 12; k++) {
    const b = rateAt(m, id, addDays(to, -7 * k));
    const a = rateAt(m, id, addDays(to, -7 * (k + 1)));
    if (a != null && b != null) moves.push(Math.abs(b - a));
  }
  moves.sort((x, y) => x - y);
  const med = moves.length ? moves[Math.floor(moves.length / 2)] : 0;
  return Math.max(med, 0.05);
}

/** Consecutive recent weeks (ending at [to]) moving the same way as the last one. */
function trendWeeks(m: Market, id: string, to: string): number {
  let run = 0;
  let dir = 0;
  for (let k = 0; k < 12; k++) {
    const b = rateAt(m, id, addDays(to, -7 * k));
    const a = rateAt(m, id, addDays(to, -7 * (k + 1)));
    if (a == null || b == null) break;
    const s = Math.sign(Math.round((b - a) * 100));
    if (s === 0) break;
    if (dir === 0) dir = s;
    if (s !== dir) break;
    run++;
  }
  return run;
}

const isKesMmf = (f: FundRow) => f.retail === true && f.fund_type === "mmf" && f.currency === "KES";
const isUsdMmf = (f: FundRow) => f.retail === true && f.fund_type === "mmf" && f.currency === "USD";
const isBill91 = (f: FundRow) => f.category === "tbill" && /91/.test(`${f.id} ${f.name}`);

const pct = (v: number) => `${v.toFixed(2)}%`;
const pts = (v: number) => `${v > 0 ? "+" : v < 0 ? "-" : ""}${Math.abs(v).toFixed(2)}`;
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  if (!s.length) return null;
  const k = Math.floor(s.length / 2);
  return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2;
};

// ── Building ───────────────────────────────────────────────────────────────

/** A day's stories: only what moved well beyond its normal week. Empty on a quiet day. */
export function buildDay(m: Market, day: string, cfg: Cfg): Story[] {
  const field = m.funds.filter(isKesMmf);
  const out: Story[] = [];
  let down = 0;
  let up = 0;

  for (const f of field) {
    const today = printsIn(m, f.id, addDays(day, -1), day);
    if (!today.length) continue;
    const before = rateAt(m, f.id, addDays(day, -1));
    if (before == null) continue;
    const now = today[today.length - 1][1];
    const move = now - before;
    if (Math.abs(move) >= 0.05) move < 0 ? down++ : up++;
    if (Math.abs(move) < cfg.dailyMinMove) continue;
    const ratio = Math.abs(move) / normalWeek(m, f.id, addDays(day, -1));
    if (ratio < cfg.dailyRatio) continue;
    out.push({
      key: `day-move-${f.id}`,
      type: move > 0 ? "day_rise" : "day_cut",
      tag_key: move > 0 ? "wrap.tag.raised" : "wrap.tag.cut",
      fund_id: f.id,
      title: f.name,
      big: pts(move),
      unit: `pts today · now ${pct(now)} gross`,
      line: `${ratio.toFixed(1)}x its normal weekly move.`,
      tone: move > 0 ? "up" : "down",
      chart: { kind: "step", points: daily(m, f.id, addDays(day, -30), day) },
      stats: { value: move, ratio, trend_weeks: trendWeeks(m, f.id, day) },
      score: ratio,
    });
  }

  if (down >= cfg.breadthMin || up >= cfg.breadthMin) {
    const cut = down >= up;
    out.push({
      key: `day-breadth-${day}`,
      type: "breadth",
      tag_key: "wrap.tag.breadth",
      fund_id: null,
      title: cut ? "Money market funds cut today" : "Money market funds raised today",
      big: `${cut ? down : up} of ${field.length}`,
      unit: cut ? "KES funds cut their rate" : "KES funds raised their rate",
      line: "A move across the market, not one fund.",
      tone: cut ? "down" : "up",
      chart: { kind: "none" },
      stats: { value: cut ? down : up, ratio: null, trend_weeks: null },
      score: 10,
    });
  }

  for (const b of m.funds.filter(isBill91)) {
    const today = printsIn(m, b.id, addDays(day, -1), day);
    if (!today.length) continue;
    const before = rateAt(m, b.id, addDays(day, -1));
    const now = today[today.length - 1][1];
    const move = before == null ? 0 : now - before;
    out.push({
      key: `day-auction-${day}`,
      type: "auction",
      tag_key: "wrap.tag.auction",
      fund_id: b.id,
      title: "91-day Treasury bill",
      big: pct(now),
      unit: before == null ? "cleared at auction" : `${pts(move)} from the last auction`,
      line: "The rate every money market fund is measured against.",
      tone: "tbill",
      chart: { kind: "step", points: daily(m, b.id, addDays(day, -84), day, 7) },
      stats: { value: move, ratio: null, trend_weeks: null },
      score: 8,
    });
  }

  return out.sort((a, b) => b.score - a.score).slice(0, cfg.dailyMax);
}

/**
 * A period's stories (week and longer): the biggest climb and cut, the
 * steadiest fund, the biggest rank climb, how many beat the bill, and
 * market-wide moves. [recent] are earlier live weeks' stories, for the
 * no-repeat rule.
 */
export function buildRange(
  m: Market,
  from: string,
  to: string,
  cfg: Cfg,
  recent: Story[] = [],
): Story[] {
  const field = m.funds.filter(isKesMmf);
  const spanDays = Math.max(1, Math.round((Date.parse(to) - Date.parse(from)) / DAY));
  const step = spanDays > 120 ? 7 : 1;
  const weeks = spanDays / 7;
  const out: Story[] = [];

  type Mv = { f: FundRow; a: number; b: number; move: number; moved: boolean };
  const moves: Mv[] = [];
  for (const f of field) {
    const a = rateAt(m, f.id, from);
    const b = rateAt(m, f.id, to);
    if (a == null || b == null) continue;
    moves.push({ f, a, b, move: b - a, moved: printsIn(m, f.id, from, to).length > 0 });
  }
  if (!moves.length) return [];

  const avgTo = moves.reduce((s, x) => s + x.b, 0) / moves.length;
  const repeat = (type: string, id: string, value: number) =>
    recent.some((s) => s.type === type && s.fund_id === id && Math.abs(value) < 2 * Math.abs(s.stats.value));

  const unusual = (x: Mv) => Math.abs(x.move) / (normalWeek(m, x.f.id, to) * Math.max(1, Math.sqrt(weeks)));

  // Biggest climb and biggest cut.
  const climbers = moves.filter((x) => x.moved && x.move >= 0.05 && !repeat("improved", x.f.id, x.move))
    .sort((x, y) => y.move - x.move);
  const cutters = moves.filter((x) => x.moved && x.move <= -0.05 && !repeat("drop", x.f.id, x.move))
    .sort((x, y) => x.move - y.move);
  for (const [x, type] of [[climbers[0], "improved"], [cutters[0], "drop"]] as const) {
    if (!x) continue;
    const up = type === "improved";
    const ratio = unusual(x);
    out.push({
      key: `${type}-${x.f.id}`,
      type,
      tag_key: up ? "wrap.tag.improved" : "wrap.tag.drop",
      fund_id: x.f.id,
      title: x.f.name,
      big: pts(x.move),
      unit: `pts · now ${pct(x.b)} gross`,
      line: up
        ? `The biggest climb among ${moves.length} KES money market funds.`
        : `The biggest cut among ${moves.length} KES money market funds.`,
      tone: up ? "up" : "down",
      chart: {
        kind: up ? "line" : "step",
        points: daily(m, x.f.id, from, to, step),
        ref: Number(avgTo.toFixed(2)),
        ref_key: "wrap.axis.avg",
      },
      stats: { value: x.move, ratio, trend_weeks: trendWeeks(m, x.f.id, to) },
      score: 6 + ratio,
    });
  }

  // Steadiest fund in the better-paying half.
  const top = [...moves].sort((x, y) => y.b - x.b).slice(0, Math.ceil(moves.length / 2));
  let stable: { x: Mv; spread: number } | null = null;
  for (const x of top) {
    const p = printsIn(m, x.f.id, from, to);
    if (p.length < 2) continue;
    const rs = p.map(([, r]) => r);
    const spread = Math.max(...rs) - Math.min(...rs);
    if (!stable || spread < stable.spread) stable = { x, spread };
  }
  if (stable && !repeat("stable", stable.x.f.id, 0.01)) {
    const lo = Math.min(...moves.map((x) => x.b));
    const hi = Math.max(...moves.map((x) => x.b));
    out.push({
      key: `stable-${stable.x.f.id}`,
      type: "stable",
      tag_key: "wrap.tag.stable",
      fund_id: stable.x.f.id,
      title: stable.x.f.name,
      big: pct(stable.x.b),
      unit: stable.spread < 0.005 ? "unchanged all period" : `moved only ${stable.spread.toFixed(2)} pts`,
      line: "The steadiest rate in the better-paying half of the market.",
      tone: "info",
      chart: { kind: "band", points: daily(m, stable.x.f.id, from, to, step), field: [lo, hi] },
      stats: { value: stable.spread, ratio: null, trend_weeks: null },
      score: 4,
    });
  }

  // Biggest climb up the league table.
  const rankOf = (key: "a" | "b") => {
    const sorted = [...moves].sort((x, y) => y[key] - x[key]);
    return new Map(sorted.map((x, i) => [x.f.id, i + 1]));
  };
  const ra = rankOf("a");
  const rb = rankOf("b");
  let best: { x: Mv; places: number } | null = null;
  for (const x of moves) {
    const places = (ra.get(x.f.id) ?? 0) - (rb.get(x.f.id) ?? 0);
    if (places >= 3 && (!best || places > best.places)) best = { x, places };
  }
  if (best && !repeat("moving_up", best.x.f.id, best.places)) {
    out.push({
      key: `moving_up-${best.x.f.id}`,
      type: "moving_up",
      tag_key: "wrap.tag.movingUp",
      fund_id: best.x.f.id,
      title: best.x.f.name,
      big: `+${best.places}`,
      unit: `places · now #${rb.get(best.x.f.id)} of ${moves.length}`,
      line: `Up ${best.places} places among KES money market funds.`,
      tone: "up",
      chart: {
        kind: "rank",
        rank_from: ra.get(best.x.f.id),
        rank_to: rb.get(best.x.f.id),
        rank_of: moves.length,
      },
      stats: { value: best.places, ratio: null, trend_weeks: null },
      score: 3 + best.places / 2,
    });
  }

  // How many beat the 91-day bill.
  if (m.tbill != null) {
    const tb = m.tbill;
    const above = moves.filter((x) => x.b > tb).sort((x, y) => y.b - x.b);
    out.push({
      key: `tbill-${to}`,
      type: "tbill",
      tag_key: "wrap.tag.tbill",
      fund_id: null,
      title: "KES money market funds against the 91-day bill",
      big: `${above.length} of ${moves.length}`,
      unit: `pay more than the bill at ${pct(tb)}`,
      line: above.length
        ? `The best, ${above[0].f.name}, pays ${pts(above[0].b - tb)} pts more.`
        : "None pays more than the bill right now.",
      tone: "tbill",
      chart: { kind: "bars", field: [...moves].map((x) => x.b).sort((a, b) => b - a), ref: tb, ref_key: "wrap.axis.tbill" },
      stats: { value: above.length, ratio: null, trend_weeks: null },
      score: 3,
    });
  }

  // Market-wide: breadth and the median.
  const downs = moves.filter((x) => x.move <= -0.05).length;
  const ups = moves.filter((x) => x.move >= 0.05).length;
  if (Math.max(downs, ups) >= cfg.breadthMin) {
    const cut = downs >= ups;
    out.push({
      key: `breadth-${to}`,
      type: "breadth",
      tag_key: "wrap.tag.breadth",
      fund_id: null,
      title: cut ? "A market-wide cut" : "A market-wide rise",
      big: `${cut ? downs : ups} of ${moves.length}`,
      unit: cut ? "funds cut their rate" : "funds raised their rate",
      line: "A move across the market, not one fund.",
      tone: cut ? "down" : "up",
      chart: { kind: "none" },
      stats: { value: cut ? downs : ups, ratio: null, trend_weeks: null },
      score: 5 + Math.max(downs, ups) / moves.length * 5,
    });
  }
  const medA = median(moves.map((x) => x.a));
  const medB = median(moves.map((x) => x.b));
  if (medA != null && medB != null && (Math.abs(medB - medA) >= 0.05 || weeks >= 4)) {
    const mv = medB - medA;
    out.push({
      key: `median-${to}`,
      type: "median",
      tag_key: "wrap.tag.median",
      fund_id: null,
      title: "The middle of the market",
      big: pct(medB),
      unit: `median KES money market rate · ${pts(mv)} pts`,
      line: mv < 0 ? "The typical fund pays less than it did." : mv > 0 ? "The typical fund pays more than it did." : "The typical fund pays what it did.",
      tone: mv < 0 ? "down" : mv > 0 ? "up" : "info",
      chart: { kind: "none" },
      stats: { value: mv, ratio: null, trend_weeks: null },
      score: 2 + Math.abs(mv) * 10,
    });
  }

  // A new leader.
  const leadA = [...moves].sort((x, y) => y.a - x.a)[0];
  const leadB = [...moves].sort((x, y) => y.b - x.b)[0];
  if (leadA && leadB && leadA.f.id !== leadB.f.id) {
    out.push({
      key: `leader-${leadB.f.id}`,
      type: "leader",
      tag_key: "wrap.tag.leader",
      fund_id: leadB.f.id,
      title: leadB.f.name,
      big: pct(leadB.b),
      unit: `now pays the most · was ${leadA.f.name}`,
      line: "A new fund at the top of the KES money market table.",
      tone: "accent",
      chart: { kind: "line", points: daily(m, leadB.f.id, from, to, step), ref: Number(avgTo.toFixed(2)), ref_key: "wrap.axis.avg" },
      stats: { value: leadB.b, ratio: null, trend_weeks: null },
      score: 7,
    });
  }

  // Longer periods: how far apart best and worst are.
  if (weeks >= 4) {
    const s = [...moves].sort((x, y) => y.b - x.b);
    const gap = s[0].b - s[s.length - 1].b;
    out.push({
      key: `spread-${to}`,
      type: "spread",
      tag_key: "wrap.tag.spread",
      fund_id: null,
      title: "Best to worst",
      big: gap.toFixed(2),
      unit: "points between the best and worst KES fund",
      line: `${s[0].f.name} pays the most, at ${pct(s[0].b)}.`,
      tone: "info",
      chart: { kind: "bars", field: s.map((x) => x.b), ref: m.tbill, ref_key: "wrap.axis.tbill" },
      stats: { value: gap, ratio: null, trend_weeks: null },
      score: 2.5,
    });
  }

  // Dollar funds get the steadiest USD fund when there are enough of them.
  const usd = m.funds.filter(isUsdMmf);
  if (usd.length >= 3 && weeks >= 4) {
    const u = usd
      .map((f) => ({ f, b: rateAt(m, f.id, to) }))
      .filter((x): x is { f: FundRow; b: number } => x.b != null)
      .sort((x, y) => y.b - x.b)[0];
    if (u) {
      out.push({
        key: `usd-top-${u.f.id}`,
        type: "usd_top",
        tag_key: "wrap.tag.top",
        fund_id: u.f.id,
        title: u.f.name,
        big: pct(u.b),
        unit: "the best USD money market rate",
        line: "For money you hold, or spend, in dollars.",
        tone: "info",
        chart: { kind: "line", points: daily(m, u.f.id, from, to, step) },
        stats: { value: u.b, ratio: null, trend_weeks: null },
        score: 2,
      });
    }
  }

  // The climb and the cut always lead; the rest by score.
  const core = out.filter((s) => s.type === "improved" || s.type === "drop");
  const rest = out.filter((s) => !core.includes(s)).sort((a, b) => b.score - a.score);
  return [...core, ...rest].slice(0, cfg.weeklyMax);
}

// ── Periods ────────────────────────────────────────────────────────────────

export function weekRow(end: string): Omit<WrapRow, "stories" | "lead"> {
  return { id: `week-${end}`, period: "week", period_start: addDays(end, -7), period_end: end };
}

export function dayRow(day: string): Omit<WrapRow, "stories" | "lead"> {
  return { id: `day-${day}`, period: "day", period_start: addDays(day, -1), period_end: day };
}

/** The month, quarter or year that ended the day before [today], if one did. */
export function closedPeriods(today: string): Omit<WrapRow, "stories" | "lead">[] {
  const [y, mo, d] = today.split("-").map(Number);
  if (d !== 1) return [];
  const out: Omit<WrapRow, "stories" | "lead">[] = [];
  const end = addDays(today, -1);
  const py = mo === 1 ? y - 1 : y;
  const pm = mo === 1 ? 12 : mo - 1;
  const mm = String(pm).padStart(2, "0");
  out.push({ id: `month-${py}-${mm}`, period: "month", period_start: addDays(`${py}-${mm}-01`, -1), period_end: end });
  if ([1, 4, 7, 10].includes(mo)) {
    const q = Math.ceil(pm / 3);
    const qStart = `${py}-${String((q - 1) * 3 + 1).padStart(2, "0")}-01`;
    out.push({ id: `quarter-${py}-q${q}`, period: "quarter", period_start: addDays(qStart, -1), period_end: end });
  }
  if (mo === 1) {
    out.push({ id: `year-${py}`, period: "year", period_start: `${py - 1}-12-31`, period_end: end });
  }
  return out;
}

/** The Friday (or configured day) that closes the week holding [today]. */
export function weekEnd(today: string, dow: number): string {
  const cur = new Date(today + "T00:00:00Z").getUTCDay();
  return addDays(today, (dow - cur + 7) % 7);
}

export function leadOf(stories: Story[]): string | null {
  const s = stories[0];
  if (!s) return null;
  return s.fund_id ? `${s.title} ${s.big}` : `${s.title}: ${s.big}`;
}

export const periodLabel = (row: { period: Period; period_start: string; period_end: string; id: string }): string => {
  const [y, m] = row.period_end.split("-").map(Number);
  switch (row.period) {
    case "day":
      return dayLabel(row.period_end);
    case "week":
      return `${dayLabel(row.period_start)} to ${dayLabel(row.period_end)}`;
    case "month":
      return `${MONTHS[m - 1]} ${y}`;
    case "quarter":
      return row.id.replace(/^quarter-(\d{4})-q(\d)$/, "Q$2 $1");
    case "year":
      return String(y);
  }
};
