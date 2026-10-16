"use server";

import { supabaseAdmin } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

// Held rate changes: approve, reject, correct or delete, one at a time or in
// bulk. Approving applies a rate exactly like an automatic one would: it is
// appended to rate_history, current_rate moves only when it is the newest
// print the fund has, and the snapshot and this week's wraps are refreshed
// once per action, not once per row.

async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch { /* ignore */ }
}

// An approved rate can now become a story: refresh today and this week.
async function refreshWraps() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/build-wraps`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-cron-secret": process.env.CRON_SECRET ?? "" },
      body: "{}",
    });
  } catch { /* ignore */ }
}

function done() {
  revalidatePath("/admin/review");
  revalidatePath("/admin/funds");
  revalidatePath("/admin/wraps");
  revalidatePath("/admin");
}

function idsOf(formData: FormData): number[] {
  return formData
    .getAll("ids")
    .map((v) => Number(v))
    .filter((n) => Number.isFinite(n));
}

/** Applies pending rows. Returns how many were applied. */
async function apply(ids: number[]): Promise<number> {
  if (!ids.length) return 0;
  const db = supabaseAdmin();
  const { data } = await db
    .from("rate_review")
    .select("id,fund_id,new_rate,as_of")
    .in("id", ids)
    .eq("status", "pending");
  const rows = (data ?? []) as { id: number; fund_id: string; new_rate: number; as_of: string }[];
  if (!rows.length) return 0;

  // One print per fund and day: if two held rows share them, the later id wins.
  const byKey = new Map<string, (typeof rows)[number]>();
  for (const r of [...rows].sort((a, b) => a.id - b.id)) byKey.set(`${r.fund_id}|${r.as_of}`, r);
  await db.from("rate_history").upsert(
    [...byKey.values()].map((r) => ({ fund_id: r.fund_id, rate: r.new_rate, as_of: r.as_of, source: "review" })),
    { onConflict: "fund_id,as_of" },
  );

  // current_rate follows the newest print each fund now has, so approving an
  // old held row never pulls a fund back to a July rate.
  const funds = [...new Set(rows.map((r) => r.fund_id))];
  for (const fundId of funds) {
    const { data: latest } = await db
      .from("rate_history")
      .select("rate")
      .eq("fund_id", fundId)
      .order("as_of", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (latest) {
      await db.from("funds").update({ current_rate: latest.rate, status: "live" }).eq("id", fundId);
    }
  }

  await db
    .from("rate_review")
    .update({ status: "approved", decided_at: new Date().toISOString() })
    .in("id", rows.map((r) => r.id));

  // The scraper compares each day's rate with the fund's current rate, so one
  // real jump was held again every day until approved: five AA Kenya rows for
  // one change. Approving the newest settles the older ones for that fund.
  const newest = new Map<string, string>();
  for (const r of rows) {
    if ((newest.get(r.fund_id) ?? "") < r.as_of) newest.set(r.fund_id, r.as_of);
  }
  for (const [fundId, asOf] of newest) {
    await db
      .from("rate_review")
      .update({ status: "rejected", decided_at: new Date().toISOString(), decided_by: "superseded" })
      .eq("fund_id", fundId)
      .eq("status", "pending")
      .lt("as_of", asOf);
  }
  return rows.length;
}

async function reject(ids: number[]): Promise<void> {
  if (!ids.length) return;
  await supabaseAdmin()
    .from("rate_review")
    .update({ status: "rejected", decided_at: new Date().toISOString() })
    .in("id", ids)
    .eq("status", "pending");
}

export async function approveReview(formData: FormData): Promise<void> {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  if (await apply([id])) {
    await republishSnapshot();
    await refreshWraps();
  }
  done();
}

export async function rejectReview(formData: FormData): Promise<void> {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  await reject([id]);
  done();
}

export async function approveSelected(formData: FormData): Promise<void> {
  if (await apply(idsOf(formData))) {
    await republishSnapshot();
    await refreshWraps();
  }
  done();
}

export async function rejectSelected(formData: FormData): Promise<void> {
  await reject(idsOf(formData));
  done();
}

/** Rejects every pending row older than [days] (default 30). */
export async function rejectOlderThan(formData: FormData): Promise<void> {
  const days = Number(formData.get("days") ?? 30);
  const cutoff = new Date(Date.now() - (Number.isFinite(days) ? days : 30) * 86_400_000)
    .toISOString()
    .slice(0, 10);
  await supabaseAdmin()
    .from("rate_review")
    .update({ status: "rejected", decided_at: new Date().toISOString() })
    .eq("status", "pending")
    .lt("as_of", cutoff);
  done();
}

/** Corrects a held row's rate or date before deciding. Touches only those two columns. */
export async function updateReview(formData: FormData): Promise<void> {
  const id = Number(formData.get("id"));
  const rate = Number(formData.get("new_rate"));
  const asOf = String(formData.get("as_of") ?? "");
  if (!Number.isFinite(id) || !Number.isFinite(rate) || rate <= 0 || rate >= 30) return;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(asOf)) return;
  const db = supabaseAdmin();
  const { data: row } = await db.from("rate_review").select("old_rate").eq("id", id).maybeSingle();
  const old = row?.old_rate == null ? null : Number(row.old_rate);
  await db
    .from("rate_review")
    .update({
      new_rate: rate,
      as_of: asOf,
      delta_bps: old == null ? null : Math.round((rate - old) * 100),
    })
    .eq("id", id)
    .eq("status", "pending");
  done();
}

export async function deleteReview(formData: FormData): Promise<void> {
  const id = Number(formData.get("id"));
  if (!Number.isFinite(id)) return;
  await supabaseAdmin().from("rate_review").delete().eq("id", id);
  done();
}
