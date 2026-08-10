import type { Metadata } from "next";
import Link from "next/link";
import SiteShell from "../site/SiteShell";
import { INFLATION } from "../landing/content";
import {
  FUND_TYPE_LABEL,
  fmtDay,
  getFunds,
  netRate,
  realRate,
} from "@/lib/funds.server";
import "./funds.css";

/*
 * The hub.
 *
 * Two jobs, and the second is the one that matters. It ranks for the generic
 * head terms ("money market fund rates Kenya"), and it links to every fund
 * page, which is how Googlebot finds 144 URLs it would otherwise never reach.
 * A sitemap invites a crawl; internal links are what actually earn one.
 */

const SITE = "https://fructa.africa";
export const revalidate = 3600;

export async function generateMetadata(): Promise<Metadata> {
  const { funds, whtPct } = await getFunds();
  const top = funds.find((f) => f.grossRate != null);
  const title = top
    ? `Money Market Fund Rates Kenya: ${top.grossRate!.toFixed(2)}% Top Rate Today`
    : "Money Market Fund Rates in Kenya";
  const description = top
    ? `Live rates for ${funds.length} Kenyan funds. ${top.name} leads at ${top.grossRate!.toFixed(2)}% gross, ${netRate(top, whtPct)!.toFixed(2)}% after ${whtPct}% withholding tax. Compare gross, net and real returns.`
    : `Compare live rates across ${funds.length} Kenyan collective investment schemes.`;

  return {
    metadataBase: new URL(SITE),
    title,
    description,
    alternates: { canonical: "/funds" },
    openGraph: {
      type: "website",
      url: `${SITE}/funds`,
      title,
      description,
      images: [`${SITE}/og.png`],
    },
  };
}

export default async function FundsIndex() {
  const { funds, whtPct, asOf } = await getFunds();
  const rated = funds.filter((f) => f.grossRate != null);

  // Grouped by type so the page reads as a directory rather than one long list,
  // and so each group heading carries a phrase somebody actually searches.
  const groups = new Map<string, typeof funds>();
  for (const f of rated) {
    const k = f.fundType ?? "other";
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(f);
  }
  const order = ["mmf", "fixed_income", "balanced", "equity", "special", "other"];
  const sorted = [...groups.entries()].sort(
    (a, b) => order.indexOf(a[0]) - order.indexOf(b[0]),
  );

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "ItemList",
    name: "Kenyan investment fund rates",
    numberOfItems: rated.length,
    itemListElement: rated.slice(0, 50).map((f, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: f.name,
      url: `${SITE}/funds/${f.slug}`,
    })),
  };

  return (
    <SiteShell>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <header className="fu-head">
        <p className="fu-eyebrow">Live rates</p>
        <h1 className="fu-h1">Money market fund rates in Kenya</h1>
        <p className="fu-lede">
          Every rate below is the latest figure Fructa recorded, not an annual
          average and not a marketing number. Each fund shows gross, what is left
          after {whtPct}% withholding tax, and what is left after{" "}
          {INFLATION.toFixed(1)}% inflation, because those three are rarely the
          same story.
        </p>
        {asOf ? <p className="fu-asof">Rates as of {fmtDay(asOf)}</p> : null}
      </header>

      {sorted.map(([type, list]) => (
        <section className="fu-block" key={type}>
          <h2>
            {FUND_TYPE_LABEL[type] ?? "Other funds"}
            <span className="fu-count">{list.length}</span>
          </h2>
          <table className="fu-table fu-table-index">
            <thead>
              <tr>
                <th scope="col">Fund</th>
                <th scope="col">Gross</th>
                <th scope="col">Net</th>
                <th scope="col">Real</th>
              </tr>
            </thead>
            <tbody>
              {list.map((f) => {
                const n = netRate(f, whtPct);
                const r = realRate(f, whtPct, INFLATION);
                return (
                  <tr key={f.id}>
                    <td>
                      <Link href={`/funds/${f.slug}`}>{f.name}</Link>
                      <span className="fu-cur">{f.currency}</span>
                    </td>
                    <td className="fu-num fu-gold">
                      {f.grossRate!.toFixed(2)}%
                    </td>
                    <td className="fu-num">{n?.toFixed(2)}%</td>
                    <td className={`fu-num ${(r ?? 0) < 0 ? "fu-neg" : ""}`}>
                      {r?.toFixed(2)}%
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </section>
      ))}

      {rated.length === 0 ? (
        <p className="fu-note">
          Rates are temporarily unavailable. They are refreshed every weekday at
          noon EAT.
        </p>
      ) : null}

      <section className="fu-cta">
        <h2>All of it, on your phone</h2>
        <p>
          Fructa puts these rates next to T-bills, government bonds, SACCO
          dividends and NSE prices, and lets you set an alert on any of them. No
          account, and your holdings never leave your device.
        </p>
        <Link className="fl-btn fl-btn-gold" href="/get">
          Get the app
        </Link>
      </section>

      <p className="fu-disclaimer">
        Collected from fund managers, published factsheets, the CBK and the CMA.
        Shown for information only, not investment advice. Confirm any figure
        with the fund manager before you invest.
      </p>
    </SiteShell>
  );
}
