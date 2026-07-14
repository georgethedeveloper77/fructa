// notify-rate-change - one OneSignal push per changed fund, targeted by the
// per-fund tag so only users who follow that fund are notified. Called by the
// scrapers after a rate moves. Gated by x-cron-secret.
//
// This used to hand-roll its own fetch against the OneSignal REST API, which is
// how it drifted from _shared/onesignal.ts and acquired three bugs:
//
//   - it counted `res.ok` as a delivery, so a filter that matched zero devices
//     was reported as a successful send;
//   - it never wrote to push_log, so there was no record of any of it;
//   - it sent at default FCM priority, which Doze defers on exactly the Android
//     hardware this app runs on.
//
// It now goes through the shared sender like everything else.
//
// Body:
//   { "changes": [ { "fundId": "...", "name": "...", "oldRate": 12.0, "newRate": 12.34 } ] }

import { adminClient } from "../_shared/supabase.ts";
import {
  logPush,
  MUTE_RATE_MOVES,
  oneSignalEnabled,
  sendToTag,
  tagKey,
} from "../_shared/onesignal.ts";

interface Change {
  fundId: string;
  name?: string;
  oldRate: number;
  newRate: number;
}

function bodyFor(c: Change): string {
  const up = c.newRate > c.oldRate;
  const verb = up ? "rose" : "fell";
  return `Rate ${verb} to ${Number(c.newRate).toFixed(2)}% (was ${Number(c.oldRate).toFixed(2)}%)`;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!oneSignalEnabled()) {
    return Response.json(
      { ok: false, error: "ONESIGNAL_APP_ID / ONESIGNAL_REST_KEY not set" },
      { status: 500 },
    );
  }

  const { changes } = (await req.json().catch(() => ({ changes: [] }))) as {
    changes: Change[];
  };

  const db = adminClient();

  let sent = 0; // reached at least one device
  let empty = 0; // OneSignal accepted it and matched nobody
  const errors: string[] = [];

  for (const c of changes ?? []) {
    if (!c?.fundId || typeof c.oldRate !== "number" || typeof c.newRate !== "number") {
      errors.push(`${c?.fundId ?? "unknown"}: malformed change`);
      continue;
    }

    const key = tagKey(c.fundId);
    const heading = c.name ?? "Rate update";
    const body = bodyFor(c);

    // unlessMuted is what makes the Settings toggle real. Until now the app's
    // "Rate moves" switch wrote to Hive and nothing else, so a user who turned
    // it off kept getting these pushes forever.
    const res = await sendToTag(
      key,
      "true",
      { heading, body, target: `fund/${c.fundId}` },
      { unlessMuted: MUTE_RATE_MOVES },
    );

    await logPush(db, {
      source: "rate_change",
      title: heading,
      body,
      target: `fund/${c.fundId}`,
      segment: `${key}=true AND ${MUTE_RATE_MOVES} not_exists`,
      subjectId: c.fundId,
    }, res);

    if (res.status === "sent") sent++;
    else if (res.status === "no_recipients") empty++;
    else errors.push(`${c.fundId}: ${res.error ?? "unknown error"}`);
  }

  // `empty` is not an error. Nobody follows that fund yet, which is a perfectly
  // ordinary state for a 200-fund universe. It IS a number worth watching: if
  // every send is empty while users insist they are following, the tags are not
  // reaching OneSignal and the app side is the problem, not this function.
  return Response.json({
    ok: errors.length === 0,
    sent,
    no_recipients: empty,
    errors,
  });
});
