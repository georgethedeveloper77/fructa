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

  // Priced (NAV) fields (migration 0040). A basis='nav' fund quotes a unit
  // price instead of a yield. Added to the snapshot in July 2026: the columns
  // and the admin writer shipped with 0040, but the builder never selected
  // them, so no NAV ever reached the app. Null for every yield fund.
  price_per_unit: number | null;    // NAV per unit, fund's own currency
  price_as_of: string | null;       // YYYY-MM-DD, quote date
  distribution_pct: number | null;  // income distribution / interest %

  // C2 sparkline, attached by the builder (not a column). Absent when the
  // fund has fewer than 2 history points in the window.
  spark?: number[];
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

// ── Stocks (0047) ───────────────────────────────────────────────────────────
// NSE-listed equities. Deliberately NOT modelled as funds: a stock has a
// ticker, a dividend stream and (optionally) a price, not a yield.
//
// LICENCE NOTE. Everything in the "facts" block below comes from public company
// filings and announcements and always publishes. The "price block" is NSE
// market data and is subject to an NSE redistribution licence. The snapshot
// builder emits those fields ONLY when the app_config key
// `stocks.prices_enabled` is true. When it is false every price field is null,
// the app hides the price cells, and Fructa redistributes no market data.

export interface SnapshotStockDividend {
  financial_year: number;
  kind: string;                 // interim | final | special
  dps_kes: number;              // dividend per share, KES
  declared_on: string | null;
  // THE date that matters to a buyer. To receive a dividend you must own the
  // share on the books when they close, so this is a deadline, not trivia. It
  // was in the table from 0047 and never published, which meant the app knew
  // when a dividend would be PAID but not by when you had to own the share to
  // get it. That is the wrong half of the fact.
  book_closure: string | null;
  payment_date: string | null;
  source_url: string | null;
}

export interface SnapshotStock {
  // Facts. Public. Always published.
  id: string;
  ticker: string;               // e.g. 'SCOM'
  name: string;
  sector: string | null;
  segment: string | null;       // MIM | AIM | GEMS
  about: string | null;
  logo_url: string | null;
  brand_color: string | null;
  website: string | null;
  ir_url: string | null;
  listed_on: string | null;
  shares_outstanding: number | null;

  // Dividends. Public. Always published.
  dividends: SnapshotStockDividend[];
  dps_latest: number | null;    // sum of all kinds in the most recent FY
  dps_year: number | null;      // that FY

  // Earnings. Public, admin-typed off the company's own results. Always
  // published, because EPS is a fact about the company and not a price.
  eps: number | null;           // may be NEGATIVE for a loss-making company
  eps_year: number | null;      // the FY the EPS belongs to

  // Price block. All null when the stocks.prices_enabled KILL SWITCH is off.
  //
  // This used to be labelled "LICENCE GATED", which was wrong. End-of-day
  // closes are facts of public record, printed in the Kenyan press daily, and
  // the change, market cap, yield and sparkline are our own figures derived
  // from our own stored series. Nothing here is waiting on an agreement. The
  // flag exists so a bad parse or a dead source can be switched off in Config
  // and vanish from the app on the next rebuild, with no release.
  close_kes: number | null;
  prev_close: number | null;
  change_pct: number | null;
  price_as_of: string | null;
  market_cap: number | null;    // close x shares_outstanding
  div_yield: number | null;     // dps_latest / close, % (needs a price)

  // Price / earnings. Needs BOTH a price and a positive EPS, so it rides with
  // the price block. Null on a loss: a negative multiple is not a cheap stock,
  // it is a meaningless number, and the app must not print one.
  pe: number | null;
  spark: number[] | null;
}

// CMA-licensed stockbrokers. Fructa routes users out to these and never
// executes a trade itself, so this is a directory, not an order path.
export interface SnapshotBroker {
  id: string;
  name: string;
  license_no: string | null;
  blurb: string | null;
  phone: string | null;
  email: string | null;
  website: string | null;
  app_url: string | null;
  logo_url: string | null;
}

// A price adapter is the only place that knows an NSE feed's shape. Mirrors
// SourceAdapter. Rows are keyed by ticker; mapping happens upstream.
export interface StockPriceRow {
  ticker: string;
  close: number;
  prevClose?: number;
  high?: number;
  low?: number;
  volume?: number;
  asOf?: string;                // YYYY-MM-DD; overrides the run date
}

export interface StockPriceAdapter {
  id: string;
  fetchRows(): Promise<StockPriceRow[]>;
}

// ── SACCOs (0062) ───────────────────────────────────────────────────────────
// SASRA-regulated co-operative societies. Deliberately NOT modelled as funds.
//
// A SACCO carries TWO rates, and they are paid on two different pots of money:
//
//   interest_on_deposits       paid on member savings. Uncapped, and it is what
//                              secures a member's borrowing. This is the number
//                              the app ranks on, because it is the one that
//                              decides how much money a member actually
//                              receives.
//   dividend_on_share_capital  paid on member share capital, which is capped.
//                              It is almost always the bigger percentage and
//                              almost always the smaller cheque. Display only.
//                              NEVER sorted on, never shown as a bare number.
//
// A member with 500,000 in deposits at 13% and 50,000 in shares at 20% earns
// 65,000 from the 13% and 10,000 from the 20%. Leading a tile with the 20% is
// not a rounding error, it is telling someone the wrong thing about their money.
// So the two rates are separate fields with separate names and there is no
// single field called "rate" that could be either one.

export interface SnapshotSaccoRate {
  financial_year: number;                    // the year that ENDED, e.g. 2025
  interest_on_deposits: number | null;       // %, paid on savings
  dividend_on_share_capital: number | null;  // %, paid on shares
  declared_on: string | null;                // AGM date
  source_url: string | null;
  source_doc: string | null;
}

export interface SnapshotSacco {
  // Identity and regulation.
  id: string;
  name: string;                    // verbatim from the SASRA register
  display_name: string;            // short form for tiles
  sasra_licensed_until: string | null;
  tier: number | null;             // 1, 2 or 3, from the supervision report

  // Membership. `bond` decides whether a user can join AT ALL, which matters
  // more than the rate: a SACCO you cannot join has no business outranking one
  // you can. 'unknown' is treated as not joinable, never as open.
  bond: string;                    // 'open' | 'closed' | 'unknown'
  bond_note: string | null;        // e.g. 'University of Nairobi staff'
  joinable: boolean;               // bond === 'open'

  // Location and contact.
  county: string | null;
  physical_location: string | null;
  branches: number | null;
  website: string | null;
  phone: string | null;
  email: string | null;

  // Brand.
  logo_url: string | null;
  brand_color: string | null;
  about: string | null;

  // THE LOCK. Required, not optional, and always true.
  //
  // A SACCO deposit rate and a money market yield are the same shape as numbers
  // and are NOT the same shape as promises. The fund returns your money in two
  // working days. The SACCO returns it when you resign your membership. If a
  // SACCO enters the All league table without this rendered, the app is quietly
  // telling people that locked money beats liquid money.
  //
  // It is a field rather than something the app derives from the row's type
  // because a derived flag is one refactor away from being dropped. The app
  // treats a missing `locked` as an error, not as false.
  locked: true;

  // Rates. Two of them. Named so they cannot be confused for one another.
  interest_on_deposits: number | null;       // the ranked number
  dividend_on_share_capital: number | null;  // display only
  rate_year: number | null;                  // financial year of the above
  rate_declared_on: string | null;
  rate_source_url: string | null;
  rate_source_doc: string | null;
  // Every declared year, newest first. Drives the AGM history chart.
  rate_history: SnapshotSaccoRate[];

  // Joining terms, from the SACCO's own published terms.
  registration_fee_kes: number | null;
  min_share_capital_kes: number | null;
  min_monthly_deposit_kes: number | null;
  loan_multiple: number | null;      // borrow up to Nx your deposits
  deposit_notice_days: number | null;
  has_fosa: boolean | null;

  // The institution, from the SASRA Sacco Supervision Annual Report.
  total_assets_kes: number | null;
  deposits_kes: number | null;
  members: number | null;
  registered_year: number | null;
  financials_as_of: string | null;
}
