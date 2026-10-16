import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import SiteShell from "../../../../site/SiteShell";
import {
  MONTHS,
  averages,
  categoryBySlug,
  categoryFunds,
  median,
  medianByMonth,
  monthExists,
  monthRange,
  nairobiToday,
  shift,
} from "@/lib/rates.server";
import { Answer, AppCta, CategoryTabs, Crumbs, Faq, JsonLd, LineChart, RatesTable, SITE, crumbsLd, faqLd } from "../../../ui";
import "../../../rates.css";

/*
 * One month's rates: "best money market fund kenya october 2026". Each fund's
 * average daily rate across the month, from the approved record. A page for
 * every month since Fructa began, so the site grows by itself. Closed months
 * never change, so they are rebuilt daily; the current one hourly.
 */
export const revalidate = 3600;

type Props = { params: Promise<{ category: string; year: string; month: string }> };

async function resolve(p: Props["params"]) {
  const { category, year, month } = await p;
  const cat = categoryBySlug(category);
  const y = Number(year);
  const m = Number(month);
  if (!cat || !/^\d{4}$/.test(year) || !/^\d{2}$/.test(month)) return null;
  if (!(await monthExists(y, m))) return null;
  return { cat, y, m };
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const r = await resolve(params);
  if (!r) return {};
  const { cat, y, m } = r;
  const { funds } = await categoryFunds(cat);
  const [a, b] = monthRange(y, m);
  const avgs = await averages(funds, a, b);
  const top = avgs[0];
  const label = `${MONTHS[m - 1]} ${y}`;
  const title = `Best ${cat.title.toLowerCase()}s in Kenya, ${label}`;
  const description = top
    ? `${top.fund.name} led ${cat.noun} in ${label}, averaging ${top.avg.toFixed(2)}%. Every fund's average rate for the month, ranked.`
    : `Every ${cat.title.toLowerCase()}'s average rate in ${label}, ranked.`;
  const path = `/rates/${cat.slug}/${y}/${String(m).padStart(2, "0")}`;
  return {
    metadataBase: new URL(SITE),
    title,
    description,
    alternates: { canonical: path },
    openGraph: { type: "article", url: `${SITE}${path}`, title, description },
  };
}

export default async function MonthPage({ params }: Props) {
  const r = await resolve(params);
  if (!r) notFound();
  const { cat, y, m } = r;
  const { funds, whtPct } = await categoryFunds(cat);
  const [a, b] = monthRange(y, m);
  const [py, pm] = shift(y, m, -1);
  const [pa, pb] = monthRange(py, pm);
  const [avgs, prev, series] = await Promise.all([
    averages(funds, a, b),
    averages(funds, pa, pb),
    medianByMonth(funds, 12),
  ]);
  const label = `${MONTHS[m - 1]} ${y}`;
  const ongoing = b >= nairobiToday();
  const med = median(avgs.map((x) => x.avg));
  const prevMed = median(prev.map((x) => x.avg));
  const top = avgs[0];
  const runners = avgs.slice(1, 3);
  const mm = String(m).padStart(2, "0");

  const crumbs: [string, string | null][] = [
    ["Fructa", "/"],
    ["Rates today", "/rates/money-market-funds"],
    [cat.title.replace(/ fund$/, " funds"), `/rates/${cat.slug}`],
    [String(y), `/rates/${cat.slug}/${y}`],
    [MONTHS[m - 1], null],
  ];

  const others = [1, 2, 3].map((k) => shift(y, m, -k));
  const next = shift(y, m, 1);
  const hasNext = !ongoing;

  const faqs = top
    ? [
        {
          q: `Which ${cat.title.toLowerCase()} paid the most in ${label}?`,
          a: `${top.fund.name}, averaging ${top.avg.toFixed(2)}% gross across the month${runners.length ? `, ahead of ${runners.map((x) => `${x.fund.name} (${x.avg.toFixed(2)}%)`).join(" and ")}` : ""}.`,
        },
        ...(med != null && prevMed != null
          ? [
              {
                q: `Did rates rise or fall in ${label}?`,
                a: `The median ${cat.title.toLowerCase()} averaged ${med.toFixed(2)}%, ${med >= prevMed ? "up" : "down"} ${Math.abs(med - prevMed).toFixed(2)} points from ${MONTHS[pm - 1]}.`,
              },
            ]
          : []),
        {
          q: "How is the monthly average worked out?",
          a: "Every day of the month counts, using the rate each fund had published on that day. Weekends carry Friday's rate.",
        },
      ]
    : [];

  return (
    <SiteShell wide>
      <JsonLd data={[crumbsLd(crumbs), faqLd(faqs)]} />
      <Crumbs items={crumbs} />
      <h1 className="ra-h1">
        Best {cat.title.toLowerCase()}s in Kenya, {label}
      </h1>
      <p className="ra-dateline">
        Average rate each fund paid{ongoing ? " so far this month" : ""} · {avgs.length} {cat.noun}
      </p>

      {top ? (
        <Answer
          eyebrow={`${label} · average`}
          big={`${top.avg.toFixed(2)}%`}
          sub={`${top.fund.name} led the month${runners.length ? `, ahead of ${runners.map((x) => `${x.fund.name.replace(/ Money Market Fund.*$/, "")} (${x.avg.toFixed(2)}%)`).join(" and ")}` : ""}`}
          chips={[
            ...(med != null ? [{ k: "Median", v: `${med.toFixed(2)}%` }] : []),
            ...(med != null && prevMed != null
              ? [
                  {
                    k: `vs ${MONTHS[pm - 1]}`,
                    v: `${med - prevMed >= 0 ? "+" : "-"}${Math.abs(med - prevMed).toFixed(2)} pts`,
                    tone: (med - prevMed >= 0 ? "up" : "down") as "up" | "down",
                  },
                ]
              : []),
          ]}
        />
      ) : (
        <p className="ra-note">No rates were published for this month.</p>
      )}

      <CategoryTabs current={cat} pathFor={(c) => `/rates/${c.slug}/${y}/${mm}`} />

      {series.some((p) => p.median != null) ? (
        <section className="ra-card" style={{ marginBottom: 24 }}>
          <h2>The median rate, month by month</h2>
          <LineChart
            values={series.map((p) => p.median)}
            labels={series.filter((_, i) => i % 2 === 0 || i === series.length - 1).map((p) => `${MONTHS[p.month - 1].slice(0, 3)} ${String(p.year).slice(2)}`)}
          />
        </section>
      ) : null}

      <RatesTable
        wht={whtPct}
        grossLabel="Average"
        moveLabel={`vs ${MONTHS[pm - 1].slice(0, 3)}`}
        rows={avgs.map((x) => {
          const before = prev.find((p) => p.fund.id === x.fund.id);
          return {
            fund: x.fund,
            gross: x.avg,
            net: x.fund.taxFree ? x.avg : x.avg * (1 - whtPct / 100),
            move: before ? x.avg - before.avg : null,
          };
        })}
      />

      <div className="ra-grid">
        {faqs.length ? <Faq title="Questions people ask" items={faqs} /> : <div />}
        <section className="ra-card">
          <h2>Other months</h2>
          <div className="ra-months">
            {hasNext ? (
              <Link className="ra-month" href={`/rates/${cat.slug}/${next[0]}/${String(next[1]).padStart(2, "0")}`}>
                {MONTHS[next[1] - 1]} {next[0]}
              </Link>
            ) : null}
            {others.map(([yy, m2]) => (
              <Link key={`${yy}-${m2}`} className="ra-month" href={`/rates/${cat.slug}/${yy}/${String(m2).padStart(2, "0")}`}>
                {MONTHS[m2 - 1]} {yy}
              </Link>
            ))}
            <Link className="ra-month" href={`/rates/${cat.slug}/${y}`}>
              All of {y}
            </Link>
          </div>
        </section>
      </div>

      <AppCta
        title="See every rate as it moves"
        body="Fructa tracks every Kenyan fund daily, with what you keep after tax and alerts when a rate you follow changes."
      />
    </SiteShell>
  );
}
