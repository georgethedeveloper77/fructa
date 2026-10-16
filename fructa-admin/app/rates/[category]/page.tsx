import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import SiteShell from "../../site/SiteShell";
import FundLogo from "../../funds/FundLogo";
import { netRate } from "@/lib/funds.server";
import {
  CATEGORIES,
  MONTHS,
  billRate,
  categoryBySlug,
  categoryFunds,
  longDay,
  median,
  nairobiToday,
  shift,
  weekMoves,
} from "@/lib/rates.server";
import { Answer, AppCta, CategoryTabs, Crumbs, Faq, JsonLd, RatesTable, SITE, crumbsLd, faqLd } from "../ui";
import "../rates.css";

/*
 * Today's rates for one category. The page for "money market fund rates kenya
 * today": the H1 is that phrase, the date is in it, the answer comes first and
 * every number is in the HTML. Rebuilt hourly; rates move once a day.
 */
export const revalidate = 3600;

export function generateStaticParams() {
  return CATEGORIES.map((c) => ({ category: c.slug }));
}

type Props = { params: Promise<{ category: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { category } = await params;
  const cat = categoryBySlug(category);
  if (!cat) return {};
  const { funds, whtPct } = await categoryFunds(cat);
  const top = funds[0];
  const day = longDay(nairobiToday()).replace(/^\w+ /, "");
  const title = top
    ? `${cat.title} rates in Kenya today, ${day}: ${top.grossRate!.toFixed(2)}% top rate`
    : `${cat.title} rates in Kenya today`;
  const description = top
    ? `Today's rates for ${funds.length} ${cat.noun}. ${top.name} leads at ${top.grossRate!.toFixed(2)}% gross, ${netRate(top, whtPct)!.toFixed(2)}% after ${whtPct}% withholding tax. Updated every weekday.`
    : `Today's rates for ${cat.noun}, updated every weekday.`;
  return {
    metadataBase: new URL(SITE),
    title,
    description,
    alternates: { canonical: `/rates/${cat.slug}` },
    openGraph: { type: "website", url: `${SITE}/rates/${cat.slug}`, title, description },
  };
}

export default async function RatesToday({ params }: Props) {
  const { category } = await params;
  const cat = categoryBySlug(category);
  if (!cat) notFound();

  const { funds, whtPct } = await categoryFunds(cat);
  const [moves, bill] = await Promise.all([weekMoves(funds), billRate()]);
  const today = nairobiToday();
  const [y, m] = today.split("-").map(Number);
  const top = funds[0];
  const med = median(funds.map((f) => f.grossRate!));
  const moved = [...moves.values()].filter((v) => Math.abs(v) >= 0.05).length;
  const beat = bill == null ? null : funds.filter((f) => f.grossRate! > bill).length;
  const movers = funds
    .filter((f) => moves.has(f.id) && Math.abs(moves.get(f.id)!) >= 0.05)
    .sort((a, b) => Math.abs(moves.get(b.id)!) - Math.abs(moves.get(a.id)!))
    .slice(0, 5);

  const crumbs: [string, string | null][] = [
    ["Fructa", "/"],
    ["Rates today", "/rates/money-market-funds"],
    [cat.title.replace(/ fund$/, " funds"), null],
  ];
  const pastMonths = [1, 2].map((k) => shift(y, m, -k));

  const faqs = top
    ? [
        {
          q: `Which ${cat.title.toLowerCase()} pays the most in Kenya today?`,
          a: `${top.name}, at ${top.grossRate!.toFixed(2)}% gross on ${longDay(today)}. After ${whtPct}% withholding tax that is ${netRate(top, whtPct)!.toFixed(2)}%.`,
        },
        {
          q: "What is the difference between gross and net?",
          a: `Gross is the rate the fund publishes. Net is what you keep after the ${whtPct}% withholding tax on interest.`,
        },
        ...(bill != null
          ? [
              {
                q: `Do ${cat.noun} pay more than the 91-day T-bill?`,
                a: `Today ${beat} of ${funds.length} do. The 91-day T-bill is at ${bill.toFixed(2)}%.`,
              },
            ]
          : []),
        {
          q: "How often do these rates change?",
          a: "Most managers publish a new rate every working day. Fructa reads them every weekday at noon, Nairobi time.",
        },
      ]
    : [];

  return (
    <SiteShell wide>
      <JsonLd data={[crumbsLd(crumbs), faqLd(faqs)]} />
      <Crumbs items={crumbs} />
      <h1 className="ra-h1">{cat.title} rates in Kenya today</h1>
      <p className="ra-dateline">
        {longDay(today)} · {funds.length} {cat.noun} · from each manager&rsquo;s published rate
      </p>

      {top ? (
        <Answer
          eyebrow="Best rate today"
          big={`${top.grossRate!.toFixed(2)}%`}
          sub={`${top.name} · ${netRate(top, whtPct)!.toFixed(2)}% after ${whtPct}% withholding tax`}
          chips={[
            ...(med != null ? [{ k: "Median", v: `${med.toFixed(2)}%` }] : []),
            ...(bill != null ? [{ k: "91-day T-bill", v: `${bill.toFixed(2)}%`, tone: "gold" as const }] : []),
            { k: "Moved this week", v: `${moved} of ${funds.length}` },
          ]}
        />
      ) : (
        <p className="ra-note">Rates are not available right now. Please check back shortly.</p>
      )}

      <CategoryTabs
        current={cat}
        pathFor={(c) => `/rates/${c.slug}`}
        more={
          <>
            Past months:{" "}
            {pastMonths.map(([yy, mm], i) => (
              <span key={`${yy}-${mm}`}>
                {i > 0 ? " · " : ""}
                <Link href={`/rates/${cat.slug}/${yy}/${String(mm).padStart(2, "0")}`}>
                  {MONTHS[mm - 1]} {yy}
                </Link>
              </span>
            ))}
            {" · "}
            <Link href={`/rates/${cat.slug}/${y}`}>{y}</Link>
          </>
        }
      />

      <RatesTable
        wht={whtPct}
        rows={funds.map((f) => ({
          fund: f,
          gross: f.grossRate!,
          net: netRate(f, whtPct)!,
          move: moves.get(f.id) ?? null,
        }))}
      />

      <div className="ra-grid">
        {faqs.length ? <Faq title="Questions people ask" items={faqs} /> : <div />}
        {movers.length ? (
          <section className="ra-card">
            <h2>Moved this week</h2>
            {movers.map((f) => {
              const v = moves.get(f.id)!;
              return (
                <Link className="ra-list-row" key={f.id} href={`/funds/${f.slug}`}>
                  <FundLogo fund={f} size={28} />
                  <span className="grow">{f.name}</span>
                  <span className={"ra-num " + (v > 0 ? "ra-up" : "ra-down")}>
                    {v > 0 ? "+" : "-"}
                    {Math.abs(v).toFixed(2)}
                  </span>
                </Link>
              );
            })}
            <p className="ra-note" style={{ marginTop: 10 }}>Points, last 7 days</p>
          </section>
        ) : null}
      </div>

      <AppCta
        title="Know the morning a rate moves"
        body={`Follow any of these ${funds.length} funds in Fructa and get told when its rate changes, with what you keep after tax.`}
      />
      <p className="ra-note">
        Rates are collected from fund managers, the CBK and the CMA and shown for information only. They are not investment advice.
      </p>
    </SiteShell>
  );
}
