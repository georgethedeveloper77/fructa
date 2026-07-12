// Landing content model + defaults + a pure config merge.
//
// Types and DEFAULT_CONTENT are client-safe (Landing.tsx imports the types).
// The live read lives in content.server.ts, which calls applyConfig() below.
//
// The landing is chart-led: there are no marketing screenshots to upload. The
// chart shapes live in LandingCharts and are computed from rate_history + funds
// in charts.server.ts. FALLBACK_CHARTS below is what renders if that read fails,
// so the page can never break, but it is clearly marked and must never be
// mistaken for live data.

export type Series = { name: string; values: number[]; lead?: boolean };

export type RateTab = {
  key: string;
  label: string;
  unit: string;
  series: Series[];
  benchmarks: [string, string][];
};

export type MarketSlice = { name: string; value: number };

export type LandingCharts = {
  /** x-axis labels shared by the hero tabs, oldest to newest */
  months: string[];
  tabs: RateTab[];
  /** top MMF gross yields; net and real are derived client-side from WHT + inflation */
  netOfTax: { name: string; gross: number }[];
  /** the lead fund's own history, with the alert line the copy talks about */
  alert: { fund: string; labels: string[]; values: number[]; threshold: number; crossedAt: string | null };
  /** industry split. `mode` says whether the slices are AUM or fund counts. */
  market: { mode: 'aum' | 'count'; label: string; total: string; slices: MarketSlice[] };
  /** T-bill curve */
  curve: { labels: string[]; values: number[] };
  /** true when every chart above came from the database */
  live: boolean;
};

export type LandingContent = {
  brand: { name: string; footerBlurb: string; contactEmail: string };
  seo: { title: string; description: string; ogImage: string | null };
  links: { androidUrl: string; iosUrl: string };
  hero: { headline: string; headlineAccent: string; subhead: string; microtrust: string };
  cta: { headline: string; subhead: string };
  stats: { n: string; l: string }[];
};

/** Withholding tax on Kenyan fund income, and the inflation print the real
 *  return is measured against. Both are shown as labels on the landing, so they
 *  live in one place. Move to the benchmarks table once its schema is settled. */
export const WHT = 0.15;
export const INFLATION = 6.7;
export const CBR = 8.75;

export const DEFAULT_CONTENT: LandingContent = {
  brand: {
    name: 'Fructa',
    footerBlurb:
      'The rates terminal for Kenyan money. Rates are informational and not financial advice.',
    contactEmail: 'hello@fructa.africa',
  },
  seo: {
    title: 'Fructa, the rates terminal for Kenyan money',
    description:
      'Money market funds, T-bills, bonds, SACCOs and insurance. Every live rate in Kenya, ranked and compared, with your own holdings on top.',
    ogImage: null,
  },
  links: { androidUrl: '#', iosUrl: '#' },
  hero: {
    headline: 'Every Kenyan rate.',
    headlineAccent: 'One terminal.',
    subhead:
      'Money market funds, T-bills, bonds, SACCOs and insurance. Every live rate in Kenya, ranked and compared, with your own holdings on top.',
    microtrust: '144 funds tracked, updated at noon EAT every weekday',
  },
  cta: {
    headline: 'Stop hunting for yields.',
    subhead: 'Download Fructa and see where your money should be sitting.',
  },
  stats: [
    { n: '144', l: 'funds tracked across the market' },
    { n: '96.8%', l: 'of industry AUM covered' },
    { n: 'Noon', l: 'EAT refresh, every weekday' },
    { n: '6', l: 'asset classes in one board' },
  ],
};

/**
 * Rendered ONLY when the database read fails. Deliberately flat and unflattering
 * so a silent fallback is obvious in review rather than passing as live data.
 * `live: false` also hides the LIVE pip in the terminal header.
 */
export const FALLBACK_CHARTS: LandingCharts = {
  months: [],
  tabs: [],
  netOfTax: [],
  alert: { fund: '', labels: [], values: [], threshold: 0, crossedAt: null },
  market: { mode: 'count', label: 'funds by asset class', total: '0', slices: [] },
  curve: { labels: [], values: [] },
  live: false,
};

/**
 * Merge app_config rows over the defaults. Pure, takes already-parsed rows
 * (jsonb comes back as JS values). Unknown or empty keys keep the default, so a
 * deleted or blank value can never blank the page.
 */
export function applyConfig(rows: { key: string; value: unknown }[]): LandingContent {
  const m = new Map(rows.map((r) => [r.key, r.value] as const));
  const str = (k: string, d: string) => {
    const v = m.get(k);
    return typeof v === 'string' && v.trim() ? v : d;
  };
  const img = (k: string): string | null => {
    const v = m.get(k);
    return typeof v === 'string' && v.trim() ? v : null;
  };

  const c: LandingContent = structuredClone(DEFAULT_CONTENT);

  c.brand.name = str('brand.name', c.brand.name);
  c.brand.footerBlurb = str('brand.footer_blurb', c.brand.footerBlurb);
  c.brand.contactEmail = str('brand.contact_email', c.brand.contactEmail);

  c.seo.title = str('seo.title', c.seo.title);
  c.seo.description = str('seo.description', c.seo.description);
  c.seo.ogImage = img('seo.og_image');

  c.links.androidUrl = str('links.android_url', c.links.androidUrl);
  c.links.iosUrl = str('links.ios_url', c.links.iosUrl);

  c.hero.headline = str('landing.hero_headline', c.hero.headline);
  c.hero.headlineAccent = str('landing.hero_accent', c.hero.headlineAccent);
  c.hero.subhead = str('landing.hero_subhead', c.hero.subhead);
  c.hero.microtrust = str('landing.hero_microtrust', c.hero.microtrust);

  c.cta.headline = str('landing.cta_headline', c.cta.headline);
  c.cta.subhead = str('landing.cta_subhead', c.cta.subhead);

  const stats = m.get('landing.stats');
  if (Array.isArray(stats)) {
    const clean = stats
      .filter((s): s is { n: string; l: string } => !!s && typeof s === 'object')
      .map((s) => ({ n: String((s as { n?: unknown }).n ?? ''), l: String((s as { l?: unknown }).l ?? '') }))
      .filter((s) => s.n || s.l);
    if (clean.length) c.stats = clean;
  }

  return c;
}
