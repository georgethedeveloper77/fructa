import { supabaseAdmin } from "@/lib/supabase/server";

export type Page = { slug: string; title: string; body: string; updated_at: string };
export type Post = {
  slug: string;
  title: string;
  excerpt: string | null;
  body: string;
  cover_url: string | null;
  published: boolean;
  published_at: string | null;
  seo_title: string | null;
  seo_description: string | null;
};

export async function getPage(slug: string): Promise<Page | null> {
  const { data } = await supabaseAdmin()
    .from("pages")
    .select("slug,title,body,updated_at")
    .eq("slug", slug)
    .maybeSingle();
  return (data as Page) ?? null;
}

export async function getPosts(): Promise<Post[]> {
  const { data } = await supabaseAdmin()
    .from("posts")
    .select("slug,title,excerpt,body,cover_url,published,published_at,seo_title,seo_description")
    .eq("published", true)
    .order("published_at", { ascending: false });
  return (data as Post[]) ?? [];
}

export async function getPost(slug: string): Promise<Post | null> {
  const { data } = await supabaseAdmin()
    .from("posts")
    .select("slug,title,excerpt,body,cover_url,published,published_at,seo_title,seo_description")
    .eq("slug", slug)
    .eq("published", true)
    .maybeSingle();
  return (data as Post) ?? null;
}

export function fmtDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}
