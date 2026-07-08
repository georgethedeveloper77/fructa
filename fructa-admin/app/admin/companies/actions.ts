"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { republishSnapshot, slugify, strOrNull } from "@/lib/publish";

function refresh(id?: string) {
  revalidatePath("/admin/companies");
  revalidatePath("/admin/agents");
  revalidatePath("/admin/funds");
  revalidatePath("/admin");
  if (id) revalidatePath(`/admin/companies/${id}`);
}

const TYPES = ["fund_manager", "insurer", "sacco", "government"];

export async function createCompany(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;
  const type = String(formData.get("type") ?? "fund_manager");
  const id = slugify(name);
  if (!id) return;
  await supabaseAdmin().from("companies").insert({
    id,
    name,
    type: TYPES.includes(type) ? type : "fund_manager",
    website: strOrNull(formData.get("website")),
  });
  await republishSnapshot();
  refresh();
}

export async function updateCompany(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  const type = String(formData.get("type") ?? "fund_manager");
  await supabaseAdmin()
    .from("companies")
    .update({
      // Brand colour and logo are owned by setBrandColor / uploadCompanyLogo /
      // removeCompanyLogo — they are NOT inputs in this row form. Writing them
      // here read them back as null on every Save and wiped them. Same rule as
      // updateCustody: a writer only touches the fields its own form carries.
      name: String(formData.get("name")),
      type: TYPES.includes(type) ? type : "fund_manager",
      website: strOrNull(formData.get("website")),
      phone: strOrNull(formData.get("phone")),
      whatsapp: strOrNull(formData.get("whatsapp")),
      email: strOrNull(formData.get("email")),
    })
    .eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function updateContact(formData: FormData) {
  const id = String(formData.get("id") ?? "").trim();
  if (!id) throw new Error("updateContact: missing company id");

  // Only fields this form carries — never brand_color/logo_url (those live in
  // setBrandColor/uploadCompanyLogo; touching them here nulls them on Save).
  const patch = {
    website: strOrNull(formData.get("website")),
    phone: strOrNull(formData.get("phone")),
    whatsapp: strOrNull(formData.get("whatsapp")),
    email: strOrNull(formData.get("email")),
  };

  const { error } = await supabaseAdmin()
    .from("companies")
    .update(patch)
    .eq("id", id);

  if (error) throw new Error(`updateContact: ${error.message}`);

  revalidatePath(`/admin/companies/${id}`);
  revalidatePath("/admin/companies");
  await republishSnapshot();
}

// Governance / custody chain (trustee · custodian · auditor). Manager-level
// trust signals that ride in the snapshot (0026) and surface on the app's fund
// detail page. Separate writer from updateCompany so a table edit that omits
// these never nulls them.
export async function updateCustody(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  await supabaseAdmin()
    .from("companies")
    .update({
      trustee: strOrNull(formData.get("trustee")),
      custodian: strOrNull(formData.get("custodian")),
      auditor: strOrNull(formData.get("auditor")),
    })
    .eq("id", id);
  await republishSnapshot();
  refresh(id);
}

// Inline brand-colour set from the swatch.
export async function setBrandColor(formData: FormData) {
  const id = String(formData.get("id"));
  const brand_color = strOrNull(formData.get("brand_color"));
  if (!id) return;
  await supabaseAdmin().from("companies").update({ brand_color }).eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function toggleCompanyVerified(formData: FormData) {
  const id = String(formData.get("id"));
  const value = formData.get("value") === "true";
  await supabaseAdmin().from("companies").update({ verified: value }).eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function deleteCompany(formData: FormData) {
  const id = String(formData.get("id"));
  if (!id) return;
  const db = supabaseAdmin();
  // Detach funds first (funds.company_id has no cascade), then delete.
  await db.from("funds").update({ company_id: null }).eq("company_id", id);
  await db.from("companies").delete().eq("id", id);
  await republishSnapshot();
  refresh();
}

// ── Logo upload/remove (manual, Supabase Storage) ────────────────────────────
const TYPE_FOLDER: Record<string, string> = {
  fund_manager: "funds",
  insurer: "insurance",
  sacco: "sacco",
  government: "gvt",
};
const MIME_EXT: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/svg+xml": "svg",
};

export async function uploadCompanyLogo(formData: FormData) {
  const id = String(formData.get("id"));
  const type = String(formData.get("type") ?? "fund_manager");
  const file = formData.get("file") as File | null;
  if (!id || !file || file.size === 0) return;

  const folder = TYPE_FOLDER[type] ?? "funds";
  const ext = MIME_EXT[file.type] ?? "png";
  const path = `${folder}/${id}.${ext}`;
  const bytes = new Uint8Array(await file.arrayBuffer());

  const db = supabaseAdmin();
  const { error } = await db.storage.from("logos").upload(path, bytes, {
    upsert: true,
    contentType: file.type,
  });
  if (error) return;
  // Cache-bust so re-uploads to the same path show immediately in the app.
  const { data } = db.storage.from("logos").getPublicUrl(path);
  const url = `${data.publicUrl}?v=${Date.now()}`;
  await db.from("companies").update({ logo_url: url }).eq("id", id);
  await republishSnapshot();
  refresh();
}

export async function removeCompanyLogo(formData: FormData) {
  const id = String(formData.get("id"));
  const logoUrl = String(formData.get("logo_url") ?? "");
  const db = supabaseAdmin();
  const marker = "/object/public/logos/";
  const i = logoUrl.indexOf(marker);
  if (i >= 0) {
    const path = logoUrl.slice(i + marker.length).split("?")[0];
    await db.storage.from("logos").remove([path]);
  }
  await db.from("companies").update({ logo_url: null }).eq("id", id);
  await republishSnapshot();
  refresh();
}

// ── Bulk actions ─────────────────────────────────────────────────────────────
export async function bulkSetVerified(ids: string[], value: boolean) {
  if (!ids.length) return;
  await supabaseAdmin().from("companies").update({ verified: value }).in("id", ids);
  await republishSnapshot();
  refresh();
}

export async function bulkDeleteCompanies(ids: string[]) {
  if (!ids.length) return;
  const db = supabaseAdmin();
  await db.from("funds").update({ company_id: null }).in("company_id", ids);
  await db.from("companies").delete().in("id", ids);
  await republishSnapshot();
  refresh();
}
