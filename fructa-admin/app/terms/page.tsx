import type { Metadata } from "next";
import { notFound } from "next/navigation";
import SiteShell from "../site/SiteShell";
import { getPage } from "../site/content.server";
import { renderMarkdown } from "../site/markdown";

export const dynamic = "force-dynamic";
const SITE = "https://fructa.africa";

export async function generateMetadata(): Promise<Metadata> {
  const p = await getPage("terms");
  return {
    metadataBase: new URL(SITE),
    title: `${p?.title ?? "Terms of Use"} — Fructa`,
    description: "The terms for using Fructa. Rates are information, not financial advice.",
    alternates: { canonical: "/terms" },
  };
}

export default async function TermsPage() {
  const p = await getPage("terms");
  if (!p) notFound();
  return (
    <SiteShell>
      <article className="fl-article" dangerouslySetInnerHTML={{ __html: renderMarkdown(p.body) }} />
    </SiteShell>
  );
}
