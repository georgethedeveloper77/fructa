// send-push — admin-facing manual broadcast. The admin Notifications page
// invokes this with the CRON_SECRET (server action, key never in the browser).
// Every send is recorded in push_log for the history/audit view.
//
// Body:
//   {
//     "title":   "string, required",
//     "body":    "string, required",
//     "target":  "markets" | "portfolio" | "alerts" | "fund/<id>"   (optional),
//     "segment": "all"                                              (default)
//              | { "tag": "digest_weekly", "value": "true" }        (tag segment)
//   }
//
// Gated by x-cron-secret.

import { adminClient } from "../_shared/supabase.ts";
import { broadcast, sendToTag } from "../_shared/onesignal.ts";

interface Body {
  title?: string;
  body?: string;
  target?: string;
  segment?: "all" | { tag: string; value?: string };
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const b = (await req.json().catch(() => null)) as Body | null;
  if (!b?.title || !b?.body) {
    return Response.json({ ok: false, error: "title and body are required" }, { status: 400 });
  }

  const seg = b.segment ?? "all";
  const msg = { heading: b.title, body: b.body, target: b.target };

  const res = seg === "all"
    ? await broadcast(msg)
    : await sendToTag(seg.tag, seg.value ?? "true", msg);

  const segLabel = seg === "all" ? "all" : `${seg.tag}=${seg.value ?? "true"}`;

  const db = adminClient();
  const { error: logErr } = await db.from("push_log").insert({
    title: b.title,
    body: b.body,
    target: b.target ?? null,
    segment: segLabel,
    sent_count: res.recipients ?? 0,
    status: res.ok ? "sent" : "error",
    error: res.ok ? null : (res.error ?? null),
  });

  return Response.json({
    ok: res.ok,
    recipients: res.recipients ?? 0,
    segment: segLabel,
    logged: !logErr,
    error: res.error,
  }, { status: res.ok ? 200 : 502 });
});
