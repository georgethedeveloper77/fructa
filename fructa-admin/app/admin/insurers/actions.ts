"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot, slugify, strOrNull } from "@/lib/publish";

function refresh() {
  revalidatePath("/admin/insurers");
  revalidatePath("/admin");
}

const slug = (v: string) =>
  v.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

const num = (v: FormDataEntryValue | null) => {
  const n = Number(String(v ?? "").replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) && String(v ?? "").trim() !== "" ? n : null;
};
const int = (v: FormDataEntryValue | null) => {
  const s = String(v ?? "").replace(/[^0-9]/g, "");
  if (s === "") return null;
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? n : null;
};

// "code, label" per line -> [{code,label}] (IRA classes). Blank lines dropped.
function parseClasses(v: FormDataEntryValue | null) {
  return String(v ?? "")
    .split(/\r?\n/)
    .map((line) => {
      const idx = line.indexOf(",");
      if (idx < 0) return null;
      const code = line.slice(0, idx).trim();
      const label = line.slice(idx + 1).trim();
      return code && label ? { code, label } : null;
    })
    .filter(Boolean);
}

// "TAG | text" per line -> [{tag,label,text}]. TAG in STRENGTH|WATCH|NOTE
// (anything else falls back to NOTE); label mirrors the tag.
function parseSignals(v: FormDataEntryValue | null) {
  const allow = new Set(["STRENGTH", "WATCH", "NOTE"]);
  return String(v ?? "")
    .split(/\r?\n/)
    .map((line) => {
      const idx = line.indexOf("|");
      if (idx < 0) {
        const text = line.trim();
        return text ? { tag: "NOTE", label: "NOTE", text } : null;
      }
      const raw = line.slice(0, idx).trim().toUpperCase();
      const tag = allow.has(raw) ? raw : "NOTE";
      const text = line.slice(idx + 1).trim();
      return text ? { tag, label: tag, text } : null;
    })
    .filter(Boolean);
}

// Region base prices -> {ea,af,ww,sch}, omitting blanks. Null if all blank so
// the app's hasTravel gate stays false for a motor-only insurer.
function parseTravelRegions(formData: FormData) {
  const out: Record<string, number> = {};
  for (const k of ["ea", "af", "ww", "sch"] as const) {
    const n = num(formData.get(`travel_${k}`));
    if (n != null) out[k] = n;
  }
  return Object.keys(out).length ? out : null;
}

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

  // Field-scoped: every column this form owns is written explicitly. Columns
  // the form does not carry (e.g. the legacy `plans`) are left untouched.
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
      logo_domain: strOrNull(formData.get("logo_domain")),
      // IN-3 detail surface
      settle_pct: num(formData.get("settle_pct")),
      licensed_since: int(formData.get("licensed_since")),
      phone: strOrNull(formData.get("phone")),
      whatsapp: strOrNull(formData.get("whatsapp")),
      email: strOrNull(formData.get("email")),
      paybill: strOrNull(formData.get("paybill")),
      website: strOrNull(formData.get("website")),
      brand_color: strOrNull(formData.get("brand_color")),
      classes: parseClasses(formData.get("classes")),
      signals: parseSignals(formData.get("signals")),
      travel_regions: parseTravelRegions(formData),
      travel_cover: strOrNull(formData.get("travel_cover")),
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


// ── insurance types (grid cards on the Insure home) ──────────────────────────

export async function createInsuranceType(formData: FormData) {
  const label = String(formData.get("label") ?? "").trim();
  if (!label) return;
  const key = strOrNull(formData.get("key")) ?? slug(label);
  if (!key) return;
  await supabaseAdmin().from("insurance_types").insert({
    key,
    label,
    icon: strOrNull(formData.get("icon")),
    status: String(formData.get("status") ?? "soon"),
    ord: int(formData.get("ord")) ?? 0,
    lottie_url: strOrNull(formData.get("lottie_url")),
    active: true,
  });
  await republishSnapshot();
  refresh();
}

export async function updateInsuranceType(formData: FormData) {
  const key = String(formData.get("key"));
  if (!key) return;
  await supabaseAdmin()
    .from("insurance_types")
    .update({
      label: String(formData.get("label")),
      icon: strOrNull(formData.get("icon")),
      status: String(formData.get("status") ?? "soon"),
      ord: int(formData.get("ord")) ?? 0,
      sub: strOrNull(formData.get("sub")),
      lottie_url: strOrNull(formData.get("lottie_url")),
      active: formData.get("active") === "on",
    })
    .eq("key", key);
  await republishSnapshot();
  refresh();
}

export async function deleteInsuranceType(formData: FormData) {
  const key = String(formData.get("key"));
  if (!key) return;
  await supabaseAdmin().from("insurance_types").delete().eq("key", key);
  await republishSnapshot();
  refresh();
}
