import { supabaseAdmin } from "@/lib/supabase/server";
import { PostEditor, type PostRow, type LinkOption } from "./PostEditor";

export const dynamic = "force-dynamic";

export default async function EditPostPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const db = supabaseAdmin();
  const [{ data }, { data: funds }, { data: companies }] = await Promise.all([
    db
      .from("posts")
      .select(
        "slug,kind,title,excerpt,body,cover_url,published,published_at,seo_title,seo_description,tags,fund_id,company_id,pinned,reading_minutes,updated_at",
      )
      .eq("slug", slug)
      .maybeSingle(),
    db.from("funds").select("id,name").eq("kind", "fund").neq("status", "hidden").order("name"),
    db.from("companies").select("id,name").order("name"),
  ]);

  if (!data) {
    return (
      <div className="mx-auto max-w-3xl">
        <a href="/admin/blog" className="text-sm text-faint hover:text-ink">Back to Blog</a>
        <p className="mt-6 rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">
          No post found for <code className="font-mono text-faint">/{slug}</code>.
        </p>
      </div>
    );
  }

  const links: LinkOption[] = [
    ...(funds ?? []).map((f) => ({ type: "fund" as const, id: f.id as string, name: f.name as string })),
    ...(companies ?? []).map((c) => ({ type: "company" as const, id: c.id as string, name: c.name as string })),
  ];

  return (
    <div className="mx-auto max-w-5xl">
      <PostEditor post={data as PostRow} links={links} />
    </div>
  );
}
