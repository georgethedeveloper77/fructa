import type { Metadata } from "next";
import { notFound } from "next/navigation";
import SiteShell from "../site/SiteShell";
import { getPage } from "../site/content.server";
import { renderMarkdown } from "../site/markdown";

export const dynamic = "force-dynamic";
const SITE = "https://fructa.africa";

export async function generateMetadata(): Promise<Metadata> {
  const p = await getPage("privacy");
  return {
    metadataBase: new URL(SITE),
    title: `${p?.title ?? "Privacy Policy"} — Fructa`,
    description: "How Fructa handles your data. Your holdings stay on your device.",
    alternates: { canonical: "/privacy" },
  };
}

export default async function PrivacyPage() {
  const p = await getPage("privacy");
  if (!p) notFound();
  return (
    <SiteShell>
      <article className="fl-article" dangerouslySetInnerHTML={{ __html: renderMarkdown(p.body) }} />
    </SiteShell>
  );
}
