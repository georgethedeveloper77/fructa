"use server";

import { revalidatePath } from "next/cache";

// Edge functions gate on x-cron-secret. These run synchronously (the aggregator
// writes its scraper_runs row before responding), so a revalidate shows the
// result immediately.
async function callFn(name: string, body?: unknown) {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/${name}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-cron-secret": process.env.CRON_SECRET ?? "",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch { /* non-fatal */ }
  revalidatePath("/admin/scrapers");
  revalidatePath("/admin");
}

// Tag the run as manual so the Scrapers page's health check (which only counts
// scheduled runs) doesn't treat a hand-triggered run as the automatic one.
export async function runAggregator() { await callFn("scrape-aggregator", { trigger: "manual" }); }
export async function rebuildSnapshot() { await callFn("publish-snapshot"); }
