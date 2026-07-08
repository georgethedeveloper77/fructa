"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot, slugify, strOrNull } from "@/lib/publish";

function refresh() {
  revalidatePath("/admin/insurers");
  revalidatePath("/admin");
}

const num = (v: FormDataEntryValue | null) => {
  const n = Number(String(v ?? "").replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) && String(v ?? "").trim() !== "" ? n : null;
};
const int = (v: FormDataEntryValue | null) => {
  const n = parseInt(String(v ?? "").replace(/[^0-9]/g, ""), 10);
  return Number.isFinite(n) ? n : null;
};

export async function createInsurer(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;
  await supabaseAdmin().from("funds").insert({
    id: slugify(name),
    name,
    manager: strOrNull(formData.get("manager")) ?? name,
    category: "insurance",
    kind: "insurance",
    currency: String(formData.get("currency") ?? "KES"),
    company_id: strOrNull(formData.get("company_id")),
    status: "live",
  });
  await republishSnapshot();
  refresh();
}

export async function updateInsurer(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;

  const benefits = String(formData.get("benefits") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  // plans textarea: one per line "Name, price"
  const plans = String(formData.get("plans") ?? "")
    .split(/\r?\n/)
    .map((line) => {
      const [n, p] = line.split(",");
      const price = num(p as unknown as FormDataEntryValue);
      return n && n.trim() && price != null ? { name: n.trim(), price } : null;
    })
    .filter(Boolean);

  await supabaseAdmin()
    .from("funds")
    .update({
      name: String(formData.get("name")),
      company_id: strOrNull(formData.get("company_id")),
      currency: String(formData.get("currency") ?? "KES"),
      motor_rate: num(formData.get("motor_rate")),
      min_premium: num(formData.get("min_premium")),
      excess_pct: num(formData.get("excess_pct")),
      excess_min: num(formData.get("excess_min")),
      claims_days: int(formData.get("claims_days")),
      rating: int(formData.get("rating")),
      benefits,
      plans,
      logo_domain: strOrNull(formData.get("logo_domain")),
    })
    .eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function deleteInsurer(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  await supabaseAdmin().from("funds").delete().eq("id", id);
  await republishSnapshot();
  refresh();
}
