import { adminClient } from "../_shared/supabase.ts";
import { publishSnapshot } from "../_shared/snapshot.ts";
import type { StockPriceAdapter, StockPriceRow } from "../_shared/types.ts";
import { mystocksAdapter, MYSTOCKS_URL } from "./adapters/mystocks-nse.ts";

// NSE end-of-day price ingestion.
//
// Separate from scrape-aggregator on purpose: that lane writes rate_history and
// validates against a 0-30% yield band. A share price is not a yield and would
// be rejected outright.
//
// ── ON THE DATA ────────────────────────────────────────────────────────────
// This publishes end-of-day closing prices for NSE-listed companies, which are
// facts of public record, printed daily in Kenyan newspapers and published by
// numerous public sites. Fructa is informational: it displays prices, it does
// not execute trades and is not a trading venue.
//
// The figures Fructa derives from these closes (day change, sparkline, dividend
// yield) are its own computed values, held on Fructa's own stored series.
//
// `stocks.prices_enabled` remains as a KILL SWITCH, not a licence gate: set it
// false and this function stops and the app hides every price surface with no
// deploy required. That is worth keeping for reasons that have nothing to do
// with licensing (a bad parse, a source outage, a wrong number in the wild).
//
// ── WHY THIS WAS REWRITTEN: THE 504 ────────────────────────────────────────
// The first version died with
//   HTTP 504 {"code":"IDLE_TIMEOUT","message":"Request idle timeout limit (150s) reached"}
// and admin showed "never run" against an empty stock_prices table. Three bugs,
// each of which hid the others:
//
//   1. THE FETCH HAD NO TIMEOUT. If afx does not answer (a blocked user agent, a
//      blocked datacenter IP, a slow handshake) the socket simply hangs.
//      IDLE_TIMEOUT means "nothing happened for 150 seconds", which is the
//      signature of a hung socket, not of slow code.
//
//   2. scraper_runs WAS WRITTEN LAST, so a killed function logged NOTHING. The
//      failure erased its own evidence, and the Scrapers page truthfully said
//      "never run" because from the database's point of view it never had. A
//      scraper that cannot record its own death is a scraper nobody will fix.
//
//   3. publishSnapshot RAN INLINE, ahead of that insert. A full rebuild (funds,
//      ~18k rate_history rows, insurers, learn, blog, composition) sat on the
//      critical path in front of the one write that would have explained any of
//      this.
//
// Order is now: fetch (bounded) -> write prices -> WRITE THE RUN ROW -> publish.
// Everything past the run row is best effort. Whatever happens, there is a
// record.
//
// Invoke: pg_cron on trading days after the close, or the admin re-run button.
// ── SOURCE HEALTH: cooldown and backoff ────────────────────────────────────
//
// afx started dropping our requests silently. The wrong response to that is to
// keep knocking every weekday forever: a host that has decided it does not like
// you likes you less after the two hundredth request.
//
// The ladder is deliberately slow to start. The cron already fires once a
// weekday, so one or two failures need no cooldown at all: tomorrow's scheduled
// run IS the retry. Cooldown is for a source that is properly down.
function cooldownDays(consecutiveFailures: number): number {
  if (consecutiveFailures < 3) return 0;   // tomorrow's run is the retry
  if (consecutiveFailures === 3) return 3;
  if (consecutiveFailures === 4) return 7;
  return 14;                                // cap. Never give up entirely.
}

type Health = {
  source: string;
  consecutive_failures: number;
  blocked_until: string | null;
};

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const trigger = body?.trigger === "manual" ? "manual" : "cron";
  // Deliberate override for backfilling a specific missed day. Not a default.
  const force = body?.force === true;

  // ── INGEST MODE ───────────────────────────────────────────────────────────
  // A caller may POST an already-fetched board instead of asking this function
  // to go and get one:
  //
  //   { "rows": [{ "ticker": "SCOM", "close": 34.2, "prevClose": 34.05 }, ...],
  //     "source": "mystocks-nse", "trigger": "cron" }
  //
  // This exists because afx BLOCKS SUPABASE'S EGRESS. The edge functions run in
  // eu-central-1, and afx drops those packets silently: no 403, no 429, just no
  // answer until the socket dies. A browser user agent did not help, which is
  // how we know it is the address and not the header.
  //
  // So the fetch moves to a GitHub Actions runner, whose IP looks like an
  // ordinary client, exactly as ke-cbk-tbills already does. The runner does the
  // ONE thing it has to do from outside: fetch and parse. Everything that
  // matters (ticker mapping, the sanity band, prev_close from our own stored
  // series, source health, the run log, the snapshot) stays HERE, in one place,
  // where it is tested and where it cannot drift per-runner.
  const postedRows = Array.isArray(body?.rows)
    ? (body.rows as StockPriceRow[])
    : null;
  const postedSource = typeof body?.source === "string" ? body.source : "mystocks-nse";

  const db = adminClient();
  const source = "ke-nse";
  const startedAt = new Date().toISOString();
  const t0 = Date.now();

  const errors: string[] = [];
  const unmapped: string[] = [];
  let written = 0;

  /** Always leave a record, including on the paths that used to die silently. */
  const log = async (ok: boolean) => {
    await db.from("scraper_runs").insert({
      source,
      trigger,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      written,
      rejected: 0,
      unmapped,
      errors,
      ok,
    });
  };

  // EAT is UTC+3. The board we read is the close of the Nairobi trading day.
  const eatNow = new Date(Date.now() + 3 * 3_600_000);
  const asOf = eatNow.toISOString().slice(0, 10);
  const dow = eatNow.getUTCDay(); // 0 Sun, 6 Sat, read in EAT terms

  // The NSE trades Monday to Friday, 09:00 to 15:00 EAT. afx leaves Friday's
  // board up all weekend, so a manual re-run on a Saturday would store Friday's
  // closes under Saturday's date: a trading day that never happened, followed by
  // a fabricated flat Monday. The cron only fires on weekdays. This guards the
  // BUTTON, which the cron schedule never could.
  if ((dow === 0 || dow === 6) && !force) {
    errors.push(`${asOf} is a weekend in EAT. The NSE did not trade. Nothing written.`);
    await log(false);
    return Response.json({ source, skipped: "weekend", as_of: asOf, errors });
  }

  // Kill switch.
  const { data: cfg } = await db
    .from("app_config")
    .select("value")
    .eq("key", "stocks.prices_enabled")
    .maybeSingle();
  if (cfg?.value !== true) {
    // Deliberately NOT logged as a failed run. Switching prices off is a choice,
    // not a fault, and it must not paint the Scrapers page red.
    return Response.json({
      source,
      skipped: "stocks.prices_enabled is false",
    });
  }

  const feedUrl = Deno.env.get("NSE_PRICES_URL") ?? MYSTOCKS_URL;

  // ticker -> stock_id. Exact, uppercase, no fuzzy matching: a ticker is an
  // identifier, not a label. A ticker we do not hold is REPORTED, never
  // silently dropped, because that is how we find out about a new listing.
  // (Family Bank listed on 23 June 2026 and is not yet in `stocks`. It will
  // surface here as unmapped on the first run, which is the system telling us
  // the truth rather than quietly showing a 62-company market as complete.)
  const { data: stockRows } = await db.from("stocks").select("id,ticker");
  const idByTicker: Record<string, string> = {};
  for (const s of stockRows ?? []) {
    idByTicker[String(s.ticker).trim().toUpperCase()] = s.id;
  }

  // The chain. Tried IN ORDER; first usable board wins and we stop.
  //
  // A FAILOVER, never a merge. Two sources that disagree are a problem to
  // surface, not a pair of numbers to average: an average is a third number that
  // no source published and no trade ever happened at.
  //
  // afx is NOT here, and is not coming back. It blocks datacenter IP ranges:
  // four attempts across two networks (Supabase eu-central-1, a GitHub runner)
  // and three clients (Deno fetch with a bot UA, Deno fetch with a Chrome UA,
  // and real Chromium). Always silence, never once a status code.
  //
  // mystocks replaced it ON EVIDENCE. Probed from the exact runner that scrapes
  // it: HTTP 200 in 1.9s, no auth wall, 30 of 30 known tickers, SCOM at 35.05,
  // which is the same price afx quoted. Two of its sibling URLs were rejected in
  // the same probe, and both would have passed a naive check: /price_list/
  // returned 200 and bounced to a login, and /m/ quoted SCOM at 1.44.
  const adapters: StockPriceAdapter[] = [mystocksAdapter(feedUrl)];

  type PxRow = {
    stock_id: string;
    as_of: string;
    close_kes: number;
    prev_close: number | null;
    day_high: number | null;
    day_low: number | null;
    volume: number | null;
    source: string;
  };
  const points: PxRow[] = [];

  // Cooldown state. A manual re-run IGNORES it: when a human presses the button
  // they are asking "is it back yet?", and refusing to answer because of a timer
  // we invented ourselves would be obnoxious.
  const { data: healthRows } = await db
    .from("source_health")
    .select("source,consecutive_failures,blocked_until");
  const healthBySource: Record<string, Health> = {};
  for (const h of (healthRows ?? []) as Health[]) healthBySource[h.source] = h;

  let usedSource: string | null = null;

  /** Map + validate one board into rows we will store. Shared by BOTH paths, so
   *  a board that arrives from a GitHub runner is held to exactly the same
   *  standard as one this function fetched itself. Two copies of a sanity band
   *  is one copy too many. */
  const ingest = (rows: StockPriceRow[], adapterId: string) => {
    for (const row of rows) {
      const id = idByTicker[String(row.ticker).trim().toUpperCase()];
      if (!id) {
        // Reported, never silently dropped: this is how we learn about a new
        // listing rather than quietly showing a 62-company market as complete.
        unmapped.push(`${adapterId}:${row.ticker}`);
        continue;
      }
      // Sanity band only. The 0-30 yield rule from validate.ts does not apply to
      // a price. Reject the impossible, not the merely surprising: KUKZ trades
      // near 390 and KURV near 1,355, so a tight band would throw away real
      // prices.
      if (!Number.isFinite(row.close) || row.close <= 0 || row.close > 100_000) {
        errors.push(`${row.ticker}: close out of band (${row.close})`);
        continue;
      }
      points.push({
        stock_id: id,
        as_of: row.asOf ?? asOf,
        close_kes: row.close,
        prev_close: row.prevClose ?? null,
        day_high: row.high ?? null,
        day_low: row.low ?? null,
        volume: row.volume ?? null,
        source: adapterId,
      });
    }
  };

  if (postedRows) {
    // A runner already did the fetching. Nothing to time out, nothing to block.
    // The board carries its OWN date, and we store prices under that date, not
    // under today's. The NSE shuts on public holidays and mystocks leaves the
    // last session's board up when it does. Stamping that with today would
    // invent a trading day that never happened, and prev_close would then
    // compute a day move across a seam where nobody traded.
    //
    // But an old board is also how a dead source kills you quietly, so: if the
    // board is more than a week stale, refuse it. A source that keeps serving
    // last month's prices with a straight face is worse than one that is down.
    const boardDate = postedRows[0]?.asOf ?? null;
    if (boardDate) {
      const ageDays =
        (Date.parse(asOf) - Date.parse(boardDate)) / 86_400_000;
      if (ageDays > 7) {
        errors.push(
          `${postedSource}: board is dated ${boardDate}, which is ${Math.round(ageDays)} ` +
            "days old. Refusing it. The source may be frozen.",
        );
        postedRows.length = 0;
      }
    }

    if (postedRows.length < 40) {
      errors.push(
        `${postedSource}: only ${postedRows.length} rows posted, expected 60 or ` +
          "more. Refusing a partial board.",
      );
    } else {
      ingest(postedRows, postedSource);
      usedSource = postedSource;
      await db.from("source_health").upsert(
        {
          source: postedSource,
          consecutive_failures: 0,
          blocked_until: null,
          last_ok_at: new Date().toISOString(),
          last_error: null,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "source" },
      );
    }
  } else {
    for (const adapter of adapters) {
      const h = healthBySource[adapter.id];
      const cooling =
        h?.blocked_until != null && h.blocked_until > asOf && trigger !== "manual";

      if (cooling) {
        errors.push(
          `${adapter.id}: in cooldown until ${h.blocked_until} after ` +
            `${h.consecutive_failures} consecutive failures. Skipped.`,
        );
        continue;
      }

      try {
        const rows = await adapter.fetchRows();
        ingest(rows, adapter.id);
        usedSource = adapter.id;

        await db.from("source_health").upsert(
          {
            source: adapter.id,
            consecutive_failures: 0,
            blocked_until: null,
            last_ok_at: new Date().toISOString(),
            last_error: null,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "source" },
        );
        break; // first usable board wins
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        errors.push(`${adapter.id}: ${msg}`);

        const fails = (healthBySource[adapter.id]?.consecutive_failures ?? 0) + 1;
        const days = cooldownDays(fails);
        const until = days === 0
          ? null
          : new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);

        await db.from("source_health").upsert(
          {
            source: adapter.id,
            consecutive_failures: fails,
            blocked_until: until,
            last_error: msg.slice(0, 500),
            updated_at: new Date().toISOString(),
          },
          { onConflict: "source" },
        );

        if (until) {
          errors.push(
            `${adapter.id}: ${fails} consecutive failures, backing off until ${until}.`,
          );
        }
      }
    }
  }

  // Nothing usable. Log it and stop. An empty run that reports itself is
  // recoverable; an empty run that says nothing is what put us here.
  if (points.length === 0) {
    if (errors.length === 0) errors.push("adapter returned no usable rows");
    await log(false);
    return Response.json({ source, trigger, as_of: asOf, written: 0, unmapped, errors });
  }

  // prev_close comes from OUR OWN previous stored close, not from the source's
  // change column. We know what our number means; we would be guessing at
  // theirs.
  //
  // The window is bounded to 21 days now. The old query was `.in(ids)` ordered
  // desc with NO LIMIT, which reads every price row ever stored for all 64
  // stocks to answer the question "what was yesterday". Harmless while the table
  // is empty. In a year it is tens of thousands of rows, on a function that was
  // already timing out.
  try {
    const since = new Date(Date.now() - 21 * 86_400_000).toISOString().slice(0, 10);
    const ids = [...new Set(points.map((p) => p.stock_id))];
    const { data: lastRows } = await db
      .from("stock_prices")
      .select("stock_id,close_kes,as_of")
      .in("stock_id", ids)
      .gte("as_of", since)
      .lt("as_of", asOf) // strictly earlier, now enforced in SQL as well
      .order("as_of", { ascending: false });

    const lastByStock: Record<string, { close: number; asOf: string }> = {};
    for (const r of lastRows ?? []) {
      if (!lastByStock[r.stock_id]) {
        lastByStock[r.stock_id] = { close: Number(r.close_kes), asOf: r.as_of };
      }
    }
    for (const p of points) {
      const prior = lastByStock[p.stock_id];
      // Re-running on the same day must not set prev_close to today's own close,
      // which would render every stock as a flat 0.00%.
      if (p.prev_close == null && prior && prior.asOf < p.as_of) {
        p.prev_close = prior.close;
      }
    }
  } catch (e) {
    // A missing prev_close costs a day change, not a price. Carry on.
    errors.push(`prev_close lookup: ${e instanceof Error ? e.message : String(e)}`);
  }

  const { error: upsertErr } = await db
    .from("stock_prices")
    .upsert(points, { onConflict: "stock_id,as_of" });

  if (upsertErr) {
    errors.push(`upsert: ${upsertErr.message}`);
    await log(false);
    return Response.json({ source, trigger, as_of: asOf, written: 0, unmapped, errors });
  }
  written = points.length;

  // THE RUN IS NOW ON THE RECORD, before anything heavy runs.
  //
  // publishSnapshot used to sit HERE, inline, ahead of this insert. It is the
  // single heaviest thing this function does, and it stood in front of the only
  // write that could have told anyone the function was dying.
  await log(errors.length === 0);

  // Republish so the app sees the new closes. Best effort: the prices are
  // already stored and the run is already logged, so the worst case is a stale
  // app until the next rebuild, which is exactly what the "Rebuild snapshot"
  // button is for.
  let snapshot: unknown = null;
  try {
    snapshot = await publishSnapshot(db);
  } catch (e) {
    errors.push(`snapshot: ${e instanceof Error ? e.message : String(e)}`);
    // Amend the row we just wrote rather than losing the detail.
    await db
      .from("scraper_runs")
      .update({ errors, ok: false })
      .eq("source", source)
      .eq("started_at", startedAt);
  }

  return Response.json({
    source,
    // WHICH adapter actually produced the board. With a chain, "the scraper ran"
    // is no longer the same statement as "afx answered", and conflating them is
    // how you end up not noticing that your primary source has been dead for a
    // month while a fallback quietly carries the app.
    used_source: usedSource,
    trigger,
    as_of: asOf,
    written,
    unmapped,
    ms: Date.now() - t0,
    snapshot,
    errors,
  });
});
