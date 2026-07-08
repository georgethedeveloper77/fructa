// emit-events (was notify-rate-change).
// On a rate move it does TWO things:
//   1. writes market_events (rate_change per fund, leader_change per category)
//      -> drives the app's News feed + tile momentum deltas, and the on-device
//         saved-comparison leader-flip recompute.
//   2. sends OneSignal pushes to followers (follow_<id>) and category
//      subscribers (leader_<category>). Events are still recorded even if the
//      OneSignal keys are missing.
//
// Every push now carries a deep-link `data.target` (fund/<id>) so a tap opens
// the right fund. Pushes go through _shared/onesignal.ts, the single sender.
// Gated by x-cron-secret. Called by scrape-aggregator after it writes rates.

import { adminClient } from "../_shared/supabase.ts";
import { oneSignalEnabled, sendToTag } from "../_shared/onesignal.ts";

// Must match the app's Push.tagKey() exactly.
function tagKey(id: string): string {
  return "follow_" + id.replace(/[^a-zA-Z0-9]/g, "_");
}
function leaderTag(category: string): string {
  return "leader_" + category.replace(/[^a-zA-Z0-9]/g, "_");
}

interface Change {
  fundId: string;
  name?: string;
  oldRate: number;
  newRate: number;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const { changes } = (await req.json().catch(() => ({ changes: [] }))) as {
    changes: Change[];
  };
  const db = adminClient();
  const errors: string[] = [];
  let sent = 0;

  if (!changes?.length) {
    return Response.json({ ok: true, sent: 0, events: 0, errors });
  }

  // Category per changed fund (for event scoping + leader detection).
  const ids = changes.map((c) => c.fundId);
  const { data: meta } = await db
    .from("funds")
    .select("id,name,category")
    .in("id", ids);
  const catById: Record<string, string> = {};
  const nameById: Record<string, string> = {};
  for (const m of meta ?? []) {
    catById[m.id] = m.category;
    nameById[m.id] = m.name;
  }

  const events: {
    type: string;
    category: string | null;
    fund_id: string | null;
    payload: Record<string, unknown>;
  }[] = [];

  // -- rate_change per fund --------------------------------------------------
  for (const c of changes) {
    const up = c.newRate > c.oldRate;
    const name = c.name ?? nameById[c.fundId] ?? c.fundId;
    const delta = Number((c.newRate - c.oldRate).toFixed(2));
    events.push({
      type: "rate_change",
      category: catById[c.fundId] ?? null,
      fund_id: c.fundId,
      payload: {
        headline: `${name} ${up ? "rose" : "fell"} to ${c.newRate.toFixed(2)}%`,
        old: c.oldRate,
        new: c.newRate,
        delta,
      },
    });
    const res = await sendToTag(tagKey(c.fundId), "true", {
      heading: name,
      body: `Rate ${up ? "rose" : "fell"} to ${c.newRate.toFixed(2)}% (was ${c.oldRate.toFixed(2)}%)`,
      target: `fund/${c.fundId}`,
    });
    if (res.ok) sent++;
    else if (oneSignalEnabled()) errors.push(`${c.fundId}: ${res.error}`);
  }

  // -- leader_change per affected category -----------------------------------
  const changedIds = new Set(
    changes.filter((c) => c.newRate > c.oldRate).map((c) => c.fundId),
  );
  const cats = [...new Set(Object.values(catById))];
  for (const cat of cats) {
    const { data: top } = await db
      .from("funds")
      .select("id,name,current_rate")
      .eq("category", cat)
      .eq("kind", "fund")
      .neq("status", "hidden")
      .order("current_rate", { ascending: false, nullsFirst: false })
      .limit(1);
    const leader = top?.[0];
    // Emit only when a fund that just ROSE is now the category leader.
    if (leader && changedIds.has(leader.id)) {
      events.push({
        type: "leader_change",
        category: cat,
        fund_id: leader.id,
        payload: {
          headline: `${leader.name} now leads ${cat}`,
          leader: leader.id,
          rate: leader.current_rate,
        },
      });
      const res = await sendToTag(leaderTag(cat), "true", {
        heading: "New category leader",
        body: `${leader.name} now leads ${cat} at ${Number(leader.current_rate).toFixed(2)}%`,
        target: `fund/${leader.id}`,
      });
      if (!res.ok && oneSignalEnabled()) errors.push(`leader ${cat}: ${res.error}`);
    }
  }

  if (events.length) {
    const { error } = await db.from("market_events").insert(events);
    if (error) errors.push(`market_events: ${error.message}`);
  }

  return Response.json({ ok: errors.length === 0, sent, events: events.length, errors });
});
