export interface RatePoint {
  fund_id: string;
  rate: number;      // gross effective annual yield, %
  as_of: string;     // YYYY-MM-DD (EAT day)
  source: string;    // scraper id
  source_url?: string;
}

// A source adapter is the ONLY place that knows a source's shape.
// It returns raw (name, rate) rows; mapping to fund_id happens upstream,
// so swapping sources never touches the pipeline.
export interface SourceRow {
  name: string;                 // fund/company name as the source labels it
  rate: number;                 // gross EAR, %
  currency: "KES" | "USD";
  asOf?: string;                // optional YYYY-MM-DD; overrides the run date
}

export interface SourceAdapter {
  id: string;
  fetchRows(): Promise<SourceRow[]>;
}

// ── Snapshot v2 shapes ─────────────────────────────────────────────────────
// v2 keeps every v1 field and adds companies/agents/insurers/fx/templates/
// events. The app reads `schema` and falls back to v1 when it's absent.

export interface SnapshotFund {
  id: string;
  name: string;
  manager: string;
  category: string;
  fund_type: string | null;   // mmf | fixed_income | equity | balanced | special
  currency: string;
  basis: string | null;       // yield | nav | none — drives whether a rate shows
  retail: boolean;            // consumer-visible cut
  current_rate: number | null;
  tax_free: boolean;
  min_invest: number | null;
  mgmt_fee: number | null;
  site_url: string | null;
  invest_url: string | null;
  contact_url: string | null;
  logo_domain: string | null;
  verified: boolean;
  featured: boolean;
  company_id: string | null;

  // Profile & terms (migration 0026) — static per-fund facts from fact sheets.
  inception_date: string | null;  // YYYY-MM-DD; "operating since" trust signal
  benchmark_key: string | null;   // tbill_91 | tbill_182 | tbill_364 | cbr
  expense_ratio: number | null;   // all-in TER, % p.a.
  redemption_fee: number | null;  // exit fee, %
  lock_in_months: number | null;  // 0/null = no lock-in
  top_up_min: number | null;      // subsequent top-up minimum
  objective: string | null;       // one-line fund aim

  // Trailing performance (migration 0027) — latest standing from the manager's
  // monthly fact sheet. Per-horizon benchmark so vs-benchmark is on-basis.
  return_ytd: number | null;      // fund, % year to date
  return_1y: number | null;       // fund, annualised %
  return_3y: number | null;
  return_5y: number | null;
  bench_1y: number | null;        // stated benchmark, annualised %
  bench_3y: number | null;
  bench_5y: number | null;
  best_month: number | null;      // best monthly return, trailing 12 mo, %
  worst_month: number | null;     // worst monthly return, trailing 12 mo, %
  returns_as_of: string | null;   // YYYY-MM-DD, fact-sheet month
}

export interface SnapshotCompany {
  id: string;
  name: string;
  type: string;                 // fund_manager | insurer | sacco | government
  brand_color: string | null;
  logo_url: string | null;
  website: string | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  verified: boolean;
  aum_kes: number | null;
  market_share: number | null;
  rank: number | null;
  aum_as_of: string | null;

  // Custody chain (migration 0026) — manager-family trust signals.
  trustee: string | null;
  custodian: string | null;
  auditor: string | null;
}

export interface SnapshotAgent {
  id: string;
  name: string;
  role: string | null;
  phone: string | null;
  whatsapp: boolean;
  photo_url: string | null;
  is_free: boolean;
  company_ids: string[];
}

export interface SnapshotInsurer {
  id: string;
  name: string;
  company_id: string | null;
  currency: string;
  plans: unknown;               // legacy named tiers; superseded by travel_regions
  min_premium: number | null;
  excess_pct: number | null;
  excess_min: number | null;
  claims_days: number | null;
  rating: number | null;
  motor_rate: number | null;    // % of vehicle value (selected all along, was untyped)
  benefits: string[];           // cover benefit chips (selected all along, was untyped)
  logo_domain: string | null;

  // IN-3 detail surface (migration 0039).
  settle_pct: number | null;
  licensed_since: number | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  paybill: string | null;
  website: string | null;
  brand_color: string | null;
  classes: { code: string; label: string }[] | null;
  signals: { tag: string; label: string; text: string }[] | null;
  travel_regions: { ea?: number; af?: number; ww?: number; sch?: number } | null;
  travel_cover: string | null;
}

// Admin-managed grid on the Insure home (migration 0041). Motor and Travel
// route to live comparison flows; other keys render as coming-soon cards.
export interface SnapshotInsuranceType {
  key: string;
  label: string;
  icon: string | null;   // material icon name, mapped app-side
  status: string;        // 'live' | 'soon'
  ord: number;
  sub: string | null;    // optional static subtitle
}

export interface SnapshotFx {
  pair: string;                 // 'USD/KES'
  rate: number;
  as_of: string;
}

export interface SnapshotTemplate {
  key: string;
  tag: "STRENGTH" | "WATCH" | "NOTE";
  template: string;
}

export interface SnapshotEvent {
  type: string;
  category: string | null;
  fund_id: string | null;
  payload: unknown;
  created_at: string;
}

export interface SnapshotV2 {
  schema: 2;
  as_of: string;
  generated_at: string;
  funds: SnapshotFund[];
  insurers: SnapshotInsurer[];
  companies: SnapshotCompany[];
  agents: SnapshotAgent[];
  fx: SnapshotFx[];
  insight_templates: SnapshotTemplate[];
  events: SnapshotEvent[];
}

// ── Learn (D2) ──────────────────────────────────────────────────────────────
// units → lessons → steps, nested. A step's `payload` shape depends on `kind`
// (explainer | interactive | quiz) and is parsed app-side. A lesson's optional
// `fund_id` is resolved to the LIVE rate in-app for the "live term" badge and
// "See it live", so content never hard-codes a stale number.

export interface SnapshotLearnStep {
  id: string;
  kind: string;
  payload: unknown;
}

export interface SnapshotLearnLesson {
  id: string;
  title: string;
  xp: number;
  fund_id: string | null;
  steps: SnapshotLearnStep[];
}

export interface SnapshotLearnUnit {
  id: string;
  title: string;
  subtitle: string | null;
  accent: string | null;
  unlock_after: string | null;
  lessons: SnapshotLearnLesson[];
}

export interface SnapshotLearn {
  units: SnapshotLearnUnit[];
}

// ── Posts (D3) ──────────────────────────────────────────────────────────────
// Blog articles + curated market briefs from the unified posts table, published
// inside the snapshot next to learn. `kind` discriminates: 'article' (evergreen,
// hero + reading time) vs 'brief' (short, timely, optional fund/company link).
// Only published rows are serialised; pinned first, newest first. There is no
// news scraper — briefs are authored in admin. The builder maps the DB's 0035
// names (excerpt -> summary, cover_url -> hero_image_url) into this app shape;
// slug is the identity (no separate id).

export interface SnapshotPost {
  slug: string;
  kind: "article" | "brief";
  title: string;
  summary: string | null;       // from posts.excerpt
  body: string | null;
  hero_image_url: string | null; // from posts.cover_url
  author: string | null;
  tags: string[];
  fund_id: string | null;       // optional soft link, resolved to live rate in-app
  company_id: string | null;    // optional soft link
  pinned: boolean;
  reading_minutes: number | null;
  published_at: string | null;
}
