"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

// Wraps publish themselves (build-wraps, hourly). These actions are for
// stepping in: run now, rebuild one, hold or release, delete, edit stories,
// and tune what counts as a story.

type Result = { ok: boolean; error?: string };

/** Calls build-wraps with the shared cron secret. */
async function invoke(body: Record<string, unknown>): Promise<Result> {
  try {
    const res = await fetch(`${process.env.SUPABASE_URL}/functions/v1/build-wraps`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-cron-secret": process.env.CRON_SECRET ?? "",
      },
      body: JSON.stringify(body),
    });
    const json = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string };
    return json.ok ? { ok: true } : { ok: false, error: json.error ?? `HTTP ${res.status}` };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

function done(id?: string) {
  revalidatePath("/admin/wraps");
  if (id) revalidatePath(`/admin/wraps/${id}`);
}

/** The hourly run, now: today, this week, anything that just closed. */
export async function runWrapsNow(): Promise<void> {
  await invoke({});
  done();
}

/** Build every past day, week, month, quarter and year the history supports. */
export async function backfillWraps(formData: FormData): Promise<void> {
  await invoke({ backfill: true, force: formData.get("force") === "1" });
  done();
}

/** Rebuild one wrap from the data. Keeps a hold; keeps edits unless forced. */
export async function rebuildWrap(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  await invoke({ rebuild: id, force: formData.get("force") === "1" });
  done(id);
}

/** Hold takes a wrap off the app and stops its push; release puts it back. */
export async function setWrapStatus(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!id || !["live", "held", "draft"].includes(status)) return;
  await supabaseAdmin()
    .from("wraps")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", id);
  await invoke({ publish_only: true });
  done(id);
}

/** Delete a wrap. The next hourly run rebuilds the period if it is still current. */
export async function deleteWrap(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  await supabaseAdmin().from("wraps").delete().eq("id", id);
  await invoke({ publish_only: true });
  done();
}

type Story = Record<string, unknown> & { key: string };

/**
 * Save edited stories. Only the text fields a story card shows are editable;
 * charts and figures behind them stay as built. Marks the wrap edited, so
 * automatic rebuilds leave it alone.
 */
export async function saveWrapStories(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  const db = supabaseAdmin();
  const { data: row, error } = await db.from("wraps").select("stories").eq("id", id).single();
  if (error || !row) return;

  const before = (row.stories ?? []) as Story[];
  const after: Story[] = [];
  for (const s of before) {
    if (formData.get(`drop:${s.key}`) === "1") continue;
    const next: Story = { ...s };
    for (const f of ["title", "big", "unit", "line"] as const) {
      const v = formData.get(`${f}:${s.key}`);
      if (typeof v === "string" && v.trim()) next[f] = v.trim();
    }
    after.push(next);
  }
  const first = after[0] as { title?: string; big?: string; fund_id?: string | null } | undefined;
  const lead = first ? (first.fund_id ? `${first.title} ${first.big}` : `${first.title}: ${first.big}`) : null;

  const { error: upErr } = await db
    .from("wraps")
    .update({ stories: after, lead, edited: true, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (upErr) return;
  await invoke({ publish_only: true });
  done(id);
}

/** The story.* thresholds. Each key is written on its own. */
const NUMBER_KEYS = [
  "story.daily_ratio",
  "story.daily_min_move",
  "story.daily_max",
  "story.weekly_max",
  "story.repeat_weeks",
  "story.breadth_min",
  "story.weekly_publish_dow",
  "story.weekly_publish_hour",
] as const;
const BOOL_KEYS = ["story.enabled", "story.weekly_push"] as const;

export async function saveStoryThresholds(formData: FormData): Promise<void> {
  const db = supabaseAdmin();
  const now = new Date().toISOString();
  for (const key of NUMBER_KEYS) {
    const raw = formData.get(key);
    if (raw == null || String(raw).trim() === "") continue;
    const n = Number(raw);
    if (!Number.isFinite(n)) continue;
    await db.from("app_config").upsert({ key, value: n, updated_at: now });
  }
  for (const key of BOOL_KEYS) {
    if (formData.get(`${key}:present`) !== "1") continue;
    await db.from("app_config").upsert({ key, value: formData.get(key) === "on", updated_at: now });
  }
  done();
}
