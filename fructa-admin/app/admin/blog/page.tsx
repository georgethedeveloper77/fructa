import { supabaseAdmin } from "@/lib/supabase/server";
import { BlogClient, type PostRow } from "./BlogClient";

export const dynamic = "force-dynamic";

export default async function BlogPage() {
  const db = supabaseAdmin();
  const { data: posts } = await db
    .from("posts")
    .select(
      "slug,kind,title,excerpt,body,cover_url,published,published_at,seo_title,seo_description,tags,fund_id,company_id,pinned,reading_minutes,updated_at",
    )
    .order("updated_at", { ascending: false });

  return (
    <div className="mx-auto max-w-5xl">
      <BlogClient posts={(posts ?? []) as PostRow[]} />
    </div>
  );
}
