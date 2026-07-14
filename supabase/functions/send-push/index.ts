// send-push - admin-facing manual broadcast. The admin Notifications page
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
//
// Note the status semantics changed. A send that OneSignal accepted but which
// matched zero devices now comes back ok:false, status:"no_recipients". That is
// still an HTTP 200 from this function (the request was fine, the audience was
// empty), so the admin page must read `status`, not the HTTP code, to know what
// happened. Only a genuine transport or auth failure is a 502.

import { adminClient } from "../_shared/supabase.ts";
import { broadcast, logPush, sendToTag } from "../_shared/onesignal.ts";

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
    return Response.json(
      { ok: false, error: "title and body are required" },
      { status: 400 },
    );
  }

  const seg = b.segment ?? "all";
  const msg = { heading: b.title, body: b.body, target: b.target };

  const res = seg === "all"
    ? await broadcast(msg)
    : await sendToTag(seg.tag, seg.value ?? "true", msg);

  const segLabel = seg === "all" ? "all" : `${seg.tag}=${seg.value ?? "true"}`;

  const db = adminClient();
  const logged = await logPush(db, {
    source: "admin",
    title: b.title,
    body: b.body,
    target: b.target ?? null,
    segment: segLabel,
  }, res);

  // An empty audience is a real answer, not a server fault. Surface it as a 200
  // with status "no_recipients" so the admin sees "reached 0 devices" instead of
  // a red 502 that implies the function itself broke.
  const httpStatus = res.status === "error" ? 502 : 200;

  return Response.json({
    ok: res.ok,
    status: res.status,
    recipients: res.recipients,
    onesignal_id: res.id ?? null,
    segment: segLabel,
    logged,
    error: res.error ?? null,
  }, { status: httpStatus });
});
