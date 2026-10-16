import { supabaseAdmin } from "@/lib/supabase/server";
import { getFunds, type PublicFund } from "@/lib/funds.server";

/*
 * Data for the public rates pages: today's board for a category, a month's
 * averages, a year's averages, the median over time and this week's movers.
 *
 * Every page here answers a search people type ("money market fund rates
 * kenya today", "best mmf kenya october 2026", "best money market fund 2026"),
 * and every number on it comes from rate_history, which only ever holds
 * approved rates. Server-only, read-only, and soft on failure: an empty table
 * renders an honest page rather than a 500.
 */

export type Category = {
  slug: string;
  fundType: string;
  currency: string;
  /** "Money market funds" */
  title: string;
  /** "KES money market funds", in sentences */
  noun: string;
};

export const CATEGORIES: Category[] = [
  { slug: "money-market-funds", fundType: "mmf", currency: "KES", title: "Money market fund", noun: "KES money market funds" },
  { slug: "usd-money-market-funds", fundType: "mmf", currency: "USD", title: "USD money market fund", noun: "USD money market funds" },
  { slug: "fixed-income-funds", fundType: "fixed_income", currency: "KES", title: "Fixed income fund", noun: "KES fixed income funds" },
  { slug: "special-funds", fundType: "special", currency: "KES", title: "Special fund", noun: "KES special funds" },
];

export const categoryBySlug = (slug: string) => CATEGORIES.find((c) => c.slug === slug);

export const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

const DAY = 86_400_000;
const iso = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (day: string, n: number) => iso(new Date(Date.parse(day + "T00:00:00Z") + n * DAY));

/** Today in Nairobi. */
export function nairobiToday(): string {
  return iso(new Date(Date.now() + 3 * 3_600_000));
}

/** "Friday 16 October 2026". */
export function longDay(day: string): string {
  return new Date(day + "T12:00:00Z").toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

export function median(xs: number[]): number | null {
  const s = [...xs].sort((a, b) => a - b);
  if (!s.length) return null;
  const k = Math.floor(s.length / 2);
  return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2;
}

/** Funds in a category with a published rate, best first. */
export async function categoryFunds(cat: Category) {
  const bundle = await getFunds();
  const funds = bundle.funds.filter(
    (f) => f.fundType === cat.fundType && f.currency === cat.currency && f.grossRate != null,
  );
  return { ...bundle, funds };
}

/** Approved prints for [ids] between [from] and [to], per fund, date order. */
async function prints(ids: string[], from: string, to: string) {
  const out = new Map<string, [string, number][]>();
  if (!ids.length) return out;
  try {
    const db = supabaseAdmin();
    const page = 1000;
    for (let off = 0; ; off += page) {
      const { data, error } = await db
        .from("rate_history")
        .select("fund_id,as_of,rate")
        .in("fund_id", ids)
        .gte("as_of", from)
        .lte("as_of", to)
        .order("as_of", { ascending: true })
        .order("fund_id", { ascending: true })
        .range(off, off + page - 1);
      if (error) break;
      for (const r of data ?? []) {
        if (r.rate == null) continue;
        const list = out.get(r.fund_id) ?? [];
        list.push([r.as_of as string, Number(r.rate)]);
        out.set(r.fund_id, list);
      }
      if (!data || data.length < page) break;
    }
  } catch {
    // Fall through with whatever was read.
  }
  return out;
}

function rateAt(list: [string, number][] | undefined, day: string): number | null {
  if (!list) return null;
  let v: number | null = null;
  for (const [d, r] of list) {
    if (d > day) break;
    v = r;
  }
  return v;
}

/** Each fund's move over the last seven days, in points. */
export async function weekMoves(funds: PublicFund[]): Promise<Map<string, number>> {
  const today = nairobiToday();
  const p = await prints(funds.map((f) => f.id), addDays(today, -60), today);
  const out = new Map<string, number>();
  for (const f of funds) {
    const now = rateAt(p.get(f.id), today);
    const then = rateAt(p.get(f.id), addDays(today, -7));
    if (now != null && then != null) out.set(f.id, now - then);
  }
  return out;
}

/** The 91-day T-bill rate from config, the figure every fund is measured against. */
export async function billRate(): Promise<number | null> {
  try {
    const { data } = await supabaseAdmin()
      .from("app_config")
      .select("value")
      .eq("key", "benchmark.tbill_91")
      .maybeSingle();
    const v = data?.value as { rate?: number } | number | null | undefined;
    if (typeof v === "number") return v;
    return v && typeof v.rate === "number" ? v.rate : null;
  } catch {
    return null;
  }
}

export type Average = { fund: PublicFund; avg: number; prints: number };

/**
 * Each fund's average daily rate over [from, to], counting the rate in force
 * on every calendar day (a fund that prints weekly still counts every day).
 * Funds with no rate in force in the window are left out.
 */
export async function averages(funds: PublicFund[], from: string, to: string): Promise<Average[]> {
  const today = nairobiToday();
  const end = to > today ? today : to;
  if (end < from) return [];
  const p = await prints(funds.map((f) => f.id), addDays(from, -60), end);
  const out: Average[] = [];
  for (const f of funds) {
    const list = p.get(f.id);
    let sum = 0;
    let n = 0;
    let seen = 0;
    for (let d = from; d <= end; d = addDays(d, 1)) {
      const r = rateAt(list, d);
      if (r == null) continue;
      sum += r;
      n++;
    }
    for (const [d] of list ?? []) if (d >= from && d <= end) seen++;
    if (n > 0 && seen > 0) out.push({ fund: f, avg: sum / n, prints: seen });
  }
  return out.sort((a, b) => b.avg - a.avg);
}

/** First and last day of a month, as YYYY-MM-DD. */
export function monthRange(year: number, month: number): [string, string] {
  const first = `${year}-${String(month).padStart(2, "0")}-01`;
  const last = iso(new Date(Date.UTC(year, month, 0)));
  return [first, last];
}

/** The median of each month's fund averages, oldest first, for [count] months to now. */
export async function medianByMonth(funds: PublicFund[], count = 12) {
  const today = nairobiToday();
  const [y, m] = today.split("-").map(Number);
  const out: { year: number; month: number; median: number | null }[] = [];
  const from = monthRange(...shift(y, m, -(count - 1)))[0];
  const p = await prints(funds.map((f) => f.id), addDays(from, -60), today);
  for (let k = count - 1; k >= 0; k--) {
    const [yy, mm] = shift(y, m, -k);
    const [a, b] = monthRange(yy, mm);
    const end = b > today ? today : b;
    const avgs: number[] = [];
    for (const f of funds) {
      const list = p.get(f.id);
      let sum = 0;
      let n = 0;
      for (let d = a; d <= end; d = addDays(d, 1)) {
        const r = rateAt(list, d);
        if (r != null) {
          sum += r;
          n++;
        }
      }
      if (n) avgs.push(sum / n);
    }
    out.push({ year: yy, month: mm, median: median(avgs) });
  }
  return out;
}

/** [year, month] moved by [delta] months. */
export function shift(year: number, month: number, delta: number): [number, number] {
  const t = year * 12 + (month - 1) + delta;
  return [Math.floor(t / 12), (t % 12) + 1];
}

/** The first month Fructa has a rate for, so month pages before it 404. */
export async function firstMonth(): Promise<[number, number] | null> {
  try {
    const { data } = await supabaseAdmin()
      .from("rate_history")
      .select("as_of")
      .order("as_of", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (!data?.as_of) return null;
    const [y, m] = String(data.as_of).split("-").map(Number);
    return [y, m];
  } catch {
    return null;
  }
}

/** Whether a month page should exist: from the first data month to this month. */
export async function monthExists(year: number, month: number): Promise<boolean> {
  if (!Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) return false;
  const first = await firstMonth();
  if (!first) return false;
  const [ty, tm] = nairobiToday().split("-").map(Number);
  const t = year * 12 + month;
  return t >= first[0] * 12 + first[1] && t <= ty * 12 + tm;
}
