"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

export type Result = { ok: boolean; error: string | null };

const str = (fd: FormData, k: string) => String(fd.get(k) ?? "").trim();
const strOrNull = (fd: FormData, k: string) => str(fd, k) || null;
const body = (fd: FormData) => String(fd.get("body") ?? "");

function slugify(s: string): string {
  return s.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function revalidatePost(slug?: string) {
  revalidatePath("/admin/content");
  revalidatePath("/blog");
  if (slug) revalidatePath(`/blog/${slug}`);
}

// ── Pages (privacy / terms / …) ──────────────────────────────────────────────
export async function savePage(fd: FormData): Promise<Result> {
  const slug = str(fd, "slug");
  if (!slug) return { ok: false, error: "Missing page." };
  const { error } = await supabaseAdmin()
    .from("pages")
    .update({ title: str(fd, "title"), body: body(fd), updated_at: new Date().toISOString() })
    .eq("slug", slug);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/content");
  revalidatePath(`/${slug}`);
  return { ok: true, error: null };
}

// ── Blog posts ───────────────────────────────────────────────────────────────
export async function createPost(fd: FormData): Promise<Result> {
  const title = str(fd, "title");
  if (!title) return { ok: false, error: "Title is required." };
  const slug = slugify(str(fd, "slug") || title);
  if (!slug) return { ok: false, error: "Could not derive a slug." };
  const { error } = await supabaseAdmin().from("posts").insert({ slug, title });
  if (error) {
    return { ok: false, error: error.message.includes("duplicate") ? "That slug already exists." : error.message };
  }
  revalidatePost(slug);
  return { ok: true, error: null };
}

// Field-scoped: never touches cover_url (upload owns it) or published (toggle owns it).
export async function updatePost(fd: FormData): Promise<Result> {
  const slug = str(fd, "slug");
  if (!slug) return { ok: false, error: "Missing post." };
  const { error } = await supabaseAdmin()
    .from("posts")
    .update({
      title: str(fd, "title"),
      excerpt: strOrNull(fd, "excerpt"),
      body: body(fd),
      seo_title: strOrNull(fd, "seo_title"),
      seo_description: strOrNull(fd, "seo_description"),
      updated_at: new Date().toISOString(),
    })
    .eq("slug", slug);
  if (error) return { ok: false, error: error.message };
  revalidatePost(slug);
  return { ok: true, error: null };
}

export async function togglePostPublished(fd: FormData) {
  const slug = str(fd, "slug");
  const publish = fd.get("value") === "true";
  const patch = publish
    ? { published: true, published_at: new Date().toISOString() }
    : { published: false };
  const { error } = await supabaseAdmin().from("posts").update(patch).eq("slug", slug);
  if (error) throw new Error(error.message);
  revalidatePost(slug);
}

export async function deletePost(fd: FormData) {
  const slug = str(fd, "slug");
  if (!slug) return;
  await supabaseAdmin().from("posts").delete().eq("slug", slug);
  revalidatePost(slug);
}

// ── Cover images (marketing bucket, blog/ folder) ────────────────────────────
const MIME_EXT: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
};

export async function uploadPostCover(fd: FormData): Promise<Result> {
  const slug = str(fd, "slug");
  const file = fd.get("file") as File | null;
  if (!slug) return { ok: false, error: "Missing post." };
  if (!file || file.size === 0) return { ok: false, error: "No file selected." };
  if (file.size > 4 * 1024 * 1024) return { ok: false, error: "File is over 4 MB." };
  const ext = MIME_EXT[file.type];
  if (!ext) return { ok: false, error: "Use a PNG, JPG or WebP image." };

  const path = `blog/${slug}.${ext}`;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const db = supabaseAdmin();
  const up = await db.storage.from("marketing").upload(path, bytes, { upsert: true, contentType: file.type });
  if (up.error) return { ok: false, error: `Storage: ${up.error.message}` };

  const { data } = db.storage.from("marketing").getPublicUrl(path);
  const url = `${data.publicUrl}?v=${Date.now()}`;
  const { error } = await db.from("posts").update({ cover_url: url }).eq("slug", slug);
  if (error) return { ok: false, error: error.message };
  revalidatePost(slug);
  return { ok: true, error: null };
}

export async function removePostCover(fd: FormData): Promise<Result> {
  const slug = str(fd, "slug");
  const url = str(fd, "url");
  if (!slug) return { ok: false, error: "Missing post." };
  const db = supabaseAdmin();
  const marker = "/object/public/marketing/";
  const i = url.indexOf(marker);
  if (i >= 0) {
    const path = url.slice(i + marker.length).split("?")[0];
    await db.storage.from("marketing").remove([path]);
  }
  const { error } = await db.from("posts").update({ cover_url: null }).eq("slug", slug);
  if (error) return { ok: false, error: error.message };
  revalidatePost(slug);
  return { ok: true, error: null };
}
