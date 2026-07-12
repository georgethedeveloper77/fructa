"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

// Review-body moderation. Deliberately NOT in app/admin/review/, which is the
// rate-approval gate (rate_review table). Two different queues, two words that
// would otherwise collide.
//
// Note what these actions do NOT touch: `rating`. A star publishes the moment
// it is written and no admin decision changes it. Only the prose is gated.
// Writers here touch only the moderation columns, per the house rule.

function refresh() {
  revalidatePath("/admin/moderation");
  revalidatePath("/admin");
}

export async function approveBody(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  await supabaseAdmin()
    .from("insurer_reviews")
    .update({
      body_status: "approved",
      reject_reason: null,
      moderated_at: new Date().toISOString(),
    })
    .eq("id", id)
    .eq("body_status", "pending");
  refresh();
}

export async function rejectBody(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  if (!id) return;
  // The rating survives a rejected body. The user's star still counts; only
  // their prose is withheld. That is the whole point of the split.
  await supabaseAdmin()
    .from("insurer_reviews")
    .update({
      body_status: "rejected",
      reject_reason: reason || "Breaches the content rules",
      moderated_at: new Date().toISOString(),
    })
    .eq("id", id)
    .eq("body_status", "pending");
  refresh();
}

/// Hide an already-published review outright (rating included). For the case
/// where an approved body turns out to be defamatory, or a report queue fires.
export async function hideReview(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  await supabaseAdmin()
    .from("insurer_reviews")
    .update({ hidden: true })
    .eq("id", id);
  refresh();
}

export async function unhideReview(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  await supabaseAdmin()
    .from("insurer_reviews")
    .update({ hidden: false })
    .eq("id", id);
  refresh();
}

/// Block an author. Their existing rows drop out of insurer_reviews_public
/// immediately (the view filters on blocked_authors), and RLS stops them
/// writing another. They can still read the app. This is the Apple Guideline
/// 1.2 "block abusive users" requirement, satisfied without holding a name,
/// an email or a phone number: the identity is an anonymous device UUID.
export async function blockAuthor(formData: FormData) {
  const authorId = String(formData.get("author_id") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  if (!authorId) return;
  await supabaseAdmin()
    .from("blocked_authors")
    .upsert({ author_id: authorId, reason: reason || null }, { onConflict: "author_id" });
  refresh();
}

export async function unblockAuthor(formData: FormData) {
  const authorId = String(formData.get("author_id") ?? "");
  if (!authorId) return;
  await supabaseAdmin().from("blocked_authors").delete().eq("author_id", authorId);
  refresh();
}

/// Dismiss the reports on a review and put it back in front of users. Used when
/// a brigade of reports auto-hid something that is in fact fine.
export async function clearReports(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  const db = supabaseAdmin();
  await db.from("review_reports").delete().eq("review_id", id);
  await db.from("insurer_reviews").update({ hidden: false }).eq("id", id);
  refresh();
}
