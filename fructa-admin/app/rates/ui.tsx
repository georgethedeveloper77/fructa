import Link from "next/link";
import FundLogo from "../funds/FundLogo";
import type { PublicFund } from "@/lib/funds.server";
import { CATEGORIES, type Category } from "@/lib/rates.server";

export const SITE = "https://fructa.africa";

export function Crumbs({ items }: { items: [string, string | null][] }) {
  return (
    <nav className="ra-crumb" aria-label="Breadcrumb">
      {items.map(([label, href], i) => (
        <span key={label}>
          {i > 0 ? <span aria-hidden="true">› </span> : null}
          {href ? <Link href={href}>{label}</Link> : <span>{label}</span>}
        </span>
      ))}
    </nav>
  );
}

export function crumbsLd(items: [string, string | null][]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map(([name, href], i) => ({
      "@type": "ListItem",
      position: i + 1,
      name,
      item: href ? `${SITE}${href}` : undefined,
    })),
  };
}

export type Chip = { k: string; v: string; tone?: "up" | "down" | "gold" };

/** The answer, before anything else: the figure the search asked for. */
export function Answer({
  eyebrow,
  big,
  sub,
  chips,
}: {
  eyebrow: string;
  big: string;
  sub: string;
  chips: Chip[];
}) {
  return (
    <section className="ra-answer" aria-label={eyebrow}>
      <div className="ra-answer-main">
        <div className="ra-eyebrow">{eyebrow}</div>
        <div className="ra-big">{big}</div>
        <div className="ra-answer-sub">{sub}</div>
      </div>
      <div className="ra-chips">
        {chips.map((c) => (
          <div className="ra-chip" key={c.k}>
            <span className="ra-chip-k">{c.k}</span>
            <span className={"ra-chip-v" + (c.tone ? ` ra-${c.tone}` : "")}>{c.v}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

/** Category tabs; [pathFor] builds each tab's link. */
export function CategoryTabs({
  current,
  pathFor,
  more,
}: {
  current: Category;
  pathFor: (c: Category) => string;
  more?: React.ReactNode;
}) {
  return (
    <div className="ra-tabs">
      {CATEGORIES.map((c) => (
        <Link
          key={c.slug}
          className="ra-tab"
          href={pathFor(c)}
          aria-current={c.slug === current.slug ? "page" : undefined}
        >
          {c.noun.replace(/^KES /, "").replace(/^\w/, (x) => x.toUpperCase())}
        </Link>
      ))}
      {more ? <span className="ra-tabs-more">{more}</span> : null}
    </div>
  );
}

export type Row = { fund: PublicFund; gross: number; net: number; move?: number | null };

const signed = (v: number) => `${v > 0 ? "+" : v < 0 ? "-" : ""}${Math.abs(v).toFixed(2)}`;

/** The ranked table. Every fund name links to its page. */
export function RatesTable({
  rows,
  wht,
  grossLabel = "Gross",
  moveLabel = "7 days",
}: {
  rows: Row[];
  wht: number;
  grossLabel?: string;
  moveLabel?: string;
}) {
  const hasMove = rows.some((r) => r.move != null);
  return (
    <div className="ra-table" role="table">
      <div className="ra-row ra-head" role="row">
        <span>#</span>
        <span>Fund</span>
        <span className="ra-num">{grossLabel}</span>
        <span className="ra-num ra-net">Net ({wht}% WHT)</span>
        <span className="ra-num">{hasMove ? moveLabel : ""}</span>
      </div>
      {rows.map((r, i) => (
        <div className="ra-row" role="row" key={r.fund.id}>
          <span className={"ra-rank" + (i === 0 ? " lead" : "")}>{i + 1}</span>
          <Link className="ra-fund" href={`/funds/${r.fund.slug}`}>
            <FundLogo fund={r.fund} size={34} />
            <span style={{ minWidth: 0 }}>
              <span className="ra-fund-name">{r.fund.name}</span>
              {r.fund.manager ? <span className="ra-fund-mgr">{r.fund.manager}</span> : null}
            </span>
          </Link>
          <span className="ra-num big">{r.gross.toFixed(2)}%</span>
          <span className="ra-num mute ra-net">{r.net.toFixed(2)}%</span>
          <span
            className={
              "ra-num " +
              (r.move == null ? "mute" : r.move > 0 ? "ra-up" : r.move < 0 ? "ra-down" : "mute")
            }
          >
            {r.move == null ? "" : signed(r.move)}
          </span>
        </div>
      ))}
    </div>
  );
}

/** A plain line of values, oldest first, drawn on the server. */
export function LineChart({ values, labels }: { values: (number | null)[]; labels: string[] }) {
  const known = values.filter((v): v is number => v != null);
  if (known.length < 2) return null;
  const lo = Math.min(...known) - 0.05;
  const hi = Math.max(...known) + 0.05;
  const w = 1000;
  const h = 180;
  const x = (i: number) => (values.length === 1 ? w / 2 : (i / (values.length - 1)) * (w - 12) + 6);
  const y = (v: number) => h - 10 - ((v - lo) / (hi - lo)) * (h - 20);
  const pts = values
    .map((v, i) => (v == null ? null : `${x(i).toFixed(1)},${y(v).toFixed(1)}`))
    .filter(Boolean)
    .join(" ");
  const lastI = values.map((v, i) => (v == null ? -1 : i)).filter((i) => i >= 0).pop()!;
  return (
    <div className="ra-chart">
      <svg viewBox={`0 0 ${w} ${h}`} role="img" aria-label={`From ${known[0].toFixed(2)}% to ${known[known.length - 1].toFixed(2)}%`}>
        <polyline points={pts} fill="none" stroke="var(--fl-gold)" strokeWidth="3" strokeLinejoin="round" />
        <circle cx={x(lastI)} cy={y(values[lastI]!)} r="6" fill="var(--fl-gold)" />
      </svg>
      <div className="ra-axis">
        {labels.map((l, i) => (
          <span key={`${l}-${i}`}>{l}</span>
        ))}
      </div>
    </div>
  );
}

export type Qa = { q: string; a: string };

export function Faq({ title, items }: { title: string; items: Qa[] }) {
  return (
    <section className="ra-faq">
      <h2>{title}</h2>
      <dl>
        {items.map((f) => (
          <div key={f.q}>
            <dt>{f.q}</dt>
            <dd>{f.a}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

export function faqLd(items: Qa[]) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: items.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a },
    })),
  };
}

/** The way to the app: one button, /get picks the store for this phone. */
export function AppCta({ title, body }: { title: string; body: string }) {
  return (
    <section className="ra-cta">
      <div className="ra-cta-text">
        <h2>{title}</h2>
        <p>{body}</p>
      </div>
      <Link className="fl-btn fl-btn-gold" href="/get">
        Get Fructa
      </Link>
    </section>
  );
}

export function JsonLd({ data }: { data: unknown }) {
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }} />;
}
