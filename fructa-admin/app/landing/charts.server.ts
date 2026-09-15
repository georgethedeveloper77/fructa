import { supabaseAdmin } from '@/lib/supabase/server';
import {
  FALLBACK_CHARTS,
  type LandingCharts,
  type MarketSlice,
  type RateTab,
  type Series,
  CBR,
  INFLATION,
} from './content';

/*
 * Builds every chart on the landing from the same tables the app publishes from.
 *
 * COLUMNS THIS FILE ASSUMES (confirm against your schema):
 *   funds        id, name, fund_type, currency, basis, current_rate
 *   rate_history fund_id, rate, as_of
 *   app_config   key, value
 *
 * fund_type is the authoritative classifier (category is legacy/nullable), and
 * only basis = 'yield' funds carry a rate, so priced/NAV funds are excluded from
 * every yield chart rather than being shown as a fabricated percentage.
 *
 * Fails safe: any throw returns FALLBACK_CHARTS with live:false, which renders
 * the page without the terminal rather than crashing it.
 */

const HISTORY_DAYS = 260;   // enough for 8 monthly marks plus slack
const MONTH_MARKS = 8;

type FundRow = {
  id: string;
  name: string;
  fund_type: string | null;
  currency: string | null;
  basis: string | null;
  current_rate: number | null;
};
type HistRow = { fund_id: string; rate: number | null; as_of: string };

const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthKey = (iso: string) => iso.slice(0, 7);
const monthLabel = (key: string) => MONTH[Number(key.slice(5, 7)) - 1] ?? key;

/** Last observed rate per fund per month, oldest first. */
function monthlySeries(hist: HistRow[], keys: string[]): Map<string, (number | null)[]> {
  const byFund = new Map<string, Map<string, number>>();
  for (const h of hist) {
    if (h.rate == null) continue;
    const k = monthKey(h.as_of);
    let m = byFund.get(h.fund_id);
    if (!m) byFund.set(h.fund_id, (m = new Map()));
    m.set(k, h.rate); // rows arrive ascending, so the last write is the month's close
  }
  const out = new Map<string, (number | null)[]>();
  for (const [fund, m] of byFund) {
    let carry: number | null = null;
    out.set(
      fund,
      keys.map((k) => {
        const v = m.get(k);
        if (v != null) carry = v;
        return carry; // carry forward, a fund that did not move still has a rate
      }),
    );
  }
  return out;
}

/** Top N yield funds of a type/currency, leader first. */
function pickTab(
  key: string,
  label: string,
  funds: FundRow[],
  series: Map<string, (number | null)[]>,
  match: (f: FundRow) => boolean,
  n: number,
  benchmarks: [string, string][],
): RateTab | null {
  const ranked = funds
    .filter((f) => f.basis === 'yield' && f.current_rate != null && match(f))
    .sort((a, b) => (b.current_rate ?? 0) - (a.current_rate ?? 0))
    .slice(0, n);

  const out: Series[] = [];
  ranked.forEach((f, i) => {
    const vals = series.get(f.id);
    if (!vals || vals.some((v) => v == null)) return; // no gaps on the landing
    out.push({ name: f.name, values: vals as number[], lead: i === 0 });
  });
  if (out.length < 2) return null;
  return { key, label, unit: '%', series: out, benchmarks };
}

const BILLION = 1_000_000_000;

/*
 * The industry split, in KES billions, from market.aum_by_fund_type.
 *
 * This is the same row the app's donut reads, and it is the authoritative one:
 * exact shillings straight off CMA Table 10, with as_of and source attached.
 * Shape (see lib/data/models/remote_config.dart):
 *   {"as_of":…,"source":…,"total_kes":…,
 *    "types":[{"type":"mmf","aum_kes":459874570485,"share":48.5}, …]}
 *
 * Shillings are divided down to billions here because that is the unit the
 * donut prints, in its centre total and in its tooltip alike.
 */
function slicesFromFundType(v: unknown): MarketSlice[] | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const types = (v as { types?: unknown }).types;
  if (!Array.isArray(types)) return null;

  const out: MarketSlice[] = [];
  for (const e of types) {
    if (!e || typeof e !== 'object') continue;
    const name = (e as { type?: unknown }).type;
    const aum = Number((e as { aum_kes?: unknown }).aum_kes);
    if (typeof name !== 'string' || !Number.isFinite(aum) || aum <= 0) continue;
    out.push({ name, value: aum / BILLION });
  }
  if (!out.length) return null;
  return out.sort((a, b) => b.value - a.value);
}

/*
 * Legacy fallback: market.aum_by_class, a flat map already expressed in KES
 * billions. Retained only so a failed read of the authoritative row does not
 * blank the chart. This row duplicates the fund-type split and has drifted from
 * it before, so it should be retired once this file is deployed.
 */
function slicesFromLegacy(v: unknown): MarketSlice[] | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const out = Object.entries(v as Record<string, unknown>)
    .map(([name, x]) => ({ name, value: Number(x) }))
    .filter((s) => Number.isFinite(s.value) && s.value > 0)
    .sort((a, b) => b.value - a.value);
  return out.length ? out : null;
}

export async function getLandingCharts(): Promise<LandingCharts> {
  try {
    const db = supabaseAdmin();

    const since = new Date();
    since.setDate(since.getDate() - HISTORY_DAYS);

    const [fundsRes, histRes, cfgRes] = await Promise.all([
      db.from('funds').select('id,name,fund_type,currency,basis,current_rate'),
      db
        .from('rate_history')
        .select('fund_id,rate,as_of')
        .gte('as_of', since.toISOString().slice(0, 10))
        .order('as_of', { ascending: true }),
      db.from('app_config').select('key,value'),
    ]);

    const funds = (fundsRes.data ?? []) as FundRow[];
    const hist = (histRes.data ?? []) as HistRow[];
    const cfg = new Map(((cfgRes.data ?? []) as { key: string; value: unknown }[]).map((r) => [r.key, r.value]));
    if (!funds.length || !hist.length) return FALLBACK_CHARTS;

    // shared x-axis: the last MONTH_MARKS months that actually have data
    const keys = [...new Set(hist.map((h) => monthKey(h.as_of)))].sort().slice(-MONTH_MARKS);
    if (keys.length < 3) return FALLBACK_CHARTS;
    const months = keys.map(monthLabel);
    const series = monthlySeries(hist, keys);

    // T-bill curve, overridable from config so an auction print does not need a deploy
    const num = (k: string, d: number) => {
      const v = cfg.get(k);
      const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
      return Number.isFinite(n) ? n : d;
    };
    const t91 = num('market.tbill_91', 8.7067);
    const t182 = num('market.tbill_182', 8.6006);
    const t364 = num('market.tbill_364', 8.8715);
    const cbr = num('market.cbr', CBR);
    const bench: [string, string][] = [
      ['CBR', cbr.toFixed(2)],
      ['Inflation', INFLATION.toFixed(2)],
      ['91d T-bill', t91.toFixed(2)],
    ];

    const tabs = [
      pickTab('kes', 'MMF KES', funds, series, (f) => f.fund_type === 'mmf' && f.currency === 'KES', 4, bench),
      pickTab('usd', 'MMF USD', funds, series, (f) => f.fund_type === 'mmf' && f.currency === 'USD', 3, bench),
      pickTab('fixed', 'Fixed income', funds, series, (f) => f.fund_type === 'fixed_income', 3, bench),
    ].filter((t): t is RateTab => t !== null);
    if (!tabs.length) return FALLBACK_CHARTS;

    // gross yields for the net-of-tax bars: top 6 KES money market
    const netOfTax = funds
      .filter((f) => f.basis === 'yield' && f.fund_type === 'mmf' && f.currency === 'KES' && f.current_rate != null)
      .sort((a, b) => (b.current_rate ?? 0) - (a.current_rate ?? 0))
      .slice(0, 6)
      .map((f) => ({ name: f.name, gross: f.current_rate as number }));

    // the alert chart follows the leader of the first tab
    const lead = tabs[0].series.find((s) => s.lead) ?? tabs[0].series[0];
    const threshold = Math.floor(Math.max(...lead.values) * 2) / 2 - 0.5; // nearest half point below the peak
    const crossedIdx = lead.values.findIndex((v) => v >= threshold);
    const alert = {
      fund: lead.name,
      labels: months,
      values: lead.values,
      threshold,
      crossedAt: crossedIdx >= 0 ? months[crossedIdx] : null,
    };

    /*
     * Industry split, in preference order:
     *   1. market.aum_by_fund_type  authoritative, exact shillings from CMA
     *   2. market.aum_by_class      legacy flat map, already in billions
     *   3. fund count               honest fallback, never presented as money
     *
     * The count branch is not a degraded version of the AUM branch. It answers a
     * different question, so it carries its own label and its own tooltip unit
     * and the donut says which one it is showing.
     */
    const slices =
      slicesFromFundType(cfg.get('market.aum_by_fund_type')) ??
      slicesFromLegacy(cfg.get('market.aum_by_class'));

    let market: LandingCharts['market'];
    if (slices) {
      const total = slices.reduce((s, x) => s + x.value, 0);
      market = { mode: 'aum', label: 'industry AUM', total: `${total.toFixed(1)}B`, slices };
    } else {
      const counts = new Map<string, number>();
      for (const f of funds) {
        const k = f.fund_type ?? 'other';
        counts.set(k, (counts.get(k) ?? 0) + 1);
      }
      const countSlices = [...counts.entries()]
        .map(([name, value]) => ({ name, value }))
        .sort((a, b) => b.value - a.value);
      market = {
        mode: 'count',
        label: 'funds tracked',
        total: String(funds.length),
        slices: countSlices,
      };
    }

    return {
      months,
      tabs,
      netOfTax,
      alert,
      market,
      curve: { labels: ['91d', '182d', '364d'], values: [t91, t182, t364] },
      live: true,
    };
  } catch {
    return FALLBACK_CHARTS;
  }
}
