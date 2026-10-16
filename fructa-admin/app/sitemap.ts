import type { MetadataRoute } from "next";
import { getPosts } from "./site/content.server";
import { getFunds } from "@/lib/funds.server";
import { CATEGORIES, firstMonth, nairobiToday } from "@/lib/rates.server";

const SITE = "https://fructa.africa";

/*
 * The sitemap Google reads to find every page.
 *
 * Search Console reported "Couldn't fetch" on it. It was force-dynamic, so
 * every Googlebot request waited on two Supabase reads before a byte came
 * back, and any slow or failed read turned the whole sitemap into an error.
 * Now it is built at most once an hour and served from cache, and a failed
 * read still returns the pages that do not depend on it, so the sitemap can
 * be slow to refresh but never broken.
 */
export const revalidate = 3600;

async function safe<T>(read: () => Promise<T>, fallback: T): Promise<T> {
  try {
    return await read();
  } catch (err) {
    console.error("[sitemap] read failed:", err);
    return fallback;
  }
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const now = new Date();
  const [posts, funds, first] = await Promise.all([
    safe(getPosts, [] as Awaited<ReturnType<typeof getPosts>>),
    safe(async () => (await getFunds()).funds, [] as Awaited<ReturnType<typeof getFunds>>["funds"]),
    safe(firstMonth, null),
  ]);

  // Every category's today page, each year, and each month since the first
  // rate Fructa holds. Closed months never change; the current one does.
  const [ty, tm] = nairobiToday().split("-").map(Number);
  const periods: MetadataRoute.Sitemap = [];
  for (const c of CATEGORIES) {
    periods.push({ url: `${SITE}/rates/${c.slug}`, lastModified: now, changeFrequency: "daily", priority: 0.95 });
    if (!first) continue;
    for (let y = first[0]; y <= ty; y++) {
      periods.push({ url: `${SITE}/rates/${c.slug}/${y}`, lastModified: now, changeFrequency: y === ty ? "weekly" : "yearly", priority: 0.7 });
      for (let m = 1; m <= 12; m++) {
        const t = y * 12 + m;
        if (t < first[0] * 12 + first[1] || t > ty * 12 + tm) continue;
        const current = y === ty && m === tm;
        periods.push({
          url: `${SITE}/rates/${c.slug}/${y}/${String(m).padStart(2, "0")}`,
          lastModified: now,
          changeFrequency: current ? "daily" : "yearly",
          priority: current ? 0.85 : 0.6,
        });
      }
    }
  }

  return [
    { url: `${SITE}/`, lastModified: now, changeFrequency: "daily", priority: 1 },
    // The funds hub outranks the blog in priority on purpose: it is the page
    // that carries the head terms and the one that links to everything below.
    { url: `${SITE}/funds`, lastModified: now, changeFrequency: "daily", priority: 0.9 },
    { url: `${SITE}/blog`, lastModified: now, changeFrequency: "weekly", priority: 0.6 },
    { url: `${SITE}/privacy`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/terms`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    ...periods,

    // One entry per fund: the pages that answer a named search.
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
