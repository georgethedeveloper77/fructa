import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.85.0";
import type {
  SnapshotAgent,
  SnapshotBroker,
  SnapshotCompany,
  SnapshotEvent,
  SnapshotFund,
  SnapshotFx,
  SnapshotInsurer,
  SnapshotInsuranceType,
  SnapshotLearn,
  SnapshotLearnLesson,
  SnapshotLearnStep,
  SnapshotPost,
  SnapshotSacco,
  SnapshotSaccoRate,
  SnapshotStock,
  SnapshotStockDividend,
  SnapshotTemplate,
  SnapshotV2,
} from "./types.ts";

// Publishes ONE static snapshot the app reads cache-first, instead of the app
// querying Supabase on every open. Called at the end of every scrape run, and
// standalone via the publish-snapshot function.
//
// v2: adds companies/agents/insurers/fx/insight_templates/events. Every v1
// field is preserved; the app reads `schema` and falls back to v1 parsing.

const BUCKET = "snapshots";
const FILE = "funds-snapshot.json";

// Profile fields (0026): inception, benchmark key, expense/redemption/lock-in,
// top-up, objective. Returns fields (0027): trailing performance from monthly
// fact sheets. Priced fields (0040): NAV per unit + as-of + distribution, for
// basis='nav' funds. All nullable, so funds without them serialise as before.
const FUND_FIELDS =
  "id,name,manager,category,fund_type,currency,basis,retail,current_rate,tax_free,min_invest,mgmt_fee,site_url,invest_url,contact_url,logo_domain,verified,featured,company_id," +
  "inception_date,benchmark_key,expense_ratio,redemption_fee,lock_in_months,top_up_min,objective," +
  "return_ytd,return_1y,return_3y,return_5y,bench_1y,bench_3y,bench_5y,best_month,worst_month,returns_as_of," +
  "price_per_unit,price_as_of,distribution_pct";

const INSURER_FIELDS =
  "id,name,company_id,currency,plans,min_premium,excess_pct,excess_min,claims_days,rating,motor_rate,benefits,logo_domain," +
  "settle_pct,licensed_since,phone,whatsapp,email,paybill,website,brand_color,classes,signals,travel_regions,travel_cover";

// Sibling composition array (migration 0017: funds.composition jsonb +
// aum_kes + aum_as_of + composition_source_url). Keyed by fund_id and kept
// OUT of the funds rows — mirrors the deltas pattern, so the app's Fund
// model and rates path stay untouched.
type SnapshotComposition = {
  fund_id: string;
  classes: Record<string, number>; // 8 CMA classes, absolute KES
  aum_kes: number | null;
  as_of: string | null;
  source_url: string | null;
};

export async function publishSnapshot(
  db: SupabaseClient,
): Promise<{ count: number; url: string }> {
  const asOf = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10); // EAT day

  // Funds (kind='fund') — the app's rate list.
  const { data: funds, error } = await db
    .from("funds")
    .select(FUND_FIELDS)
    .eq("kind", "fund")
    .neq("status", "hidden")
    .order("category", { ascending: true })
    .order("current_rate", { ascending: false, nullsFirst: false })
    // Explicit row type. postgrest-js infers the shape from the select STRING
    // at the type level, and that parser gives up on a string this long,
    // handing back GenericStringError instead of a row. Naming the type here
    // sidesteps the parser entirely and keeps every downstream access typed.
    .returns<SnapshotFund[]>();
  if (error) throw new Error(`snapshot funds query failed: ${error.message}`);

  // C2 — compact per-fund sparkline (≤20 points, trailing 180 days) attached
  // to each fund row, so app tiles stop fetching per-fund history on scroll.
  // Full-resolution history stays behind getHistory for hero/Company/Compare.
  // 180d (not 90d): while marks are sparse (Apr/Jun 2026 backfill + scrapes),
  // a 90d window can leave a single point and every sparkline hides itself.
  const cutoff = new Date(Date.now() - 180 * 86_400_000)
    .toISOString()
    .slice(0, 10);
  const { data: histRows } = await db
    .from("rate_history")
    .select("fund_id,rate,as_of")
    .gte("as_of", cutoff)
    // DESCENDING on purpose. See the note in the stock_prices query below: with
    // an ascending order the row cap silently drops the NEWEST data.
    .order("as_of", { ascending: false })
    .limit(20000);
  const histByFund = new Map<string, number[]>();
  for (const h of [...(histRows ?? [])].reverse()) {
    const arr = histByFund.get(h.fund_id) ?? [];
    arr.push(h.rate);
    histByFund.set(h.fund_id, arr);
  }
  const downsample = (xs: number[], n = 20): number[] => {
    if (xs.length <= n) return xs;
    const out: number[] = [];
    for (let i = 0; i < n; i++) {
      out.push(xs[Math.round((i * (xs.length - 1)) / (n - 1))]);
    }
    return out;
  };
  const fundsWithSpark = (funds ?? []).map((f) => {
    const h = histByFund.get(f.id);
    return h && h.length >= 2 ? { ...f, spark: downsample(h) } : f;
  });

  // Insurers (kind='insurance') — separate array, kept out of the rate list.
  const { data: insurers } = await db
    .from("funds")
    .select(INSURER_FIELDS)
    .eq("kind", "insurance")
    .neq("status", "hidden")
    .returns<SnapshotInsurer[]>();

  const { data: companies } = await db
    .from("companies")
    .select(
      "id,name,type,brand_color,logo_url,website,phone,whatsapp,email,verified,aum_kes,market_share,rank,aum_as_of,trustee,custodian,auditor",
    );

  // Agents + their company mapping.
  const { data: agentRows } = await db
    .from("agents")
    .select("id,name,role,phone,whatsapp,photo_url,is_free")
    .eq("active", true);
  const { data: joins } = await db
    .from("agent_companies")
    .select("agent_id,company_id");
  const byAgent = new Map<string, string[]>();
  for (const j of joins ?? []) {
    const arr = byAgent.get(j.agent_id) ?? [];
    arr.push(j.company_id);
    byAgent.set(j.agent_id, arr);
  }
  const agents: SnapshotAgent[] = (agentRows ?? []).map((a) => ({
    ...a,
    company_ids: byAgent.get(a.id) ?? [],
  }));

  // FX — latest row per pair.
  const { data: fxRows } = await db
    .from("fx_rates")
    .select("pair,rate,as_of")
    .order("as_of", { ascending: false });
  const fxByPair = new Map<string, SnapshotFx>();
  for (const r of fxRows ?? []) {
    if (!fxByPair.has(r.pair)) fxByPair.set(r.pair, r);
  }

  const { data: templates } = await db
    .from("insight_templates")
    .select("key,tag,template")
    .eq("active", true);

  const { data: events } = await db
    .from("market_events")
    .select("type,category,fund_id,payload,created_at")
    .order("created_at", { ascending: false })
    .limit(10);

  // Remote config (V6): admin-edited key/values ride in the snapshot.
  const { data: configRows } = await db.from("app_config").select("key,value");
  const config: Record<string, unknown> = Object.fromEntries(
    (configRows ?? []).map((r) => [r.key, r.value]),
  );

  // Composition — only funds that actually carry a breakdown.
  const { data: compRows } = await db
    .from("funds")
    .select("id,composition,aum_kes,aum_as_of,composition_source_url")
    .eq("kind", "fund")
    .neq("status", "hidden")
    .not("composition", "is", null);
  const composition: SnapshotComposition[] = (compRows ?? [])
    .filter((r) =>
      r.composition && typeof r.composition === "object" &&
      Object.values(r.composition as Record<string, unknown>).some((v) =>
        typeof v === "number" && v > 0
      )
    )
    .map((r) => ({
      fund_id: r.id,
      classes: r.composition as Record<string, number>,
      aum_kes: r.aum_kes ?? null,
      as_of: r.aum_as_of ?? null,
      source_url: r.composition_source_url ?? null,
    }));

  // Insurance types (0041) — admin-managed grid on the Insure home. Active,
  // ordered. Motor and Travel route to live flows; other keys render as
  // coming-soon cards until their pricing tables land.
  const { data: insTypes } = await db
    .from("insurance_types")
    .select("key,label,icon,status,ord,sub,lottie_url")
    .eq("active", true)
    .order("ord", { ascending: true });

  // Learn (D2) — units → lessons → steps, nested for the app. Published in the
  // snapshot so a content edit reaches devices on the next rebuild (like config).
  const { data: lUnits } = await db
    .from("learn_units")
    .select("id,ord,title,subtitle,accent,unlock_after")
    .eq("active", true)
    .order("ord", { ascending: true });
  const { data: lLessons } = await db
    .from("learn_lessons")
    .select("id,unit_id,ord,title,xp,fund_id")
    .eq("active", true)
    .order("ord", { ascending: true });
  const { data: lSteps } = await db
    .from("learn_steps")
    .select("id,lesson_id,ord,kind,payload")
    .order("ord", { ascending: true });

  const stepsByLesson = new Map<string, SnapshotLearnStep[]>();
  for (const s of lSteps ?? []) {
    const arr = stepsByLesson.get(s.lesson_id) ?? [];
    arr.push({ id: s.id, kind: s.kind, payload: s.payload });
    stepsByLesson.set(s.lesson_id, arr);
  }
  const lessonsByUnit = new Map<string, SnapshotLearnLesson[]>();
  for (const l of lLessons ?? []) {
    const arr = lessonsByUnit.get(l.unit_id) ?? [];
    arr.push({
      id: l.id,
      title: l.title,
      xp: l.xp,
      fund_id: l.fund_id ?? null,
      steps: stepsByLesson.get(l.id) ?? [],
    });
    lessonsByUnit.set(l.unit_id, arr);
  }
  const learn: SnapshotLearn = {
    units: (lUnits ?? []).map((u) => ({
      id: u.id,
      title: u.title,
      subtitle: u.subtitle ?? null,
      accent: u.accent ?? null,
      unlock_after: u.unlock_after ?? null,
      lessons: lessonsByUnit.get(u.id) ?? [],
    })),
  };

  // Posts (D3) — blog articles + curated market briefs from the unified posts
  // table (0035 + 0037). Published rows only, riding in the snapshot like learn
  // so a content edit reaches devices on the next rebuild. Bodies are
  // first-party (no copyright weight). Pinned first, newest first. The DB uses
  // 0035's names (excerpt/cover_url/published); map to the app shape here.
  const { data: postRows } = await db
    .from("posts")
    .select(
      "slug,kind,title,excerpt,body,cover_url,author,tags,fund_id,company_id,pinned,reading_minutes,published_at",
    )
    .eq("published", true)
    .order("pinned", { ascending: false })
    .order("published_at", { ascending: false, nullsFirst: false });
  const posts: SnapshotPost[] = (postRows ?? []).map((p) => ({
    slug: p.slug,
    kind: p.kind,
    title: p.title,
    summary: p.excerpt ?? null,
    body: p.body ?? null,
    hero_image_url: p.cover_url ?? null,
    author: p.author ?? null,
    tags: (p.tags as string[]) ?? [],
    fund_id: p.fund_id ?? null,
    company_id: p.company_id ?? null,
    pinned: p.pinned ?? false,
    reading_minutes: p.reading_minutes ?? null,
    published_at: p.published_at ?? null,
  }));

  // Stocks (0047) - NSE-listed equities.
  //
  // TWO CLASSES OF FIELD, and the split is the whole point:
  //
  //   facts + dividends  public company filings and announcements. Always
  //                      published, no gate.
  //   price block        NSE market data, subject to an NSE redistribution
  //                      licence. Published ONLY when app_config
  //                      `stocks.prices_enabled` is true.
  //
  // With the gate off, every price field serialises as null and the app hides
  // the price cells, so a stock page still works as a dividend + how-to-buy
  // surface while Fructa redistributes no market data. Flipping the config key
  // (after a licence is in place) lights the cells up with no app release.
  const pricesEnabled = config["stocks.prices_enabled"] === true;

  const { data: stockRows } = await db
    .from("stocks")
    .select(
      "id,ticker,name,sector,segment,about,logo_url,brand_color,website,ir_url,listed_on,shares_outstanding,eps,eps_year",
    )
    .eq("active", true)
    .order("sort_order", { ascending: true, nullsFirst: false })
    .order("name", { ascending: true });

  // Dividends, newest first. Grouped per stock; the latest financial year's
  // rows are summed (interim + final + special) into dps_latest.
  const { data: divRows } = await db
    .from("stock_dividends")
    .select("stock_id,financial_year,kind,dps_kes,declared_on,book_closure,payment_date,source_url")
    .order("financial_year", { ascending: false });

  const divsByStock = new Map<string, SnapshotStockDividend[]>();
  for (const d of divRows ?? []) {
    const arr = divsByStock.get(d.stock_id) ?? [];
    arr.push({
      financial_year: d.financial_year,
      kind: d.kind,
      dps_kes: Number(d.dps_kes),
      declared_on: d.declared_on ?? null,
      book_closure: d.book_closure ?? null,
      payment_date: d.payment_date ?? null,
      source_url: d.source_url ?? null,
    });
    divsByStock.set(d.stock_id, arr);
  }

  // Price rows only when licensed. The query itself is skipped when the gate is
  // off, so an unlicensed deployment never even reads the table.
  const priceByStock = new Map<
    string,
    { close: number; prev: number | null; asOf: string }
  >();
  const sparkByStock = new Map<string, number[]>();
  if (pricesEnabled) {
    const pxCutoff = new Date(Date.now() - 180 * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const { data: pxRows } = await db
      .from("stock_prices")
      .select("stock_id,close_kes,prev_close,as_of")
      .gte("as_of", pxCutoff)
      // DESCENDING, then reversed below.
      //
      // This was a real bug waiting to fire. The row cap is a backstop on an
      // already date-bounded window, but with `ascending: true` the database
      // returns the OLDEST 20,000 rows. The day the window outgrows the cap,
      // TODAY'S closes are the ones thrown away: the sparkline would stop short
      // of the present and the headline price would freeze at an old value,
      // with nothing logged and nothing failing. Ordering descending means the
      // cap can only ever discard the oldest points, which is harmless.
      .order("as_of", { ascending: false })
      .limit(20000);
    for (const p of [...(pxRows ?? [])].reverse()) {
      const arr = sparkByStock.get(p.stock_id) ?? [];
      arr.push(Number(p.close_kes));
      sparkByStock.set(p.stock_id, arr);
      // ascending order, so the last row seen per stock is the latest
      priceByStock.set(p.stock_id, {
        close: Number(p.close_kes),
        prev: p.prev_close == null ? null : Number(p.prev_close),
        asOf: p.as_of,
      });
    }
  }

  const stocks: SnapshotStock[] = (stockRows ?? []).map((s) => {
    const divs = divsByStock.get(s.id) ?? [];
    const dpsYear = divs.length ? divs[0].financial_year : null;
    const dpsLatest = dpsYear == null ? null : Number(
      divs
        .filter((d) => d.financial_year === dpsYear)
        .reduce((a, d) => a + d.dps_kes, 0)
        .toFixed(4),
    );

    const px = priceByStock.get(s.id) ?? null;
    const close = px?.close ?? null;
    const prev = px?.prev ?? null;
    const shares = s.shares_outstanding == null
      ? null
      : Number(s.shares_outstanding);

    // EPS is published whether or not prices are on: it is a fact about the
    // company's earnings, not a market price. P/E is not, because it needs a
    // price, and it is suppressed on a loss (eps <= 0) rather than published as
    // a negative multiple.
    const eps = s.eps == null ? null : Number(s.eps);

    return {
      id: s.id,
      ticker: s.ticker,
      name: s.name,
      sector: s.sector ?? null,
      segment: s.segment ?? null,
      about: s.about ?? null,
      logo_url: s.logo_url ?? null,
      brand_color: s.brand_color ?? null,
      website: s.website ?? null,
      ir_url: s.ir_url ?? null,
      listed_on: s.listed_on ?? null,
      shares_outstanding: shares,

      dividends: divs,
      dps_latest: dpsLatest,
      dps_year: dpsYear,

      eps,
      eps_year: s.eps_year == null ? null : Number(s.eps_year),

      // Gated block. Every one of these is null when pricesEnabled is false.
      close_kes: close,
      prev_close: prev,
      change_pct: close != null && prev != null && prev > 0
        ? Number((((close - prev) / prev) * 100).toFixed(2))
        : null,
      price_as_of: px?.asOf ?? null,
      market_cap: close != null && shares != null ? close * shares : null,
      pe: close != null && eps != null && eps > 0
        ? Number((close / eps).toFixed(2))
        : null,
      // Yield needs a price. No licence, no price, no yield: the app shows the
      // declared dividend per share on its own instead.
      div_yield: close != null && close > 0 && dpsLatest != null
        ? Number(((dpsLatest / close) * 100).toFixed(2))
        : null,
      spark: (() => {
        const h = sparkByStock.get(s.id);
        return h && h.length >= 2 ? downsample(h) : null;
      })(),
    };
  });

  // CMA-licensed brokers for the "Where to buy" section. Fructa routes out to
  // these and never executes a trade, so this is a directory, not an order path.
  const { data: brokerRows } = await db
    .from("brokers")
    .select("id,name,license_no,blurb,phone,email,website,app_url,logo_url")
    .eq("active", true)
    .order("sort_order", { ascending: true, nullsFirst: false })
    .order("name", { ascending: true });

  // SACCOs (0062) - SASRA-regulated co-operative societies.
  //
  // Gated on `saccos.enabled`, which stays false until at least one SACCO has a
  // sourced rate. With it off the query is never even run and the app sees an
  // empty array, so the tab can ship dark and light up with no release.
  //
  // TWO RATES, and keeping them apart is the whole job. See SnapshotSacco in
  // types.ts. Short version: interest_on_deposits is paid on savings and is the
  // number we rank on; dividend_on_share_capital is paid on a capped pot of
  // shares, is almost always the bigger percentage, and is almost always the
  // smaller cheque. There is no field here called "rate", on purpose, because
  // any such field would eventually get filled with whichever number was
  // biggest.
  //
  // A SACCO with no declared rate is still published. It is a real, licensed
  // institution and the directory is worth something on its own. It carries a
  // null interest_on_deposits, which keeps it OUT of every sorted list rather
  // than ranking it at zero.
  const saccosEnabled = config["saccos.enabled"] === true;

  const saccos: SnapshotSacco[] = [];
  if (saccosEnabled) {
    const { data: saccoRows } = await db
      .from("saccos")
      .select(
        "id,name,display_name,sasra_licensed_until,tier,common_bond,bond_note," +
          "county,physical_location,branches,website,phone,email,logo_url,brand_color,about," +
          "registration_fee_kes,min_share_capital_kes,min_monthly_deposit_kes," +
          "loan_multiple,deposit_notice_days,has_fosa," +
          "total_assets_kes,deposits_kes,members,registered_year,financials_as_of",
      )
      .eq("active", true)
      // Deposit-taking only. Credit-only societies (SASRA Schedule III) are
      // prohibited by law from taking new deposits, so publishing one next to a
      // savings rate would be worse than useless. They are seeded so the
      // register is complete; they must never reach a user.
      .eq("licence_class", "dt")
      .order("sort_order", { ascending: true, nullsFirst: false })
      .order("name", { ascending: true });

    // Declared rates, newest financial year first, so the first row seen per
    // SACCO is the latest one.
    const { data: rateRows } = await db
      .from("sacco_rates")
      .select(
        "sacco_id,financial_year,interest_on_deposits,dividend_on_share_capital,declared_on,source_url,source_doc",
      )
      .order("financial_year", { ascending: false });

    const num = (v: unknown): number | null => v == null ? null : Number(v);

    const ratesBySacco = new Map<string, SnapshotSaccoRate[]>();
    for (const r of rateRows ?? []) {
      const arr = ratesBySacco.get(r.sacco_id) ?? [];
      arr.push({
        financial_year: r.financial_year,
        interest_on_deposits: num(r.interest_on_deposits),
        dividend_on_share_capital: num(r.dividend_on_share_capital),
        declared_on: r.declared_on ?? null,
        source_url: r.source_url ?? null,
        source_doc: r.source_doc ?? null,
      });
      ratesBySacco.set(r.sacco_id, arr);
    }

    for (const s of saccoRows ?? []) {
      const history = ratesBySacco.get(s.id) ?? [];
      const latest = history.length ? history[0] : null;
      const bond = s.common_bond ?? "unknown";

      saccos.push({
        id: s.id,
        name: s.name,
        display_name: s.display_name ?? s.name,
        sasra_licensed_until: s.sasra_licensed_until ?? null,
        tier: num(s.tier),

        bond,
        bond_note: s.bond_note ?? null,
        // 'unknown' is NOT joinable. SASRA does not publish the common bond, so
        // most rows start unknown, and guessing open would send a user to a
        // SACCO whose membership is closed to them.
        joinable: bond === "open",

        county: s.county ?? null,
        physical_location: s.physical_location ?? null,
        branches: num(s.branches),
        website: s.website ?? null,
        phone: s.phone ?? null,
        email: s.email ?? null,

        logo_url: s.logo_url ?? null,
        brand_color: s.brand_color ?? null,
        about: s.about ?? null,

        // Always true. Deposits are not withdrawable while you remain a member.
        locked: true,

        interest_on_deposits: latest ? latest.interest_on_deposits : null,
        dividend_on_share_capital: latest
          ? latest.dividend_on_share_capital
          : null,
        rate_year: latest ? latest.financial_year : null,
        rate_declared_on: latest ? latest.declared_on : null,
        rate_source_url: latest ? latest.source_url : null,
        rate_source_doc: latest ? latest.source_doc : null,
        rate_history: history,

        registration_fee_kes: num(s.registration_fee_kes),
        min_share_capital_kes: num(s.min_share_capital_kes),
        min_monthly_deposit_kes: num(s.min_monthly_deposit_kes),
        loan_multiple: num(s.loan_multiple),
        deposit_notice_days: num(s.deposit_notice_days),
        has_fosa: s.has_fosa ?? null,

        total_assets_kes: num(s.total_assets_kes),
        deposits_kes: num(s.deposits_kes),
        members: num(s.members),
        registered_year: num(s.registered_year),
        financials_as_of: s.financials_as_of ?? null,
      });
    }
  }

  const snapshot:
    & SnapshotV2
    & {
      composition: SnapshotComposition[];
      config: Record<string, unknown>;
      learn: SnapshotLearn;
      posts: SnapshotPost[];
      insurance_types: SnapshotInsuranceType[];
      stocks: SnapshotStock[];
      brokers: SnapshotBroker[];
      saccos: SnapshotSacco[];
    } = {
    schema: 2,
    as_of: asOf,
    generated_at: new Date().toISOString(),
    funds: fundsWithSpark,
    insurers: insurers ?? [],
    companies: (companies ?? []) as SnapshotCompany[],
    agents,
    fx: [...fxByPair.values()],
    insight_templates: (templates ?? []) as SnapshotTemplate[],
    events: (events ?? []) as SnapshotEvent[],
    composition,
    config,
    learn,
    posts,
    insurance_types: (insTypes ?? []) as SnapshotInsuranceType[],
    stocks,
    brokers: (brokerRows ?? []) as SnapshotBroker[],
    saccos,
  };

  const body = new TextEncoder().encode(JSON.stringify(snapshot));
  const { error: upErr } = await db.storage.from(BUCKET).upload(FILE, body, {
    upsert: true,
    contentType: "application/json",
    // 60s, not 1h. The file changes on every scrape/admin edit, so a long
    // max-age made a fresh publish take up to an hour to reach devices even
    // though the app revalidates via ETag. 60s lets fetch-if-changed actually
    // run soon after a republish; unchanged fetches still return a cheap 304.
    cacheControl: "60",
  });
  if (upErr) throw new Error(`snapshot upload failed: ${upErr.message}`);

  const base = Deno.env.get("SUPABASE_URL");
  return {
    count: funds?.length ?? 0,
    url: `${base}/storage/v1/object/public/${BUCKET}/${FILE}`,
  };
}