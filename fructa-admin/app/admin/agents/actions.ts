"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot, slugify, strOrNull } from "@/lib/publish";

function refresh() {
  revalidatePath("/admin/agents");
  revalidatePath("/admin");
}

export async function createAgent(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;
  const id = `${slugify(name)}-${Date.now().toString(36).slice(-4)}`;
  await supabaseAdmin().from("agents").insert({
    id,
    name,
    role: strOrNull(formData.get("role")),
    phone: strOrNull(formData.get("phone")),
    whatsapp: formData.get("whatsapp") === "on",
    is_free: formData.get("is_free") === "on",
  });
  await republishSnapshot();
  refresh();
}

export async function toggleAgentFlag(formData: FormData) {
  const id = String(formData.get("id"));
  const field = String(formData.get("field")); // active | whatsapp | is_free
  if (!["active", "whatsapp", "is_free"].includes(field)) return;
  const value = formData.get("value") === "true";
  await supabaseAdmin().from("agents").update({ [field]: value }).eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function deleteAgent(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  // agent_companies rows cascade on agent delete.
  await supabaseAdmin().from("agents").delete().eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function addAgentCompany(formData: FormData) {
  const agent_id = String(formData.get("agent_id"));
  const company_id = String(formData.get("company_id"));
  if (!agent_id || !company_id) return;
  await supabaseAdmin()
    .from("agent_companies")
    .upsert({ agent_id, company_id }, { onConflict: "agent_id,company_id" });
  await republishSnapshot();
  refresh();
}

export async function removeAgentCompany(formData: FormData) {
  const agent_id = String(formData.get("agent_id"));
  const company_id = String(formData.get("company_id"));
  if (!agent_id || !company_id) return;
  await supabaseAdmin()
    .from("agent_companies")
    .delete()
    .eq("agent_id", agent_id)
    .eq("company_id", company_id);
  await republishSnapshot();
  refresh();
}
