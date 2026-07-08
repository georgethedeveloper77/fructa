// Landing content model + defaults + a pure config merge.
//
// Types and DEFAULT_CONTENT are client-safe (Landing.tsx imports the types).
// The live read lives in content.server.ts, which calls applyConfig() below.

export type Series = { name: string; values: number[]; lead?: boolean };
export type ChartTab = {
  key: string;
  label: string;
  unit: string;
  series: Series[];
  benchmarks: [string, string][];
};

export type LandingContent = {
  brand: { name: string; footerBlurb: string; contactEmail: string };
  seo: { title: string; description: string; ogImage: string | null };
  links: { androidUrl: string; iosUrl: string };
  hero: { headline: string; headlineAccent: string; subhead: string; microtrust: string };
  cta: { headline: string; subhead: string };
  stats: { n: string; l: string }[];
  images: { rank: string | null; portfolio: string | null; alerts: string | null };
  months: string[];
  chart: ChartTab[];
};

export const DEFAULT_CONTENT: LandingContent = {
  brand: {
    name: 'Fructa',
    footerBlurb:
      'The rates terminal for Kenyan money. Rates are informational and not financial advice.',
    contactEmail: 'hello@fructa.africa',
  },
  seo: {
    title: 'Fructa — the rates terminal for Kenyan money',
    description:
      'Money market funds, T-bills, bonds, SACCOs and insurance. Every live rate in Kenya, ranked and compared, with your own holdings on top.',
    ogImage: null,
  },
  links: { androidUrl: '#', iosUrl: '#' },
  hero: {
    headline: 'Every Kenyan rate.',
    headlineAccent: 'One terminal.',
    subhead:
      'Money market funds, T-bills, bonds, SACCOs and insurance — every live rate in Kenya, ranked and compared, with your own holdings on top.',
    microtrust: '144 funds tracked · updated at noon EAT, every weekday',
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
  images: { rank: null, portfolio: null, alerts: null },
  months: ['Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
  chart: [
    {
      key: 'kes',
      label: 'MMF KES',
      unit: '%',
      series: [
        { name: 'Etica MMF', lead: true, values: [10.1, 10.4, 10.9, 11.5, 12.0, 12.6, 13.0, 13.42] },
        { name: 'Cytonn MMF', values: [9.9, 10.2, 10.6, 11.1, 11.6, 12.2, 12.7, 13.11] },
        { name: 'Kuza MMF', values: [9.6, 9.9, 10.3, 10.8, 11.3, 11.9, 12.4, 12.88] },
        { name: 'GenAfrica MMF', values: [9.2, 9.4, 9.8, 10.2, 10.7, 11.3, 11.9, 12.4] },
      ],
      benchmarks: [['CBR', '8.75'], ['Inflation', '6.70'], ['91d T-bill', '8.71']],
    },
    {
      key: 'usd',
      label: 'MMF USD',
      unit: '%',
      series: [
        { name: 'Nabo USD', lead: true, values: [5.0, 5.1, 5.3, 5.6, 5.8, 6.0, 6.1, 6.2] },
        { name: 'Old Mutual USD', values: [4.7, 4.8, 5.0, 5.2, 5.4, 5.6, 5.8, 5.9] },
        { name: 'Sanlam USD', values: [4.4, 4.5, 4.7, 4.9, 5.1, 5.3, 5.5, 5.6] },
      ],
      benchmarks: [['Fed range', '4.50'], ['USD infl.', '3.10'], ['SOFR', '4.38']],
    },
    {
      key: 'fixed',
      label: 'Fixed Income',
      unit: '%',
      series: [
        { name: '364-Day', lead: true, values: [8.5, 8.55, 8.6, 8.62, 8.7, 8.75, 8.8, 8.87] },
        { name: '182-Day', values: [8.3, 8.35, 8.42, 8.45, 8.5, 8.55, 8.58, 8.6] },
        { name: '91-Day', values: [8.2, 8.25, 8.3, 8.35, 8.5, 8.6, 8.68, 8.71] },
      ],
      benchmarks: [['CBR', '8.75'], ['Inflation', '6.70'], ['Auction', '15 Jun']],
    },
  ],
};

/**
 * Merge app_config rows over the defaults. Pure — takes already-parsed rows
 * (jsonb comes back as JS values). Unknown/empty keys keep the default, so a
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
      .map((s) => ({ n: String((s as any).n ?? ''), l: String((s as any).l ?? '') }))
      .filter((s) => s.n || s.l);
    if (clean.length) c.stats = clean;
  }

  c.images.rank = img('landing.feature_rank_image');
  c.images.portfolio = img('landing.feature_portfolio_image');
  c.images.alerts = img('landing.feature_alerts_image');

  return c;
}
