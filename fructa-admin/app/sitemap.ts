import type { MetadataRoute } from "next";
import { getPosts } from "./site/content.server";
import { getFunds } from "@/lib/funds.server";

const SITE = "https://fructa.africa";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const now = new Date();
  const [posts, { funds }] = await Promise.all([getPosts(), getFunds()]);

  return [
    { url: `${SITE}/`, lastModified: now, changeFrequency: "daily", priority: 1 },
    // The funds hub outranks the blog in priority on purpose: it is the page
    // that carries the head terms and the one that links to everything below.
    { url: `${SITE}/funds`, lastModified: now, changeFrequency: "daily", priority: 0.9 },
    { url: `${SITE}/blog`, lastModified: now, changeFrequency: "weekly", priority: 0.6 },
    { url: `${SITE}/privacy`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/terms`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },

    // One entry per fund. These are the pages that answer a named search, and
    // without them in the sitemap Google has to find 144 URLs by crawl alone.
    // changeFrequency is daily because the rate genuinely changes daily; lying
    // about it is one of the few ways to actively lose crawl budget.
    ...funds.map((f) => ({
      url: `${SITE}/funds/${f.slug}`,
      lastModified: f.updatedAt ? new Date(f.updatedAt) : now,
      changeFrequency: "daily" as const,
      priority: 0.8,
    })),

    ...posts.map((p) => ({
      url: `${SITE}/blog/${p.slug}`,
      lastModified: p.published_at ? new Date(p.published_at) : now,
      changeFrequency: "monthly" as const,
      priority: 0.5,
    })),
  ];
}

export const dynamic = "force-dynamic";
