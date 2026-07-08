import { supabaseAdmin } from "@/lib/supabase/server";
import { ContentClient, type PageRow, type PostRow } from "./ContentClient";

export const dynamic = "force-dynamic";

export default async function ContentPage() {
  const db = supabaseAdmin();
  const [{ data: pages }, { data: posts }] = await Promise.all([
    db.from("pages").select("slug,title,body,updated_at").order("slug"),
    db
      .from("posts")
      .select("slug,title,excerpt,body,cover_url,published,published_at,seo_title,seo_description,updated_at")
      .order("created_at", { ascending: false }),
  ]);

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Content</h1>
        <p className="mt-1 text-sm text-mute">
          The website's legal pages and blog. Edits publish to fructa.africa on save. Body fields
          accept Markdown (headings, <span className="font-mono text-xs">**bold**</span>, lists,
          links, quotes).
        </p>
      </header>
      <ContentClient pages={(pages ?? []) as PageRow[]} posts={(posts ?? []) as PostRow[]} />
    </div>
  );
}
