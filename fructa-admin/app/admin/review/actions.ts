"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

// Approving a held rate applies it exactly like an auto/manual set would:
// append to history, refresh current_rate, re-publish the snapshot.
async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch { /* ignore */ }
}

export async function approveReview(formData: FormData) {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  const db = supabaseAdmin();

  const { data: r } = await db
    .from("rate_review")
    .select("fund_id,new_rate,as_of")
    .eq("id", id)
    .eq("status", "pending")
    .single();
  if (!r) return;

  await db.from("rate_history").upsert(
    { fund_id: r.fund_id, rate: r.new_rate, as_of: r.as_of, source: "review" },
    { onConflict: "fund_id,as_of" },
  );
  await db.from("funds")
    .update({ current_rate: r.new_rate, status: "live" })
    .eq("id", r.fund_id);
  await db.from("rate_review")
    .update({ status: "approved", decided_at: new Date().toISOString() })
    .eq("id", id);

  await republishSnapshot();
  revalidatePath("/admin/review");
  revalidatePath("/admin/funds");
  revalidatePath("/admin");
}

export async function rejectReview(formData: FormData) {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  await supabaseAdmin()
    .from("rate_review")
    .update({ status: "rejected", decided_at: new Date().toISOString() })
    .eq("id", id);
  revalidatePath("/admin/review");
}
