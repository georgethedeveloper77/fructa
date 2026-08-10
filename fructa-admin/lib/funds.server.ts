import { supabaseAdmin } from "@/lib/supabase/server";
import { slugify } from "@/lib/publish";

/*
 * Data layer for the public /funds pages.
 *
 * These pages exist because the entire public site was one indexable route
 * competing for a whole market. Somebody searching "cic money market fund rate"
 * is asking a question this database answers precisely, and until now the only
 * pages ranking for it were blog posts quoting figures from two years ago.
 *
 * Read-only and server-only. Same tables the landing charts read, same rule
 * that `fund_type` is authoritative and `category` is legacy.
 */

/**
 * Withholding tax on Kenyan money market fund interest, as a percentage.
 *
 * The Flutter app takes this from RemoteConfig.whtPct, which is published in
 * the snapshot. There is no confirmed `app_config` key for it on the web side,
 * so this reads a candidate key and falls back to the statutory 15. If the real
 * key differs, add it to WHT_KEYS rather than editing the constant, so the two
 * surfaces cannot drift into quoting different net figures for the same fund.
 */
const WHT_FALLBACK = 15;
const WHT_KEYS = ["market.wht_pct", "tax.wht_pct", "wht_pct"];

export type PublicFund = {
  id: string;
  slug: string;
  name: string;
  manager: string | null;
  fundType: string | null;
  currency: string;
  basis: string | null;
  grossRate: number | null;
  taxFree: boolean;
  minInvest: number | null;
  mgmtFee: number | null;
  siteUrl: string | null;
  updatedAt: string | null;
};

export type RatePoint = { asOf: string; rate: number };

export type FundsBundle = {
  funds: PublicFund[];
  whtPct: number;
  /** Latest rate_history date across all funds, for "as of" copy. */
  asOf: string | null;
};

type FundRow = {
  id: string;
  name: string;
  manager: string | null;
  fund_type: string | null;
  currency: string | null;
  basis: string | null;
  current_rate: number | null;
  tax_free: boolean | null;
  min_invest: number | null;
  mgmt_fee: number | null;
  site_url: string | null;
  status: string | null;
  updated_at: string | null;
};

/**
 * Slug from the fund's NAME, not its id.
 *
 * The ids are internal and often unlovely (`nabo-africa-funds-mmf-kes--2`), and
 * one of them lies outright: it carries a `-kes` suffix while the fund is USD.
 * The name slugifies to exactly what a person types into Google, which is the
 * only reason these pages exist.
 *
 * Collisions are resolved deterministically so a URL never moves between
 * deploys: currency first, then the id, and the funds are sorted by id before
 * assignment so the winner of a tie is stable.
 */
function assignSlugs(rows: FundRow[]): Map<string, string> {
  const sorted = [...rows].sort((a, b) => a.id.localeCompare(b.id));
  const counts = new Map<string, number>();
  for (const r of sorted) {
    const base = slugify(r.name);
    counts.set(base, (counts.get(base) ?? 0) + 1);
  }

  const used = new Set<string>();
  const out = new Map<string, string>();
  for (const r of sorted) {
    const base = slugify(r.name);
    let slug = base;
    if ((counts.get(base) ?? 0) > 1) {
      slug = `${base}-${(r.currency ?? "kes").toLowerCase()}`;
    }
    if (used.has(slug)) slug = `${base}-${slugify(r.id)}`;
    used.add(slug);
    out.set(r.id, slug);
  }
  return out;
}

function toPublic(r: FundRow, slug: string): PublicFund {
  return {
    id: r.id,
    slug,
    name: r.name,
    manager: r.manager,
    fundType: r.fund_type,
    currency: r.currency ?? "KES",
    basis: r.basis,
    grossRate: r.current_rate,
    taxFree: r.tax_free === true,
    minInvest: r.min_invest,
    mgmtFee: r.mgmt_fee,
    siteUrl: r.site_url,
    updatedAt: r.updated_at,
  };
}

/** Every publishable fund, ranked by gross yield, leader first. */
export async function getFunds(): Promise<FundsBundle> {
  try {
    const db = supabaseAdmin();
    const [fundsRes, cfgRes, lastRes] = await Promise.all([
      db
        .from("funds")
        .select(
          "id,name,manager,fund_type,currency,basis,current_rate,tax_free,min_invest,mgmt_fee,site_url,status,updated_at",
        ),
      db.from("app_config").select("key,value"),
      db
        .from("rate_history")
        .select("as_of")
        .order("as_of", { ascending: false })
        .limit(1),
    ]);

    const rows = ((fundsRes.data ?? []) as FundRow[]).filter(
      // Hidden funds are hidden everywhere. A page Google indexes and a page the
      // app refuses to show is worse than no page at all.
      (r) => r.status !== "hidden" && r.name,
    );

    const cfg = new Map(
      ((cfgRes.data ?? []) as { key: string; value: unknown }[]).map((r) => [
        r.key,
        r.value,
      ]),
    );
    let whtPct = WHT_FALLBACK;
    for (const k of WHT_KEYS) {
      const v = Number(cfg.get(k));
      if (Number.isFinite(v) && v > 0 && v < 100) {
        whtPct = v;
        break;
      }
    }

    const slugs = assignSlugs(rows);
    const funds = rows
      .map((r) => toPublic(r, slugs.get(r.id)!))
      .sort((a, b) => (b.grossRate ?? -1) - (a.grossRate ?? -1));

    const asOf =
      ((lastRes.data ?? []) as { as_of: string }[])[0]?.as_of ?? null;

    return { funds, whtPct, asOf };
  } catch {
    // Fails soft. An empty list renders an honest "rates unavailable" page
    // rather than a 500, which Google would treat far less kindly.
    return { funds: [], whtPct: WHT_FALLBACK, asOf: null };
  }
}

export async function getFundBySlug(
  slug: string,
): Promise<{ fund: PublicFund; bundle: FundsBundle } | null> {
  const bundle = await getFunds();
  const fund = bundle.funds.find((f) => f.slug === slug);
  return fund ? { fund, bundle } : null;
}

/** Monthly closing rate for one fund, oldest first. */
export async function getFundHistory(
  fundId: string,
  months = 12,
): Promise<RatePoint[]> {
  try {
    const since = new Date();
    since.setMonth(since.getMonth() - months);
    const { data } = await supabaseAdmin()
      .from("rate_history")
      .select("rate,as_of")
      .eq("fund_id", fundId)
      .gte("as_of", since.toISOString().slice(0, 10))
      .order("as_of", { ascending: true });

    const rows = (data ?? []) as { rate: number | null; as_of: string }[];
    // Last observation per calendar month: a fund quoted daily would otherwise
    // render two hundred near-identical rows and say nothing.
    const byMonth = new Map<string, RatePoint>();
    for (const r of rows) {
      if (r.rate == null) continue;
      byMonth.set(r.as_of.slice(0, 7), { asOf: r.as_of, rate: r.rate });
    }
    return [...byMonth.values()];
  } catch {
    return [];
  }
}

/** Same type and currency, ranked, excluding [fund]. Drives internal linking. */
export function peersOf(fund: PublicFund, all: PublicFund[], n = 6) {
  return all
    .filter(
      (f) =>
        f.id !== fund.id &&
        f.fundType === fund.fundType &&
        f.currency === fund.currency &&
        f.grossRate != null,
    )
    .slice(0, n);
}

// ── Derived figures ────────────────────────────────────────────────────────

/** After withholding. A tax-free fund keeps its gross. */
export function netRate(f: PublicFund, whtPct: number): number | null {
  if (f.grossRate == null) return null;
  return f.taxFree ? f.grossRate : f.grossRate * (1 - whtPct / 100);
}

/**
 * After withholding AND inflation, Fisher rather than subtraction.
 *
 * Matches `Fund.realRate` in the Flutter app exactly. Subtracting would read
 * 3.08% where the app prints 2.88% for the same fund on the same day, and a
 * number that disagrees with the app is worse than no number.
 */
export function realRate(
  f: PublicFund,
  whtPct: number,
  inflationPct: number,
): number | null {
  const n = netRate(f, whtPct);
  if (n == null) return null;
  return ((1 + n / 100) / (1 + inflationPct / 100) - 1) * 100;
}

export const FUND_TYPE_LABEL: Record<string, string> = {
  mmf: "Money market fund",
  fixed_income: "Fixed income fund",
  equity: "Equity fund",
  balanced: "Balanced fund",
  special: "Special fund",
};

export const pct = (v: number | null | undefined, dp = 2) =>
  v == null ? null : `${v.toFixed(dp)}%`;

export const money = (currency: string, v: number | null | undefined) =>
  v == null ? null : `${currency} ${Math.round(v).toLocaleString("en-KE")}`;

export const fmtDay = (iso: string | null) =>
  !iso
    ? ""
    : new Date(iso).toLocaleDateString("en-GB", {
        day: "numeric",
        month: "short",
        year: "numeric",
      });
