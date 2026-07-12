"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot } from "@/lib/publish";

// Each writer touches ONLY the keys its own form carries (same discipline as
// updateContact/updateCustody), so saving one section never blanks another.
//
// The marketing image uploads are gone: the landing is chart-led and reads its
// figures from rate_history, so there are no screenshots to store. The
// `marketing` bucket and the landing.feature_*_image keys are now unused.

const str = (fd: FormData, k: string) => String(fd.get(k) ?? "").trim();

export type Result = { ok: boolean; error: string | null };

async function upsertKeys(entries: { key: string; value: unknown }[]): Promise<string | null> {
  const now = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert(entries.map((e) => ({ key: e.key, value: e.value, updated_at: now })));
  return error?.message ?? null;
}

// Landing reads app_config server-side (force-dynamic), so revalidating the
// admin page is enough; the public "/" re-reads on its next request.
function revalidate() {
  revalidatePath("/admin/settings");
  revalidatePath("/");
}

function done(err: string | null) {
  if (err) throw new Error(err);
  revalidate();
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

// Manual republish from the header bar. Returns a Result rather than throwing so
// the bar can show why it failed without taking the page down.
export async function republishNow(): Promise<Result> {
  try {
    await republishSnapshot();
    revalidate();
    return { ok: true, error: null };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Republish failed" };
  }
}
