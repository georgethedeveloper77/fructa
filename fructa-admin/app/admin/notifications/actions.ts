"use server";

import { revalidatePath } from "next/cache";

export type Segment = "all" | { tag: string; value?: string };

export type SendResult = {
  ok: boolean;
  recipients: number;
  segment?: string;
  error?: string;
};

export interface SendInput {
  title: string;
  body: string;
  target?: string; // markets | portfolio | alerts | fund/<id>
  segment: Segment;
}

// Calls the send-push edge function (which owns the OneSignal REST key and
// writes push_log). The CRON_SECRET lives only in the admin server env — never
// shipped to the browser. Mirrors server.ts's URL fallback so a missing
// SUPABASE_URL doesn't 500 the route.
export async function sendPush(input: SendInput): Promise<SendResult> {
  const title = input.title?.trim();
  const body = input.body?.trim();
  if (!title || !body) {
    return { ok: false, recipients: 0, error: "Title and body are required." };
  }

  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secret = process.env.CRON_SECRET;
  if (!url) return { ok: false, recipients: 0, error: "SUPABASE_URL not set." };
  if (!secret) {
    return { ok: false, recipients: 0, error: "CRON_SECRET not set in the admin environment." };
  }

  try {
    const res = await fetch(`${url}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-cron-secret": secret },
      body: JSON.stringify({
        title,
        body,
        target: input.target || undefined,
        segment: input.segment,
      }),
      cache: "no-store",
    });
    const json = (await res.json().catch(() => ({}))) as Partial<SendResult> & { error?: string };
    revalidatePath("/admin/notifications");
    if (!res.ok || !json.ok) {
      return {
        ok: false,
        recipients: json.recipients ?? 0,
        error: json.error ?? `HTTP ${res.status}`,
      };
    }
    return { ok: true, recipients: json.recipients ?? 0, segment: json.segment };
  } catch (e) {
    return { ok: false, recipients: 0, error: e instanceof Error ? e.message : String(e) };
  }
}
