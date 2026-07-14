// The ONE place that talks to the OneSignal REST API. emit-events, send-push,
// notify-rate-change, emit-dividend-alerts and weekly-digest all send through
// here, so every push carries a deep-link `data.target` by construction, lands
// on the same Android channel, and is judged by the same definition of "sent".
//
// Keys are server-only (Supabase secrets), never shipped in the app:
//   ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY
//
// Three things in here are load-bearing and were the cause of silent failure:
//
// 1. AUTH STYLE. OneSignal migrated its REST keys. A legacy key is sent as
//    `Authorization: Basic <key>`; a key minted after the migration must be
//    sent as `Authorization: Key <key>`. The wrong prefix is a flat 401. We try
//    Key first, fall back to Basic once, and remember which one worked for the
//    life of the isolate.
//
// 2. ZERO RECIPIENTS IS NOT A SEND. When a tag filter matches nobody, OneSignal
//    returns HTTP 200 with an `errors` array and NO `id`. Reading only res.ok
//    reports that as success. It is not: nothing was delivered. It gets its own
//    status so the audit trail stops lying.
//
// 3. PRIORITY. Android FCM messages sent at normal priority are batched and
//    deferred by Doze. On the Transsion and Xiaomi devices that dominate this
//    market that means "sometimes tomorrow, sometimes never". Every push here
//    goes out at priority 10.

const APP_ID = Deno.env.get("ONESIGNAL_APP_ID");
const REST = Deno.env.get("ONESIGNAL_REST_KEY");

const ENDPOINT = "https://onesignal.com/api/v1/notifications";

/// Must match LocalNotify.channelId in the app. Sharing one channel means the
/// user gets ONE "Rate alerts" switch in Android settings that governs both the
/// server push and the local fallback, instead of two they have to find.
const ANDROID_CHANNEL_ID = "fructa_rates";

/// Monochrome silhouette in android/app/src/main/res/drawable-*. OneSignal looks
/// this name up by convention; without it Android renders the full-colour
/// launcher icon as a white blob.
const SMALL_ICON = "ic_stat_onesignal_default";

/// Fructa gold, ARGB, no leading hash. This is an OS-level tint applied outside
/// the widget tree, so there is no theme token to reach for.
const ACCENT_ARGB = "FFE7B24C";

/// Three days. A rate move is stale after that; do not wake someone on Friday
/// with Tuesday's news.
const TTL_SECONDS = 259200;

export type PushStatus = "sent" | "error" | "no_recipients";

export interface PushMsg {
  heading: string;
  body: string;
  target?: string; // fund/<id> | stock/<id> | markets | portfolio | alerts | settings
}

export interface PushResult {
  ok: boolean;
  status: PushStatus;
  id?: string;
  recipients: number;
  error?: string;
}

export const oneSignalEnabled = (): boolean => !!(APP_ID && REST);

/// Must match the app's Push.tagKey() exactly. Exported so no caller ever
/// hand-rolls it again and drifts.
export function tagKey(fundId: string): string {
  return "follow_" + fundId.replace(/[^a-zA-Z0-9]/g, "_");
}

/// Must match the app's Push.stockTagKey() exactly.
export function stockTagKey(stockId: string): string {
  return "follow_stock_" + stockId.replace(/[^a-zA-Z0-9]/g, "_");
}

function dataFor(target?: string): Record<string, unknown> | undefined {
  return target ? { target } : undefined;
}

// Remembered across calls within one warm isolate so we pay the 401 probe once.
let authStyle: "key" | "basic" | null = null;

function headersFor(style: "key" | "basic"): HeadersInit {
  return {
    "Content-Type": "application/json",
    "Authorization": style === "key" ? `Key ${REST}` : `Basic ${REST}`,
  };
}

const DELIVERY_DEFAULTS = {
  priority: 10,
  ttl: TTL_SECONDS,
  existing_android_channel_id: ANDROID_CHANNEL_ID,
  android_accent_color: ACCENT_ARGB,
  small_icon: SMALL_ICON,
};

async function post(payload: Record<string, unknown>): Promise<PushResult> {
  if (!APP_ID || !REST) {
    return {
      ok: false,
      status: "error",
      recipients: 0,
      error: "ONESIGNAL_APP_ID / ONESIGNAL_REST_KEY not set",
    };
  }

  const body = JSON.stringify({
    app_id: APP_ID,
    ...DELIVERY_DEFAULTS,
    ...payload,
  });

  try {
    let style: "key" | "basic" = authStyle ?? "key";
    let res = await fetch(ENDPOINT, { method: "POST", headers: headersFor(style), body });

    // Only probe the other style if we have never confirmed one.
    if (res.status === 401 && authStyle === null) {
      style = "basic";
      res = await fetch(ENDPOINT, { method: "POST", headers: headersFor(style), body });
    }

    const json = (await res.json().catch(() => ({}))) as {
      id?: string;
      recipients?: number;
      errors?: unknown;
    };

    if (!res.ok) {
      const detail = json.errors ? `: ${JSON.stringify(json.errors)}` : "";
      const hint = res.status === 401
        ? " (both Key and Basic auth were rejected: ONESIGNAL_REST_KEY is wrong or revoked)"
        : "";
      return {
        ok: false,
        status: "error",
        recipients: 0,
        error: `HTTP ${res.status}${detail}${hint}`,
      };
    }

    authStyle = style;

    const recipients = Number(json.recipients ?? 0);

    // 200 with no id, or 200 with zero recipients, means the filter matched
    // nobody. OneSignal considers the request well-formed. The user considers
    // it silence. We side with the user.
    if (!json.id || recipients === 0) {
      const errs = json.errors;
      const why = Array.isArray(errs)
        ? errs.join("; ")
        : errs
        ? JSON.stringify(errs)
        : "matched zero subscribed devices";
      return { ok: false, status: "no_recipients", recipients: 0, error: why };
    }

    return { ok: true, status: "sent", id: json.id, recipients };
  } catch (e) {
    return {
      ok: false,
      status: "error",
      recipients: 0,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/// Send to everyone in a segment (default: OneSignal's built-in "Subscribed
/// Users"). Used by admin "send to all" and any market-wide broadcast.
export function broadcast(
  msg: PushMsg,
  segment = "Subscribed Users",
): Promise<PushResult> {
  return post({
    included_segments: [segment],
    headings: { en: msg.heading },
    contents: { en: msg.body },
    data: dataFor(msg.target),
  });
}

/// Send to the users carrying a tag (e.g. follow_<id>, follow_stock_<id>,
/// digest_weekly). Value defaults to "true" to match the app.
///
/// [unlessMuted] adds a second filter: the device must NOT be carrying that tag.
/// This is how a user's "Rate moves: off" toggle actually reaches the server.
///
/// It is a NOT EXISTS check, not a `= false` check, and that is deliberate. The
/// app writes a mute tag only when the user turns something OFF, so a device
/// that has never touched the setting carries no tag at all. If this filtered on
/// `mute_rate_moves = false` instead, every device already installed would fail
/// to match and the entire user base would go silent until they each opened the
/// app and let it write a tag it had never written before. NOT EXISTS matches
/// them on day one.
export function sendToTag(
  key: string,
  value: string,
  msg: PushMsg,
  opts?: { unlessMuted?: string },
): Promise<PushResult> {
  const filters: Record<string, string>[] = [
    { field: "tag", key, relation: "=", value },
  ];

  if (opts?.unlessMuted) {
    filters.push({ operator: "AND" });
    filters.push({ field: "tag", key: opts.unlessMuted, relation: "not_exists" });
  }

  return post({
    filters,
    headings: { en: msg.heading },
    contents: { en: msg.body },
    data: dataFor(msg.target),
  });
}

/// The mute tags the app writes. Must match Push.muteRateMoves and friends.
export const MUTE_RATE_MOVES = "mute_rate_moves";
export const MUTE_SAVED = "mute_saved";
export const MUTE_COUPONS = "mute_coupons";

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

/// The narrow slice of the Supabase client this module needs. Typed structurally
/// so onesignal.ts does not have to import the client and drag its types in.
interface PushLogWriter {
  from(table: string): {
    insert(row: Record<string, unknown>): Promise<{ error: unknown }>;
  };
}

export interface PushLogRow {
  source: string; // admin | rate_change | dividend | digest | market
  title: string;
  body: string;
  target?: string | null;
  segment: string; // 'all' or '<tagKey>=<value>'
  subjectId?: string | null;
}

/// Record every send, including the ones that reached nobody. A push you cannot
/// see in push_log is a push you cannot debug.
export async function logPush(
  db: PushLogWriter,
  row: PushLogRow,
  res: PushResult,
): Promise<boolean> {
  const { error } = await db.from("push_log").insert({
    source: row.source,
    title: row.title,
    body: row.body,
    target: row.target ?? null,
    segment: row.segment,
    subject_id: row.subjectId ?? null,
    sent_count: res.recipients,
    status: res.status,
    onesignal_id: res.id ?? null,
    error: res.ok ? null : (res.error ?? null),
  });
  return !error;
}
