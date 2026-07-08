import type { Metadata } from "next";
import Link from "next/link";
import SiteShell from "../site/SiteShell";
import { getPosts, fmtDate } from "../site/content.server";

export const dynamic = "force-dynamic";
const SITE = "https://fructa.africa";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: "Blog — Fructa",
  description: "Guides and updates on Kenyan investment rates: MMFs, T-bills, SACCOs and more.",
  alternates: { canonical: "/blog" },
  openGraph: { type: "website", url: `${SITE}/blog`, title: "Fructa Blog", siteName: "Fructa" },
};

export default async function BlogPage() {
  const posts = await getPosts();
  return (
    <SiteShell>
      <div className="fl-blog-head">
        <h1>Blog</h1>
        <p>Guides and updates on Kenyan investment rates.</p>
      </div>

      {posts.length === 0 ? (
        <p className="fl-empty">No posts yet. Check back soon.</p>
      ) : (
        <div className="fl-post-list">
          {posts.map((p) => (
            <Link key={p.slug} href={`/blog/${p.slug}`} className="fl-post-card">
              <span className="fl-date">{fmtDate(p.published_at)}</span>
              <h2>{p.title}</h2>
              {p.excerpt && <p>{p.excerpt}</p>}
            </Link>
          ))}
        </div>
      )}
    </SiteShell>
  );
}
