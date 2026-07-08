"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot } from "@/lib/publish";

// Each writer touches ONLY the keys its own form carries (same discipline as
// updateContact/updateCustody), so saving one section never blanks another.

const str = (fd: FormData, k: string) => String(fd.get(k) ?? "").trim();

async function upsertKeys(entries: { key: string; value: unknown }[]): Promise<string | null> {
  const now = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert(entries.map((e) => ({ key: e.key, value: e.value, updated_at: now })));
  return error?.message ?? null;
}

// Landing reads app_config server-side (force-dynamic), so revalidating the
// admin page is enough; the public "/" re-reads on its next request.
function done(err: string | null) {
  if (err) throw new Error(err);
  revalidatePath("/admin/settings");
  revalidatePath("/");
}

export async function saveBrand(fd: FormData) {
  const err = await upsertKeys([
    { key: "brand.name", value: str(fd, "name") },
    { key: "brand.footer_blurb", value: str(fd, "footer_blurb") },
    { key: "brand.contact_email", value: str(fd, "contact_email") },
  ]);
  await republishSnapshot();
  done(err);
}

export async function saveSeo(fd: FormData) {
  const err = await upsertKeys([
    { key: "seo.title", value: str(fd, "title") },
    { key: "seo.description", value: str(fd, "description") },
  ]);
  await republishSnapshot();
  done(err);
}

export async function saveLinks(fd: FormData) {
  const err = await upsertKeys([
    { key: "links.android_url", value: str(fd, "android_url") },
    { key: "links.ios_url", value: str(fd, "ios_url") },
  ]);
  await republishSnapshot();
  done(err);
}

export async function saveCopy(fd: FormData) {
  const err = await upsertKeys([
    { key: "landing.hero_headline", value: str(fd, "hero_headline") },
    { key: "landing.hero_accent", value: str(fd, "hero_accent") },
    { key: "landing.hero_subhead", value: str(fd, "hero_subhead") },
    { key: "landing.hero_microtrust", value: str(fd, "hero_microtrust") },
    { key: "landing.cta_headline", value: str(fd, "cta_headline") },
    { key: "landing.cta_subhead", value: str(fd, "cta_subhead") },
  ]);
  await republishSnapshot();
  done(err);
}

export async function saveStats(fd: FormData) {
  const stats: { n: string; l: string }[] = [];
  for (let i = 0; i < 4; i++) {
    const n = str(fd, `stat_${i}_n`);
    const l = str(fd, `stat_${i}_l`);
    if (n || l) stats.push({ n, l });
  }
  const err = await upsertKeys([{ key: "landing.stats", value: stats }]);
  await republishSnapshot();
  done(err);
}

// ── Marketing images (Supabase Storage `marketing` bucket) ───────────────────
// Mirrors uploadCompanyLogo. The public URL is stored in the given app_config
// key; an empty string clears it (jsonb is NOT NULL, so we store "" not null).
const MIME_EXT: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/svg+xml": "svg",
};

const IMAGE_KEYS = new Set([
  "landing.feature_rank_image",
  "landing.feature_portfolio_image",
  "landing.feature_alerts_image",
  "seo.og_image",
]);

export async function uploadMarketingImage(fd: FormData) {
  const key = str(fd, "key");
  const file = fd.get("file") as File | null;
  if (!IMAGE_KEYS.has(key) || !file || file.size === 0) return;

  const ext = MIME_EXT[file.type] ?? "png";
  const path = `${key.replace(/\./g, "/")}.${ext}`; // landing/feature_rank_image.png
  const bytes = new Uint8Array(await file.arrayBuffer());

  const db = supabaseAdmin();
  const { error } = await db.storage.from("marketing").upload(path, bytes, {
    upsert: true,
    contentType: file.type,
  });
  if (error) return;

  const { data } = db.storage.from("marketing").getPublicUrl(path);
  const url = `${data.publicUrl}?v=${Date.now()}`; // cache-bust re-uploads
  const err = await upsertKeys([{ key, value: url }]);
  await republishSnapshot();
  done(err);
}

export async function removeMarketingImage(fd: FormData) {
  const key = str(fd, "key");
  const url = str(fd, "url");
  if (!IMAGE_KEYS.has(key)) return;

  const db = supabaseAdmin();
  const marker = "/object/public/marketing/";
  const i = url.indexOf(marker);
  if (i >= 0) {
    const path = url.slice(i + marker.length).split("?")[0];
    await db.storage.from("marketing").remove([path]);
  }
  const err = await upsertKeys([{ key, value: "" }]);
  await republishSnapshot();
  done(err);
}
