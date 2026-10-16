import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import SiteShell from "../../../site/SiteShell";
import {
  MONTHS,
  averages,
  categoryBySlug,
  categoryFunds,
  firstMonth,
  monthExists,
  nairobiToday,
} from "@/lib/rates.server";
import { Answer, AppCta, CategoryTabs, Crumbs, Faq, JsonLd, RatesTable, SITE, crumbsLd, faqLd } from "../../ui";
import "../../rates.css";

/*
 * A year's rates: "best money market fund in kenya 2026". Each fund's average
 * over the year so far, and a link to every month. Rebuilt daily.
 */
export const revalidate = 86400;

type Props = { params: Promise<{ category: string; year: string }> };

async function resolve(p: Props["params"]) {
  const { category, year } = await p;
  const cat = categoryBySlug(category);
  const y = Number(year);
  if (!cat || !/^\d{4}$/.test(year)) return null;
  const first = await firstMonth();
  const ty = Number(nairobiToday().slice(0, 4));
  if (!first || y < first[0] || y > ty) return null;
  return { cat, y };
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const r = await resolve(params);
  if (!r) return {};
  const { cat, y } = r;
  const title = `Best ${cat.title.toLowerCase()}s in Kenya, ${y}`;
  const description = `Every ${cat.title.toLowerCase()}'s average rate in ${y}, ranked, with a page for each month.`;
  return {
    metadataBase: new URL(SITE),
    title,
    description,
    alternates: { canonical: `/rates/${cat.slug}/${y}` },
    openGraph: { type: "article", url: `${SITE}/rates/${cat.slug}/${y}`, title, description },
  };
}

export default async function YearPage({ params }: Props) {
  const r = await resolve(params);
  if (!r) notFound();
  const { cat, y } = r;
  const { funds, whtPct } = await categoryFunds(cat);
  const avgs = await averages(funds, `${y}-01-01`, `${y}-12-31`);
  const top = avgs[0];
  const ongoing = y === Number(nairobiToday().slice(0, 4));
  const months: number[] = [];
  for (let m = 1; m <= 12; m++) if (await monthExists(y, m)) months.push(m);

  const crumbs: [string, string | null][] = [
    ["Fructa", "/"],
    ["Rates today", "/rates/money-market-funds"],
    [cat.title.replace(/ fund$/, " funds"), `/rates/${cat.slug}`],
    [String(y), null],
  ];
  const faqs = top
    ? [
        {
          q: `Which ${cat.title.toLowerCase()} paid the most in ${y}?`,
          a: `${top.fund.name}, averaging ${top.avg.toFixed(2)}% gross ${ongoing ? "so far this year" : "across the year"}.`,
        },
      ]
    : [];

  return (
    <SiteShell wide>
      <JsonLd data={[crumbsLd(crumbs), faqLd(faqs)]} />
      <Crumbs items={crumbs} />
      <h1 className="ra-h1">
        Best {cat.title.toLowerCase()}s in Kenya, {y}
      </h1>
      <p className="ra-dateline">
        Average rate each fund paid{ongoing ? " so far this year" : ""} · {avgs.length} {cat.noun}
      </p>
      {top ? (
        <Answer
          eyebrow={`${y} · average`}
          big={`${top.avg.toFixed(2)}%`}
          sub={`${top.fund.name} leads ${y}`}
          chips={[{ k: "Months", v: String(months.length) }]}
        />
      ) : null}
      <CategoryTabs current={cat} pathFor={(c) => `/rates/${c.slug}/${y}`} />
      <section className="ra-card" style={{ marginBottom: 24 }}>
        <h2>Month by month</h2>
        <div className="ra-months">
          {months.map((m) => (
            <Link key={m} className="ra-month" href={`/rates/${cat.slug}/${y}/${String(m).padStart(2, "0")}`}>
              {MONTHS[m - 1]}
            </Link>
          ))}
        </div>
      </section>
      <RatesTable
        wht={whtPct}
        grossLabel="Average"
        rows={avgs.map((x) => ({
          fund: x.fund,
          gross: x.avg,
          net: x.fund.taxFree ? x.avg : x.avg * (1 - whtPct / 100),
        }))}
      />
      {faqs.length ? (
        <div className="ra-grid">
          <Faq title="Questions people ask" items={faqs} />
          <div />
        </div>
      ) : null}
      <AppCta
        title="See every rate as it moves"
        body="Fructa tracks every Kenyan fund daily, with what you keep after tax."
      />
    </SiteShell>
  );
}
