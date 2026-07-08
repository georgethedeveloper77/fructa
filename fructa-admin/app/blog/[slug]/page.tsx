import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import SiteShell from "../../site/SiteShell";
import { getPost, fmtDate } from "../../site/content.server";
import { renderMarkdown } from "../../site/markdown";

export const dynamic = "force-dynamic";
const SITE = "https://fructa.africa";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) return { title: "Not found — Fructa" };
  const title = post.seo_title ?? post.title;
  const description = post.seo_description ?? post.excerpt ?? undefined;
  const og = post.cover_url ?? `${SITE}/og.png`;
  return {
    metadataBase: new URL(SITE),
    title: `${title} — Fructa`,
    description,
    alternates: { canonical: `/blog/${post.slug}` },
    openGraph: {
      type: "article",
      url: `${SITE}/blog/${post.slug}`,
      title,
      description,
      images: [og],
      publishedTime: post.published_at ?? undefined,
    },
    twitter: { card: "summary_large_image", title, description, images: [og] },
  };
}

export default async function PostPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) notFound();

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.seo_description ?? post.excerpt ?? undefined,
    datePublished: post.published_at ?? undefined,
    image: post.cover_url ?? undefined,
    author: { "@type": "Organization", name: "Fructa" },
    publisher: { "@type": "Organization", name: "Fructa" },
    mainEntityOfPage: `${SITE}/blog/${post.slug}`,
  };

  return (
    <SiteShell>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <Link href="/blog" className="fl-back">
        <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
          <path d="M15 18l-6-6 6-6" />
        </svg>
        Back to blog
      </Link>
      {post.cover_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img className="fl-post-cover" src={post.cover_url} alt="" />
      )}
      <span className="fl-eyebrow-date">{fmtDate(post.published_at)}</span>
      <article className="fl-article" dangerouslySetInnerHTML={{ __html: renderMarkdown(post.body) }} />
    </SiteShell>
  );
}
