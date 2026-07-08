"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase/server";
import { republishSnapshot } from "@/lib/publish";

export interface ConfigRow {
  key: string;
  value: unknown;
  description: string | null;
  updated_at: string;
}

export interface ConfigResult {
  ok: boolean;
  error: string | null;
}

/// Upsert a config key. The value textarea accepts either JSON (kept as-is)
/// or plain text (stored as a JSON string) — so copy edits don't require
/// hand-quoting. Republishes the snapshot so devices pick it up.
export async function upsertConfig(formData: FormData): Promise<ConfigResult> {
  const key = String(formData.get("key") ?? "").trim();
  const raw = String(formData.get("value") ?? "");
  const description = String(formData.get("description") ?? "").trim() || null;

  if (!/^[a-z0-9_.-]+$/i.test(key)) {
    return { ok: false, error: "Key must be dot.case letters/digits (e.g. onboarding.headline)." };
  }
  if (!raw.trim()) return { ok: false, error: "Value is empty." };

  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    value = raw; // plain text → JSON string
  }

  const db = supabaseAdmin();
  const { error } = await db.from("app_config").upsert({
    key,
    value,
    description,
    updated_at: new Date().toISOString(),
  });
  if (error) return { ok: false, error: error.message };

  await republishSnapshot();
  revalidatePath("/admin/config");
  return { ok: true, error: null };
}

export async function deleteConfig(key: string): Promise<ConfigResult> {
  const db = supabaseAdmin();
  const { error } = await db.from("app_config").delete().eq("key", key);
  if (error) return { ok: false, error: error.message };
  await republishSnapshot();
  revalidatePath("/admin/config");
  return { ok: true, error: null };
}
