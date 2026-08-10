import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import SiteShell from "../../site/SiteShell";
import FundLogo from "../FundLogo";
import { INFLATION } from "../../landing/content";
import {
  FUND_TYPE_LABEL,
  fmtDay,
  getFundBySlug,
  getFundHistory,
  getFunds,
  money,
  netRate,
  pct,
  peersOf,
  realRate,
} from "@/lib/funds.server";
import "../funds.css";

/*
 * One page per fund.
 *
 * The query these target is not "best money market fund", it is "cic money
 * market fund rate": a named product, high intent, and currently answered on
 * page one by blog posts quoting rates from two years ago. We publish the live
 * figure, so this is a page we can win on merit rather than on backlinks.
 *
 * Rendered on the server with the numbers already in the HTML. Google indexes
 * the response, not what a client fetch paints afterwards, and a rate that only
 * appears post-hydration is a rate that does not exist as far as ranking goes.
 */

const SITE = "https://fructa.africa";

// Hourly ISR rather than force-dynamic. Rates move once a day at noon EAT, so
// per-request rendering would buy nothing and cost crawl budget: Google's
// ranking systems weigh response time, and 144 pages each doing three round
// trips to Supabase on every crawler hit is a slow site by construction.
export const revalidate = 3600;

export async function generateStaticParams() {
  const { funds } = await getFunds();
  return funds.map((f) => ({ slug: f.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const found = await getFundBySlug(slug);
  if (!found) return { title: "Fund not found, Fructa" };

  const { fund, bundle } = found;
  const gross = pct(fund.grossRate);
  const net = pct(netRate(fund, bundle.whtPct));

  // The title carries the exact phrase people type. "Rate Today" rather than a
  // brand-first title, because the brand is not what is being searched for.
  const title = gross
    ? `${fund.name} Rate Today: ${gross} (${net} net)`
    : `${fund.name} Rate and Details`;

  const description = gross
    ? `${fund.name} is paying ${gross} gross, which is ${net} after ${bundle.whtPct}% withholding tax. Minimum investment, fees and 12 month rate history, updated daily.`
    : `Live rate, minimum investment, fees and rate history for ${fund.name}, tracked daily by Fructa.`;

  return {
    metadataBase: new URL(SITE),
    title,
    description,
    alternates: { canonical: `/funds/${fund.slug}` },
    openGraph: {
      type: "website",
      url: `${SITE}/funds/${fund.slug}`,
      title,
      description,
      images: [`${SITE}/og.png`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [`${SITE}/og.png`],
    },
  };
}

export default async function FundPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const found = await getFundBySlug(slug);
  if (!found) notFound();

  const { fund, bundle } = found;
  const wht = bundle.whtPct;
  const [history] = await Promise.all([getFundHistory(fund.id)]);
  const peers = peersOf(fund, bundle.funds);

  const gross = fund.grossRate;
  const net = netRate(fund, wht);
  const real = realRate(fund, wht, INFLATION);
  const typeLabel = FUND_TYPE_LABEL[fund.fundType ?? ""] ?? "Fund";
  const rank = bundle.funds.findIndex((f) => f.id === fund.id) + 1;

  // Loss to tax on a round balance, because a percentage point is abstract and
  // a shilling figure is not.
  const taxCost =
    gross != null && net != null && !fund.taxFree
      ? Math.round(((gross - net) / 100) * 100000)
      : null;

  const faqs = buildFaqs({
    name: fund.name,
    currency: fund.currency,
    gross,
    net,
    wht,
    taxFree: fund.taxFree,
    minInvest: fund.minInvest,
    manager: fund.manager,
  });

  const jsonLd = [
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        { "@type": "ListItem", position: 1, name: "Home", item: SITE },
        { "@type": "ListItem", position: 2, name: "Funds", item: `${SITE}/funds` },
        {
          "@type": "ListItem",
          position: 3,
          name: fund.name,
          item: `${SITE}/funds/${fund.slug}`,
        },
      ],
    },
    {
      "@context": "https://schema.org",
      "@type": "InvestmentFund",
      name: fund.name,
      url: `${SITE}/funds/${fund.slug}`,
      provider: fund.manager
        ? { "@type": "Organization", name: fund.manager }
        : undefined,
      category: typeLabel,
      feesAndCommissionsSpecification:
        fund.mgmtFee != null ? `${fund.mgmtFee}% management fee` : undefined,
      interestRate: gross ?? undefined,
      currenciesAccepted: fund.currency,
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: faqs.map((f) => ({
        "@type": "Question",
        name: f.q,
        acceptedAnswer: { "@type": "Answer", text: f.a },
      })),
    },
  ];

  return (
    <SiteShell>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <nav className="fu-crumb">
        <Link href="/funds">All funds</Link>
        <span aria-hidden="true">/</span>
        <span>{fund.name}</span>
      </nav>

      <header className="fu-head">
        <div className="fu-ident">
          <FundLogo fund={fund} size={52} />
          <p className="fu-eyebrow">
            {typeLabel} &middot; {fund.currency}
            {fund.manager ? ` · ${fund.manager}` : ""}
          </p>
        </div>
        <h1 className="fu-h1">{fund.name} rate today</h1>

        {gross != null ? (
          <>
            <p className="fu-big">
              {gross.toFixed(2)}
              <span className="fu-pct">%</span>
            </p>
            <p className="fu-sub">
              {fund.taxFree ? (
                <>Tax free, so {gross.toFixed(2)}% is what you keep.</>
              ) : (
                <>
                  You keep <strong>{net!.toFixed(2)}%</strong> after {wht}%
                  withholding tax
                  {real != null ? (
                    <>
                      , and <strong>{real.toFixed(2)}%</strong> after{" "}
                      {INFLATION.toFixed(1)}% inflation
                    </>
                  ) : null}
                  .
                </>
              )}
            </p>
          </>
        ) : (
          <p className="fu-sub">
            This fund does not publish a running yield. It is priced per unit,
            so its return comes from the change in unit price rather than a
            quoted rate.
          </p>
        )}

        {bundle.asOf ? (
          <p className="fu-asof">Rates as of {fmtDay(bundle.asOf)}</p>
        ) : null}
      </header>

      <section className="fu-facts" aria-label="Key facts">
        <Fact label="Gross yield" value={pct(gross)} />
        <Fact
          label={fund.taxFree ? "Net (tax free)" : `Net after ${wht}% WHT`}
          value={pct(net)}
        />
        <Fact
          label={`Real, after ${INFLATION.toFixed(1)}% inflation`}
          value={pct(real)}
        />
        <Fact
          label="Minimum investment"
          value={money(fund.currency, fund.minInvest)}
        />
        <Fact label="Management fee" value={pct(fund.mgmtFee)} />
        <Fact
          label="Rank by yield"
          value={rank > 0 && gross != null ? `#${rank} of ${bundle.funds.length}` : null}
        />
      </section>

      {taxCost != null ? (
        <p className="fu-cost">
          On a {fund.currency} 100,000 balance that is roughly{" "}
          <strong>
            {fund.currency} {taxCost.toLocaleString("en-KE")}
          </strong>{" "}
          a year going to withholding tax, which is the part the advertised rate
          does not mention.
        </p>
      ) : null}

      {history.length > 1 ? (
        <section className="fu-block">
          <h2>{fund.name} rate history</h2>
          <p className="fu-note">
            Last quoted rate in each month, from Fructa&rsquo;s daily record.
          </p>
          <table className="fu-table">
            <thead>
              <tr>
                <th scope="col">Month</th>
                <th scope="col">Gross</th>
                <th scope="col">Net after {wht}% WHT</th>
              </tr>
            </thead>
            <tbody>
              {[...history].reverse().map((h) => (
                <tr key={h.asOf}>
                  <td>{fmtDay(h.asOf)}</td>
                  <td className="fu-num">{h.rate.toFixed(2)}%</td>
                  <td className="fu-num fu-mute">
                    {(fund.taxFree ? h.rate : h.rate * (1 - wht / 100)).toFixed(2)}%
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      ) : null}

      <section className="fu-block">
        <h2>Questions people ask about {fund.name}</h2>
        <dl className="fu-faq">
          {faqs.map((f) => (
            <div key={f.q}>
              <dt>{f.q}</dt>
              <dd>{f.a}</dd>
            </div>
          ))}
        </dl>
      </section>

      {peers.length > 0 ? (
        <section className="fu-block">
          <h2>
            Other {typeLabel.toLowerCase()}s in {fund.currency}
          </h2>
          <ul className="fu-peers">
            {peers.map((p) => (
              <li key={p.id}>
                <Link href={`/funds/${p.slug}`}>
                  <FundLogo fund={p} size={30} />
                  <span className="fu-peer-name">{p.name}</span>
                  <span className="fu-peer-rate">
                    {p.grossRate?.toFixed(2)}%
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section className="fu-cta">
        <h2>Track this fund in the app</h2>
        <p>
          Fructa tracks {bundle.funds.length} funds across money market, fixed
          income, T-bills, SACCOs and the NSE, with gross, net and real on every
          one. Set an alert and you will know the morning{" "}
          {fund.name} moves. No account needed.
        </p>
        <Link className="fl-btn fl-btn-gold" href="/get">
          Get the app
        </Link>
      </section>

      <p className="fu-disclaimer">
        Rates are collected from fund managers, published factsheets, the CBK and
        the CMA, and are shown for information only. They are not investment
        advice, and a yield quoted today is not a promise about tomorrow. Confirm
        any figure with the fund manager before you invest.
      </p>
    </SiteShell>
  );
}

function Fact({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <div className="fu-fact">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

/**
 * The long tail, answered in prose.
 *
 * One page cannot rank for one phrase alone. "cic money market fund rate", "how
 * much is cic mmf", "cic money market fund minimum" and "is cic money market
 * fund taxed" are four searches with one answer each, and answering them in
 * plain sentences is what lets a single page serve all four.
 *
 * FAQPage markup is included for structure. Google restricted FAQ rich results
 * to government and health sites in 2023, so do not expect the dropdown in the
 * SERP: the value here is the text itself, not the schema.
 */
function buildFaqs(o: {
  name: string;
  currency: string;
  gross: number | null;
  net: number | null;
  wht: number;
  taxFree: boolean;
  minInvest: number | null;
  manager: string | null;
}) {
  const out: { q: string; a: string }[] = [];

  if (o.gross != null) {
    out.push({
      q: `What is the current ${o.name} rate?`,
      a: `${o.name} is quoting ${o.gross.toFixed(2)}% gross. Fructa records the rate every weekday, so this figure is the most recent one published rather than an annual average.`,
    });
  }

  if (o.gross != null && o.net != null) {
    out.push({
      q: o.taxFree
        ? `Is ${o.name} taxed?`
        : `How much do you actually keep from ${o.name}?`,
      a: o.taxFree
        ? `${o.name} is a tax exempt fund, so the quoted ${o.gross.toFixed(2)}% is what you keep. Most Kenyan money market funds are not, and lose ${o.wht}% of the interest to withholding tax.`
        : `Kenyan money market fund interest carries ${o.wht}% withholding tax, deducted at source. The advertised ${o.gross.toFixed(2)}% is therefore ${o.net.toFixed(2)}% in practice. On ${o.currency} 100,000 that difference is about ${o.currency} ${Math.round(((o.gross - o.net) / 100) * 100000).toLocaleString("en-KE")} a year.`,
    });
  }

  if (o.minInvest != null && o.minInvest > 0) {
    out.push({
      q: `What is the minimum investment for ${o.name}?`,
      a: `${o.name} requires a minimum of ${o.currency} ${Math.round(o.minInvest).toLocaleString("en-KE")} to open. Minimums vary widely between Kenyan funds, from a hundred shillings to six figures, and a higher minimum does not reliably buy a higher yield.`,
    });
  }

  if (o.manager) {
    out.push({
      q: `Who manages ${o.name}?`,
      a: `${o.name} is managed by ${o.manager}, a fund manager licensed by the Capital Markets Authority. Fructa tracks every CMA licensed collective investment scheme that publishes a rate.`,
    });
  }

  out.push({
    q: `Is ${o.name} a good place to keep money?`,
    a: `That depends on what you are comparing it against and what you need the money for. The yield matters, but so do the minimum, the fee, how quickly you can withdraw, and whether the return beats inflation once tax is taken. Fructa shows gross, net and real side by side for every fund so the comparison is like for like.`,
  });

  return out;
}
