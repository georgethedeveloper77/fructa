// build-wraps: builds, publishes and keeps the market stories.
//
// Runs hourly from pg_cron (0081). Every run is idempotent:
//   1. Today: if something moved well beyond its normal week, today's stories
//      go live (at most story.daily_max). A quiet day writes nothing.
//   2. This week: the draft is refreshed with the week so far. On the publish
//      day and hour (Friday 18:00 Nairobi by default) it goes live and the
//      push goes to the digest_weekly tag, once. A missed Friday is caught up
//      on the next run.
//   3. On the 1st: the month that just ended goes live, and the quarter and
//      the year when they end too.
//   4. wraps.json is written to the snapshots bucket with every live wrap the
//      app lists, newest first.
//
// Admin can call it with a body:
//   { "rebuild": "week-2026-10-16" }            rebuild one wrap (keeps hold)
//   { "rebuild": "...", "force": true }         also replace operator edits
//   { "publish_only": true }                    rewrite wraps.json only
//   { "backfill": true }                        build every past period the
//                                               history supports (no pushes)
//
// A wrap an operator edited keeps its stories on every automatic run. A held
// wrap stays held and is left out of wraps.json and the push.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.85.0";
import { adminClient } from "../_shared/supabase.ts";
import { logPush, sendToTag } from "../_shared/onesignal.ts";
import {
  addDays,
  buildDay,
  buildRange,
  type Cfg,
  closedPeriods,
  dayRow,
  leadOf,
  loadCfg,
  loadMarket,
  nairobiNow,
  type Period,
  periodLabel,
  type Story,
  weekEnd,
  weekRow,
  type WrapRow,
} from "../_shared/wraps.ts";

type Meta = Omit<WrapRow, "stories" | "lead">;
type Status = "draft" | "live" | "held";
interface Current {
  status: Status;
  edited: boolean;
  stories: Story[];
  published_at: string | null;
  pushed_at: string | null;
}

/** Enough history before a period for each fund's normal week (12 weeks) and margin. */
const LOOKBACK_DAYS = 100;

const BUCKET = "snapshots";
const FILE = "wraps.json";

/** How many live wraps of each period the app lists. */
const KEEP: Record<Period, number> = { day: 14, week: 26, month: 24, quarter: 12, year: 10 };

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }
  const body = (await req.json().catch(() => ({}))) as {
    rebuild?: string;
    force?: boolean;
    publish_only?: boolean;
    backfill?: boolean;
  };
  const db = adminClient();
  const log: string[] = [];

  try {
    if (body.publish_only) {
      const n = await publishIndex(db);
      return Response.json({ ok: true, published: n });
    }

    const cfg = await loadCfg(db);

    if (body.backfill) {
      const n = await backfill(db, cfg, !!body.force, log);
      const published = await publishIndex(db);
      return Response.json({ ok: true, built: n, published, log: log.slice(-20) });
    }

    if (body.rebuild) {
      const meta = metaFromId(body.rebuild);
      if (!meta) return Response.json({ ok: false, error: "unknown wrap id" }, { status: 400 });
      const today = nairobiNow().day;
      const to = meta.period_end > today ? today : meta.period_end;
      const m = await loadMarket(db, addDays(meta.period_start, -LOOKBACK_DAYS), to);
      const stories = meta.period === "day"
        ? buildDay(m, meta.period_end, cfg)
        : buildRange(m, meta.period_start, to, cfg, await recentWeekStories(db, meta, cfg));
      const cur = await current(db, meta.id);
      const status: Status = cur?.status ?? (meta.period_end > today ? "draft" : "live");
      await save(db, meta, stories, status, cur, !!body.force);
      log.push(`rebuilt ${meta.id}: ${stories.length} stories`);
      const n = await publishIndex(db);
      return Response.json({ ok: true, log, published: n });
    }

    if (!cfg.enabled) {
      return Response.json({ ok: true, log: ["story.enabled is off"] });
    }

    const now = nairobiNow();
    const end = weekEnd(now.day, cfg.publishDow);
    const week = weekRow(end);
    const lastWeek = weekRow(addDays(end, -7));
    const closed = closedPeriods(now.day);
    const earliest = [week.period_start, lastWeek.period_start, ...closed.map((c) => c.period_start)].sort()[0];
    const m = await loadMarket(db, addDays(earliest, -LOOKBACK_DAYS), now.day);

    // 1. Today.
    const dayStories = buildDay(m, now.day, cfg);
    if (dayStories.length) {
      const meta = dayRow(now.day);
      await save(db, meta, dayStories, "live", await current(db, meta.id), false);
      log.push(`day ${now.day}: ${dayStories.length} stories`);
    }

    // 2. Last week, if a missed Friday left it as a draft, then this week.
    for (const meta of [lastWeek, week]) {
      const cur = await current(db, meta.id);
      const due = now.day > meta.period_end ||
        (now.day === meta.period_end && now.hour >= cfg.publishHour);
      if (meta === lastWeek && (!cur || cur.status !== "draft")) continue;
      const to = meta.period_end > now.day ? now.day : meta.period_end;
      const stories = buildRange(m, meta.period_start, to, cfg, await recentWeekStories(db, meta, cfg));
      const status: Status = cur?.status === "live" || due ? "live" : "draft";
      const saved = await save(db, meta, stories, status, cur, false);
      log.push(`${meta.id}: ${saved.status}, ${saved.stories.length} stories`);
      if (saved.status === "live" && !saved.pushed_at && cfg.weeklyPush && saved.stories.length) {
        log.push(await pushWeek(db, meta, saved.stories));
      }
    }

    // 3. Months, quarters and years that ended yesterday.
    for (const meta of closed) {
      const cur = await current(db, meta.id);
      if (cur && cur.status !== "draft") continue;
      const stories = buildRange(m, meta.period_start, meta.period_end, cfg);
      await save(db, meta, stories, "live", cur, false);
      log.push(`${meta.id}: ${stories.length} stories`);
    }

    const n = await publishIndex(db);
    return Response.json({ ok: true, log, published: n });
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    return Response.json({ ok: false, error, log }, { status: 500 });
  }
});

/**
 * Builds every past period the rate history can support, oldest first, so
 * the archive is complete from the first week with enough data. Days only go
 * back 90 days and only where something moved. Existing wraps are left alone
 * unless [force]. Nothing is pushed: these are history, not news.
 */
async function backfill(db: SupabaseClient, cfg: Cfg, force: boolean, log: string[]): Promise<number> {
  const { data: first } = await db
    .from("rate_history")
    .select("as_of")
    .order("as_of", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (!first?.as_of) return 0;
  const now = nairobiNow();
  // A fund's normal week needs some weeks behind it; start four weeks in.
  const start = addDays(first.as_of as string, 28);
  const m = await loadMarket(db, first.as_of as string, now.day);

  const { data: have } = await db.from("wraps").select("id");
  const exists = new Set((have ?? []).map((r) => r.id as string));
  let built = 0;

  const put = async (meta: Meta, stories: Story[]) => {
    if (!stories.length || (exists.has(meta.id) && !force)) return;
    await save(db, meta, stories, "live", force ? null : await current(db, meta.id), force);
    // Backfilled weeks are history: mark them pushed so a late run never
    // sends a push for an old week.
    if (meta.period === "week") {
      await db.from("wraps").update({ pushed_at: new Date().toISOString() }).eq("id", meta.id).is("pushed_at", null);
    }
    exists.add(meta.id);
    built++;
  };

  // Weeks, up to the last one that has closed.
  const thisWeekEnd = weekEnd(now.day, cfg.publishDow);
  for (let end = weekEnd(start, cfg.publishDow); end < thisWeekEnd; end = addDays(end, 7)) {
    const meta = weekRow(end);
    await put(meta, buildRange(m, meta.period_start, end, cfg, await recentWeekStories(db, meta, cfg)));
  }

  // Months, quarters and years, as each closed.
  for (let day = start; day <= now.day; day = addDays(day, 1)) {
    if (!day.endsWith("-01")) continue;
    for (const meta of closedPeriods(day)) {
      if (meta.period_start < first.as_of) continue;
      await put(meta, buildRange(m, meta.period_start, meta.period_end, cfg));
    }
  }

  // Days that moved, over the last 90 days.
  for (let day = addDays(now.day, -90); day < now.day; day = addDays(day, 1)) {
    if (day < start) continue;
    await put(dayRow(day), buildDay(m, day, cfg));
  }

  log.push(`backfilled ${built} wraps from ${start}`);
  return built;
}

/** The period a wrap id names, or null. */
function metaFromId(id: string): Meta | null {
  let x: RegExpMatchArray | null;
  if ((x = id.match(/^day-(\d{4}-\d{2}-\d{2})$/))) return dayRow(x[1]);
  if ((x = id.match(/^week-(\d{4}-\d{2}-\d{2})$/))) return weekRow(x[1]);
  if ((x = id.match(/^month-(\d{4})-(\d{2})$/))) {
    const first = `${x[1]}-${x[2]}-01`;
    const next = new Date(Date.UTC(Number(x[1]), Number(x[2]), 1)).toISOString().slice(0, 10);
    return { id, period: "month", period_start: addDays(first, -1), period_end: addDays(next, -1) };
  }
  if ((x = id.match(/^quarter-(\d{4})-q([1-4])$/))) {
    const y = Number(x[1]);
    const q = Number(x[2]);
    const first = `${y}-${String((q - 1) * 3 + 1).padStart(2, "0")}-01`;
    const next = new Date(Date.UTC(y, q * 3, 1)).toISOString().slice(0, 10);
    return { id, period: "quarter", period_start: addDays(first, -1), period_end: addDays(next, -1) };
  }
  if ((x = id.match(/^year-(\d{4})$/))) {
    const y = Number(x[1]);
    return { id, period: "year", period_start: `${y - 1}-12-31`, period_end: `${y}-12-31` };
  }
  return null;
}

async function current(db: SupabaseClient, id: string): Promise<Current | null> {
  const { data } = await db
    .from("wraps")
    .select("status,edited,stories,published_at,pushed_at")
    .eq("id", id)
    .maybeSingle();
  return (data as Current | null) ?? null;
}

/** Stories from the last few live weeks before [meta], for the no-repeat rule. */
async function recentWeekStories(db: SupabaseClient, meta: Meta, cfg: Cfg): Promise<Story[]> {
  if (meta.period !== "week") return [];
  const { data } = await db
    .from("wraps")
    .select("stories")
    .eq("period", "week")
    .eq("status", "live")
    .lt("period_end", meta.period_end)
    .order("period_end", { ascending: false })
    .limit(Math.max(0, cfg.repeatWeeks));
  return (data ?? []).flatMap((r) => (r.stories ?? []) as Story[]);
}

/**
 * Writes a wrap. A held wrap stays held; an operator's edits survive unless
 * [force]; a wrap that went live keeps its first published time.
 */
async function save(
  db: SupabaseClient,
  meta: Meta,
  built: Story[],
  wanted: Status,
  cur: Current | null,
  force: boolean,
): Promise<{ status: Status; stories: Story[]; pushed_at: string | null }> {
  const keepEdits = !!cur?.edited && !force;
  const stories = keepEdits ? cur!.stories : built;
  const status: Status = cur?.status === "held" ? "held" : wanted;
  const nowIso = new Date().toISOString();
  const { error } = await db.from("wraps").upsert({
    ...meta,
    stories,
    lead: leadOf(stories),
    status,
    edited: keepEdits,
    built_at: nowIso,
    published_at: status === "live" ? (cur?.published_at ?? nowIso) : (cur?.published_at ?? null),
    updated_at: nowIso,
  });
  if (error) throw new Error(`save ${meta.id}: ${error.message}`);
  return { status, stories, pushed_at: cur?.pushed_at ?? null };
}

/** The Friday push, once per week, to everyone who left the weekly wrap on. */
async function pushWeek(db: SupabaseClient, meta: Meta, stories: Story[]): Promise<string> {
  const heading = "Your weekly wrap is ready";
  const lead = stories[0];
  const body = `${lead.title} ${lead.big}. ${stories.length} ${stories.length === 1 ? "story" : "stories"} this week.`;
  const res = await sendToTag("digest_weekly", "true", { heading, body, target: "wrap" });
  await logPush(db, { source: "digest", title: heading, body, target: "wrap", segment: "digest_weekly=true" }, res);
  if (res.ok) {
    await db.from("wraps").update({ pushed_at: new Date().toISOString() }).eq("id", meta.id);
  }
  return `push ${meta.id}: ${res.status}, ${res.recipients} recipients`;
}

/** Writes wraps.json: every live wrap the app lists, newest first in each period. */
async function publishIndex(db: SupabaseClient): Promise<number> {
  const out: unknown[] = [];
  for (const period of Object.keys(KEEP) as Period[]) {
    const { data, error } = await db
      .from("wraps")
      .select("id,period,period_start,period_end,lead,stories,published_at")
      .eq("period", period)
      .eq("status", "live")
      .order("period_end", { ascending: false })
      .limit(KEEP[period]);
    if (error) throw new Error(`wraps: ${error.message}`);
    for (const r of data ?? []) {
      out.push({
        id: r.id,
        period: r.period,
        start: r.period_start,
        end: r.period_end,
        label: periodLabel(r as { id: string; period: Period; period_start: string; period_end: string }),
        lead: r.lead,
        published_at: r.published_at,
        stories: r.stories,
      });
    }
  }
  const json = JSON.stringify({ v: 1, built_at: new Date().toISOString(), wraps: out });
  const { error } = await db.storage.from(BUCKET).upload(FILE, new TextEncoder().encode(json), {
    upsert: true,
    contentType: "application/json",
    cacheControl: "60",
  });
  if (error) throw new Error(`wraps.json upload failed: ${error.message}`);
  return out.length;
}

