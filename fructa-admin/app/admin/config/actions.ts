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

/** A staged edit: the key, and its serialized value string. */
export interface ConfigEdit {
  key: string;
  value: string;
  description?: string | null;
}

const KEY_RE = /^[a-z0-9_.-]+$/i;

/// The value string is either JSON (kept as-is) or plain text (stored as a JSON
/// string), so copy edits never need hand-quoting.
function parseValue(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

/**
 * Publish a batch of staged edits: one upsert, one snapshot rebuild.
 *
 * Config work is "fix three things, then ship", and republishing per key would
 * rebuild the snapshot three times and leave the app briefly holding a half
 * applied set. Everything lands together or nothing does.
 */
export async function publishConfig(edits: ConfigEdit[]): Promise<ConfigResult> {
  if (edits.length === 0) return { ok: true, error: null };

  const now = new Date().toISOString();
  const rows: { key: string; value: unknown; description?: string | null; updated_at: string }[] = [];

  for (const e of edits) {
    const key = e.key.trim();
    if (!KEY_RE.test(key)) {
      return { ok: false, error: `Key must be dot.case letters, digits, dash or underscore: ${key}` };
    }
    if (!e.value.trim()) return { ok: false, error: `Value is empty: ${key}` };
    const row: { key: string; value: unknown; description?: string | null; updated_at: string } = {
      key,
      value: parseValue(e.value),
      updated_at: now,
    };
    // Only carry description when the caller supplied one, so a batch publish
    // never blanks a description it was not editing.
    if (e.description !== undefined) row.description = e.description;
    rows.push(row);
  }

  const { error } = await supabaseAdmin().from("app_config").upsert(rows);
  if (error) return { ok: false, error: error.message };

  await republishSnapshot();
  revalidatePath("/admin/config");
  revalidatePath("/");
  return { ok: true, error: null };
}

/** Single-key upsert. Kept for the custom-key escape hatch. */
export async function upsertConfig(formData: FormData): Promise<ConfigResult> {
  const key = String(formData.get("key") ?? "").trim();
  const raw = String(formData.get("value") ?? "");
  const description = String(formData.get("description") ?? "").trim() || null;

  if (!KEY_RE.test(key)) {
    return { ok: false, error: "Key must be dot.case letters/digits (e.g. onboarding.headline)." };
  }
  if (!raw.trim()) return { ok: false, error: "Value is empty." };

  const { error } = await supabaseAdmin().from("app_config").upsert({
    key,
    value: parseValue(raw),
    description,
    updated_at: new Date().toISOString(),
  });
  if (error) return { ok: false, error: error.message };

  await republishSnapshot();
  revalidatePath("/admin/config");
  return { ok: true, error: null };
}

export async function deleteConfig(key: string): Promise<ConfigResult> {
  const { error } = await supabaseAdmin().from("app_config").delete().eq("key", key);
  if (error) return { ok: false, error: error.message };
  await republishSnapshot();
  revalidatePath("/admin/config");
  return { ok: true, error: null };
}

export async function republishNow(): Promise<ConfigResult> {
  try {
    await republishSnapshot();
    revalidatePath("/admin/config");
    return { ok: true, error: null };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Republish failed" };
  }
}
