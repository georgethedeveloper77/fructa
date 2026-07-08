"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot } from "@/lib/publish";

function refresh() {
  revalidatePath("/admin/insights");
  revalidatePath("/admin");
}

const TAGS = ["STRENGTH", "WATCH", "NOTE"];

export async function addTemplate(formData: FormData) {
  const key = String(formData.get("key") ?? "").trim();
  const tag = String(formData.get("tag") ?? "");
  const template = String(formData.get("template") ?? "").trim();
  if (!key || !template || !TAGS.includes(tag)) return;
  await supabaseAdmin()
    .from("insight_templates")
    .upsert({ key, tag, template, active: true }, { onConflict: "key,template" });
  await republishSnapshot();
  refresh();
}

export async function updateTemplate(formData: FormData) {
  const id = Number(formData.get("id"));
  const tag = String(formData.get("tag") ?? "");
  const template = String(formData.get("template") ?? "").trim();
  if (!Number.isFinite(id) || !template || !TAGS.includes(tag)) return;
  await supabaseAdmin()
    .from("insight_templates")
    .update({ tag, template })
    .eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function toggleTemplate(formData: FormData) {
  const id = Number(formData.get("id"));
  const value = formData.get("value") === "true";
  if (!Number.isFinite(id)) return;
  await supabaseAdmin()
    .from("insight_templates")
    .update({ active: value })
    .eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function deleteTemplate(formData: FormData) {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  await supabaseAdmin().from("insight_templates").delete().eq("id", id);
  await republishSnapshot();
  refresh();
}
