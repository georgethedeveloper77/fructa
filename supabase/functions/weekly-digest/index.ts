// weekly-digest — "This week in Kenyan yields". Broadcasts to the
// digest_weekly tag (users who left the Weekly digest toggle on). Computes a
// one-line summary from live data so the copy is never stale:
//   - best retail KES money-market rate right now
//   - how many rate moves were recorded in the last 7 days
//
// Runnable manually now (x-cron-secret). A pg_cron schedule (Mon 08:00 EAT)
// is added once the existing cron migration pattern is confirmed. Recorded in
// push_log like every other server send.

import { adminClient } from "../_shared/supabase.ts";
import { sendToTag } from "../_shared/onesignal.ts";

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const db = adminClient();

  // Best current retail KES money-market rate.
  const { data: top } = await db
    .from("funds")
    .select("name,current_rate")
    .eq("kind", "fund")
    .neq("status", "hidden")
    .eq("fund_type", "mmf")
    .eq("currency", "KES")
    .eq("retail", true)
    .order("current_rate", { ascending: false, nullsFirst: false })
    .limit(1);
  const best = top?.[0];

  // Rate moves in the last 7 days.
  const since = new Date(Date.now() - 7 * 86_400_000).toISOString();
  const { data: moves } = await db
    .from("market_events")
    .select("id")
    .eq("type", "rate_change")
    .gte("created_at", since);
  const movers = moves?.length ?? 0;

  const bestLine = best?.current_rate != null
    ? `Top KES money market: ${best.name} at ${Number(best.current_rate).toFixed(2)}%.`
    : "See the week's latest money-market rates.";
  const moveLine = movers > 0
    ? ` ${movers} rate ${movers === 1 ? "move" : "moves"} this week.`
    : "";
  const body = `${bestLine}${moveLine}`;

  const res = await sendToTag("digest_weekly", "true", {
    heading: "This week in Kenyan yields",
    body,
    target: "markets",
  });

  await db.from("push_log").insert({
    title: "This week in Kenyan yields",
    body,
    target: "markets",
    segment: "digest_weekly=true",
    sent_count: res.recipients ?? 0,
    status: res.ok ? "sent" : "error",
    error: res.ok ? null : (res.error ?? null),
  });

  return Response.json({
    ok: res.ok,
    recipients: res.recipients ?? 0,
    movers,
    error: res.error,
  }, { status: res.ok ? 200 : 502 });
});
